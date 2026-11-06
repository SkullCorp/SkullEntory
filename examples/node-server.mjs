// Exemple minimal de web app compatible SkullBridge (Node 18+, aucune dépendance).
//   node examples/node-server.mjs
//   → dans l'app : URL = http://<ip-du-pc>:3000/api/widget , jeton = secret
import http from "node:http";

const TOKEN = process.env.TOKEN ?? "secret";
const state = { stock: 128, low: 3, orders: 5, lastScan: null };

// Le JSON affiché par le widget. Tous les champs sont optionnels.
const widget = () => ({
  title: "Inventaire",
  subtitle: state.lastScan ? `Scan ${state.lastScan}` : "Atelier",
  icon: "shippingbox.fill",
  tint: "#FF9534",
  url: "http://localhost:3000/",
  refresh: 900,
  value: state.stock,
  unit: "articles",
  gauge: { value: state.stock, min: 0, max: 200, label: "Capacité" },
  items: [
    { label: "Stock bas", value: state.low, icon: "exclamationmark.triangle.fill", color: state.low ? "#FF3B30" : "green" },
    { label: "Commandes", value: state.orders, icon: "cart.fill" },
  ],
  actions: [
    { id: "in", label: "+1", icon: "plus.circle.fill", color: "green", url: "/api/stock", body: { delta: 1 } },
    { id: "out", label: "-1", icon: "minus.circle.fill", color: "red", url: "/api/stock", body: { delta: -1 } },
    { id: "order", label: "Commander", icon: "cart.badge.plus", url: "/api/order" },
  ],
});

const readBody = (req) =>
  new Promise((ok) => {
    let b = "";
    req.on("data", (c) => (b += c));
    req.on("end", () => { try { ok(b ? JSON.parse(b) : {}); } catch { ok({ text: b }); } });
  });

http.createServer(async (req, res) => {
  const send = (code, obj) => {
    res.writeHead(code, { "Content-Type": "application/json" });
    res.end(JSON.stringify(obj));
  };
  if (req.headers.authorization !== `Bearer ${TOKEN}`) return send(401, { error: "unauthorized" });

  const body = req.method === "GET" ? {} : await readBody(req);
  console.log(req.method, req.url, body);

  if (req.url === "/api/widget") return send(200, widget());
  if (req.url === "/api/stock") { state.stock += Number(body.delta ?? 0); return send(200, widget()); } // réponse = nouveau widget
  if (req.url === "/api/order") { state.orders += 1; return send(200, widget()); }
  if (req.url === "/api/scan") { state.lastScan = body.code ?? body.text ?? "?"; return send(200, widget()); } // via Raccourcis
  send(404, { error: "not found" });
}).listen(3000, () => console.log("SkullBridge demo sur http://0.0.0.0:3000/api/widget (token:", TOKEN + ")"));
