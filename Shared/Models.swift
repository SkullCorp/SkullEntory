import Foundation

// MARK: - Source (= une web app configurée dans l'app)

enum SourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// GET sur une URL qui renvoie directement le JSON du widget.
    case json
    /// POST {url}/api/template : Home Assistant rend un template Jinja qui produit le JSON du widget.
    case homeAssistant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .json: return "JSON (URL)"
        case .homeAssistant: return "Home Assistant (template)"
        }
    }
}

struct Source: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var kind: SourceKind
    /// URL du endpoint JSON, ou URL de base de Home Assistant (ex. http://homeassistant.local:8123).
    var url: String
    /// Jeton envoyé dans `tokenHeader` (préfixé par "Bearer " si le header est Authorization).
    var token: String
    var tokenHeader: String
    /// Template Jinja (uniquement pour `.homeAssistant`).
    var template: String

    init(id: UUID = UUID(),
         name: String = "",
         kind: SourceKind = .json,
         url: String = "",
         token: String = "",
         tokenHeader: String = "Authorization",
         template: String = "") {
        self.id = id
        self.name = name
        self.kind = kind
        self.url = url
        self.token = token
        self.tokenHeader = tokenHeader
        self.template = template
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Sans nom"
        kind = (try? c.decodeIfPresent(SourceKind.self, forKey: .kind)) ?? .json
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        tokenHeader = try c.decodeIfPresent(String.self, forKey: .tokenHeader) ?? "Authorization"
        template = try c.decodeIfPresent(String.self, forKey: .template) ?? ""
    }

    var baseURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let u = URL(string: trimmed), u.scheme != nil else { return nil }
        return u
    }

    var displayName: String { name.isEmpty ? (baseURL?.host ?? "Web app") : name }
}

// MARK: - JSON arbitraire (corps des actions)

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n):
            if n.rounded() == n, abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }
}

// MARK: - Décodage tolérant (les templates HA renvoient souvent des nombres/booléens)

enum LenientFormat {
    static func number(_ d: Double) -> String {
        if d.rounded() == d, abs(d) < 1e15 { return String(Int64(d)) }
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.locale = Locale.current
        return f.string(from: NSNumber(value: d)) ?? String(d)
    }
}

extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return LenientFormat.number(d) }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? "oui" : "non" }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

// MARK: - Payload renvoyé par une web app

struct WidgetItem: Codable, Hashable, Sendable {
    var label: String
    var value: String?
    var icon: String?
    var color: String?

    init(label: String, value: String? = nil, icon: String? = nil, color: String? = nil) {
        self.label = label; self.value = value; self.icon = icon; self.color = color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = c.lenientString(.label) ?? ""
        value = c.lenientString(.value)
        icon = c.lenientString(.icon)
        color = c.lenientString(.color)
    }
}

struct GaugeInfo: Codable, Hashable, Sendable {
    var value: Double
    var min: Double?
    var max: Double?
    var label: String?

    init(value: Double, min: Double? = nil, max: Double? = nil, label: String? = nil) {
        self.value = value; self.min = min; self.max = max; self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = c.lenientDouble(.value) ?? 0
        min = c.lenientDouble(.min)
        max = c.lenientDouble(.max)
        label = c.lenientString(.label)
    }

    var lower: Double { min ?? 0 }
    var upper: Double { Swift.max(max ?? 1, lower + .ulpOfOne) }
    var clamped: Double { Swift.min(Swift.max(value, lower), upper) }
    var fraction: Double { (clamped - lower) / (upper - lower) }
}

struct WidgetAction: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String
    var icon: String?
    var color: String?
    /// GET, POST, PUT, PATCH, DELETE (défaut : POST)
    var method: String?
    /// URL absolue, ou relative à l'URL de la source.
    var url: String
    var body: JSONValue?
    var headers: [String: String]?

    init(id: String, label: String, icon: String? = nil, color: String? = nil,
         method: String? = nil, url: String, body: JSONValue? = nil, headers: [String: String]? = nil) {
        self.id = id; self.label = label; self.icon = icon; self.color = color
        self.method = method; self.url = url; self.body = body; self.headers = headers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = c.lenientString(.label) ?? "Action"
        id = c.lenientString(.id) ?? label
        icon = c.lenientString(.icon)
        color = c.lenientString(.color)
        method = c.lenientString(.method)
        url = c.lenientString(.url) ?? ""
        body = try? c.decodeIfPresent(JSONValue.self, forKey: .body)
        headers = try? c.decodeIfPresent([String: String].self, forKey: .headers)
    }

    var httpMethod: String { (method ?? "POST").uppercased() }
}

struct WidgetPayload: Codable, Hashable, Sendable {
    var title: String?
    var subtitle: String?
    /// Nom de SF Symbol (ex. "shippingbox.fill").
    var icon: String?
    /// Couleur hex (#FF9500) ou nom (orange, red…).
    var tint: String?
    /// URL ouverte quand on touche le widget.
    var url: String?
    /// Intervalle de rafraîchissement souhaité, en secondes (min 300).
    var refresh: Int?
    /// Grosse valeur mise en avant.
    var value: String?
    var unit: String?
    var gauge: GaugeInfo?
    var items: [WidgetItem]
    var actions: [WidgetAction]

    init(title: String? = nil, subtitle: String? = nil, icon: String? = nil, tint: String? = nil,
         url: String? = nil, refresh: Int? = nil, value: String? = nil, unit: String? = nil,
         gauge: GaugeInfo? = nil, items: [WidgetItem] = [], actions: [WidgetAction] = []) {
        self.title = title; self.subtitle = subtitle; self.icon = icon; self.tint = tint
        self.url = url; self.refresh = refresh; self.value = value; self.unit = unit
        self.gauge = gauge; self.items = items; self.actions = actions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.lenientString(.title)
        subtitle = c.lenientString(.subtitle)
        icon = c.lenientString(.icon)
        tint = c.lenientString(.tint)
        url = c.lenientString(.url)
        refresh = c.lenientDouble(.refresh).map { Int($0) }
        value = c.lenientString(.value)
        unit = c.lenientString(.unit)
        gauge = try? c.decodeIfPresent(GaugeInfo.self, forKey: .gauge)
        items = (try? c.decodeIfPresent([WidgetItem].self, forKey: .items)) ?? []
        actions = ((try? c.decodeIfPresent([WidgetAction].self, forKey: .actions)) ?? []).filter { !$0.url.isEmpty }
    }

    /// Vrai si l'objet ressemble vraiment à un payload de widget (utile pour les réponses d'actions).
    var looksMeaningful: Bool { title != nil || value != nil || gauge != nil || !items.isEmpty }

    static let sample = WidgetPayload(
        title: "Inventaire",
        subtitle: "Atelier",
        icon: "shippingbox.fill",
        tint: "#FF9534",
        value: "128",
        unit: "articles",
        gauge: GaugeInfo(value: 0.72, label: "Stock"),
        items: [
            WidgetItem(label: "Stock bas", value: "3", icon: "exclamationmark.triangle.fill", color: "#FF3B30"),
            WidgetItem(label: "Commandes", value: "5", icon: "cart.fill"),
            WidgetItem(label: "Entrées du jour", value: "12", icon: "arrow.down.circle.fill", color: "green"),
        ],
        actions: [
            WidgetAction(id: "scan", label: "Scanner", icon: "barcode.viewfinder", url: "/api/scan"),
            WidgetAction(id: "sync", label: "Synchro", icon: "arrow.triangle.2.circlepath", url: "/api/sync"),
        ]
    )
}

// MARK: - Cache partagé app ↔ widget

struct CachedPayload: Codable, Hashable, Sendable {
    var payload: WidgetPayload
    var date: Date
}

struct ActionResult: Codable, Hashable, Sendable {
    var label: String
    var success: Bool
    var message: String?
    var date: Date
}
