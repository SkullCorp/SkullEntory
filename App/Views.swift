import UIKit
import SwiftUI
import WidgetKit

// MARK: - Liste des web apps

struct SourcesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: Source?
    @State private var showHelp = false
    @State private var showTransfer = false

    var body: some View {
        NavigationStack {
            List {
                if !model.store.isShared {
                    Section {
                        Label("App Group indisponible : les widgets ne verront pas ta config. Installe l'IPA via SideStore/AltStore (pas en sideload brut).",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                ForEach(model.sources) { source in
                    NavigationLink(value: source.id) {
                        SourceRow(source: source)
                    }
                }
                .onDelete(perform: model.delete)
                .onMove(perform: model.move)
            }
            .overlay {
                if model.sources.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune web app", systemImage: "app.connected.to.app.below.fill")
                    } description: {
                        Text("Ajoute une URL qui renvoie le JSON SkullWidgets, ou ton Home Assistant avec un template.")
                    } actions: {
                        Button("Ajouter une web app") { editing = Source() }
                            .buttonStyle(.borderedProminent)
                        Button("Format JSON attendu") { showHelp = true }
                    }
                }
            }
            .navigationTitle("SkullWidgets")
            .navigationDestination(for: UUID.self) { id in
                SourceDetailView(sourceID: id)
            }
            .navigationDestination(item: $model.selection) { id in
                SourceDetailView(sourceID: id)
            }
            .refreshable { await model.refreshAll() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Format JSON", systemImage: "curlybraces") { showHelp = true }
                        Button("Importer / exporter", systemImage: "square.and.arrow.up.on.square") { showTransfer = true }
                        Button("Recharger les widgets", systemImage: "arrow.clockwise") {
                            WidgetCenter.shared.reloadAllTimelines()
                            model.toast = "Widgets rechargés"
                        }
                        if !model.sources.isEmpty { EditButton() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = Source() } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { source in
                SourceEditorView(source: source, isNew: !model.sources.contains { $0.id == source.id })
            }
            .sheet(item: $model.pendingImport) { source in
                SourceEditorView(source: source, isNew: true)
            }
            .sheet(isPresented: $showHelp) { FormatHelpView() }
            .sheet(isPresented: $showTransfer) { TransferView() }
            .toast($model.toast)
            .task { await model.refreshAll() }
        }
    }
}

struct SourceRow: View {
    @EnvironmentObject private var model: AppModel
    let source: Source

    var body: some View {
        let payload = model.cache[source.id]?.payload
        HStack(spacing: 12) {
            Image(systemName: payload?.iconName ?? (source.kind == .homeAssistant ? "house.fill" : "globe"))
                .font(.title3)
                .foregroundStyle(payload?.tintColor ?? .accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName).font(.headline)
                if let error = model.errors[source.id] {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if let payload {
                    Text([payload.value.map { "\($0) \(payload.unit ?? "")" }, payload.subtitle]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(source.kind.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.loading.contains(source.id) { ProgressView() }
        }
    }
}

// MARK: - Détail d'une web app

struct SourceDetailView: View {
    @EnvironmentObject private var model: AppModel
    let sourceID: UUID
    @State private var editing: Source?
    @State private var running: String?

    private var source: Source? { model.sources.first { $0.id == sourceID } }

    var body: some View {
        if let source {
            let cached = model.cache[source.id]
            List {
                Section {
                    if let payload = cached?.payload {
                        PayloadCard(payload: payload, fallbackTitle: source.displayName)
                    } else {
                        Text("Pas encore de données").foregroundStyle(.secondary)
                    }
                    if let error = model.errors[source.id] {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Aperçu")
                } footer: {
                    if let date = cached?.date {
                        Text("Mis à jour \(date.formatted(.relative(presentation: .named)))")
                    }
                }

                if let actions = cached?.payload.actions, !actions.isEmpty {
                    Section("Actions") {
                        ForEach(actions) { action in
                            Button {
                                running = action.id
                                Task {
                                    await model.run(action, on: source)
                                    running = nil
                                }
                            } label: {
                                HStack {
                                    ActionLabel(action: action)
                                        .foregroundStyle(Color(bridge: action.color) ?? .accentColor)
                                    Spacer()
                                    if running == action.id { ProgressView() } else {
                                        Text("\(action.httpMethod) \(action.url)")
                                            .font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            .disabled(running != nil)
                        }
                    }
                }

                if let last = model.store.lastAction(for: source.id) {
                    Section("Dernière action") {
                        Label("\(last.label) – \(last.message ?? "")",
                              systemImage: last.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(last.success ? .green : .red)
                        Text(last.date.formatted(date: .abbreviated, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Connexion") {
                    LabeledContent("Type", value: source.kind.label)
                    LabeledContent("URL", value: source.url).lineLimit(1)
                    LabeledContent("Jeton", value: source.token.isEmpty ? "aucun" : "•••• \(source.token.suffix(4))")
                    if let link = cached?.payload.url.flatMap(URL.init(string:)) {
                        Link(destination: link) { Label("Ouvrir la web app", systemImage: "safari") }
                    }
                }
            }
            .navigationTitle(source.displayName)
            .refreshable { await model.refresh(source) }
            .toolbar {
                Button("Modifier") { editing = source }
            }
            .sheet(item: $editing) { SourceEditorView(source: $0, isNew: false) }
        } else {
            ContentUnavailableView("Web app supprimée", systemImage: "trash")
        }
    }
}

/// Version « grand format » du widget, dans l'app.
struct PayloadCard: View {
    let payload: WidgetPayload
    let fallbackTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PayloadHeader(payload: payload, fallbackTitle: fallbackTitle)
            HeroValue(payload: payload, large: true)
            if payload.value != nil, let gauge = payload.gauge {
                Gauge(value: gauge.clamped, in: gauge.lower...gauge.upper) {
                    if let label = gauge.label { Text(label) }
                }
                .gaugeStyle(.linearCapacity)
                .tint(payload.tintColor)
            }
            ForEach(Array(payload.items.enumerated()), id: \.offset) { _, item in
                ItemRow(item: item)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Édition

struct SourceEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State var source: Source
    let isNew: Bool

    @State private var testing = false
    @State private var testResult: Result<WidgetPayload, Error>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom", text: $source.name)
                    Picker("Type", selection: $source.kind) {
                        ForEach(SourceKind.allCases) { Text($0.label).tag($0) }
                    }
                    TextField(source.kind == .homeAssistant ? "http://homeassistant.local:8123" : "https://mon-app.fr/api/widget",
                              text: $source.url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text(source.kind == .homeAssistant
                         ? "URL de base de Home Assistant. Le template ci-dessous est rendu via /api/template."
                         : "Endpoint qui renvoie le JSON SkullWidgets (GET).")
                }

                Section {
                    SecureField(source.kind == .homeAssistant ? "Jeton longue durée" : "Jeton (optionnel)", text: $source.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Header", text: $source.tokenHeader)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Authentification")
                } footer: {
                    Text("Header « Authorization » → envoyé en « Bearer <jeton> ». Le jeton n'est jamais envoyé à un autre hôte.")
                }

                if source.kind == .homeAssistant {
                    Section {
                        TextEditor(text: $source.template)
                            .font(.caption.monospaced())
                            .frame(minHeight: 220)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Insérer un exemple") { source.template = Self.haExample }
                    } header: {
                        Text("Template Jinja")
                    } footer: {
                        Text("Le template doit produire le JSON SkullWidgets. Astuce : construis un dict et termine par « | tojson ».")
                    }
                }

                Section {
                    Button {
                        testing = true
                        Task {
                            do { testResult = .success(try await BridgeClient.shared.fetchPayload(for: source)) }
                            catch { testResult = .failure(error) }
                            testing = false
                        }
                    } label: {
                        HStack {
                            Text("Tester la connexion")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(source.baseURL == nil || testing)

                    switch testResult {
                    case .success(let payload):
                        PayloadCard(payload: payload, fallbackTitle: source.displayName)
                        if !payload.actions.isEmpty {
                            Text("\(payload.actions.count) action(s) : " + payload.actions.map(\.label).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    case .failure(let error):
                        Label(error.localizedDescription, systemImage: "xmark.octagon.fill")
                            .font(.footnote).foregroundStyle(.red)
                    case nil:
                        EmptyView()
                    }
                }
            }
            .navigationTitle(isNew ? "Nouvelle web app" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        model.upsert(source)
                        dismiss()
                    }
                    .disabled(source.baseURL == nil)
                }
            }
        }
    }

    static let haExample = """
    {% set t = states('sensor.temperature_salon') %}
    {% set lights = states.light | selectattr('state','eq','on') | list | count %}
    {{ {
      "title": "Maison",
      "icon": "house.fill",
      "tint": "#03A9F4",
      "value": t,
      "unit": "°C",
      "refresh": 600,
      "items": [
        {"label": "Lumières allumées", "value": lights, "icon": "lightbulb.fill", "color": "yellow"},
        {"label": "Alarme", "value": states('alarm_control_panel.maison'), "icon": "shield.fill"}
      ],
      "actions": [
        {"id": "salon", "label": "Salon", "icon": "lightbulb", "url": "/api/services/light/toggle",
         "body": {"entity_id": "light.salon"}},
        {"id": "nuit", "label": "Nuit", "icon": "moon.fill", "color": "indigo",
         "url": "/api/services/script/turn_on", "body": {"entity_id": "script.mode_nuit"}}
      ]
    } | tojson }}
    """
}

// MARK: - Aide format

struct FormatHelpView: View {
    @Environment(\.dismiss) private var dismiss

    static let sampleJSON = """
    {
      "title": "Inventaire",
      "subtitle": "Atelier",
      "icon": "shippingbox.fill",
      "tint": "#FF9534",
      "url": "https://mon-app.fr",
      "refresh": 900,
      "value": "128",
      "unit": "articles",
      "gauge": { "value": 72, "min": 0, "max": 100, "label": "Stock" },
      "items": [
        { "label": "Stock bas", "value": 3, "icon": "exclamationmark.triangle.fill", "color": "#FF3B30" },
        { "label": "Commandes", "value": 5, "icon": "cart.fill" }
      ],
      "actions": [
        { "id": "sync", "label": "Synchro", "icon": "arrow.triangle.2.circlepath",
          "method": "POST", "url": "/api/sync", "body": { "source": "widget" } }
      ]
    }
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ta web app expose une URL qui renvoie ce JSON (tous les champs sont optionnels). Les boutons « actions » apparaissent sur le widget et envoient la requête décrite. Si la réponse d'une action est elle-même un JSON SkullWidgets, le widget se met à jour immédiatement.")
                        .font(.callout)
                    Text(Self.sampleJSON)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    Text("Lien d'ajout rapide à mettre dans ta web app :\nskullwidgets://add?name=Inventaire&url=https://mon-app.fr/api/widget&token=XXX")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle("Format JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Copier", systemImage: "doc.on.doc") { UIPasteboard.general.string = Self.sampleJSON }
                }
            }
        }
    }
}

// MARK: - Import / export de la configuration

struct TransferView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ShareLink(item: model.store.exportJSON()) { Label("Exporter (contient les jetons !)", systemImage: "square.and.arrow.up") }
                    Button("Copier la config", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = model.store.exportJSON()
                        model.toast = "Config copiée"
                    }
                } header: { Text("Exporter") }

                Section {
                    TextEditor(text: $text)
                        .font(.caption.monospaced())
                        .frame(minHeight: 160)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Coller", systemImage: "doc.on.clipboard") { text = UIPasteboard.general.string ?? "" }
                    Button("Importer", systemImage: "square.and.arrow.down") {
                        if let sources = model.store.decodeSources(from: text) {
                            model.importSources(sources)
                            dismiss()
                        } else {
                            error = "JSON invalide (attendu : tableau de web apps)"
                        }
                    }
                    .disabled(text.isEmpty)
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                } header: { Text("Importer") } footer: {
                    Text("Utile pour garder ta config entre deux réinstallations (le sideload gratuit expire tous les 7 jours si tu oublies de rafraîchir).")
                }
            }
            .navigationTitle("Import / export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }
}

// MARK: - Petit toast

private struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { self.message = nil }
                    }
            }
        }
        .animation(.spring, value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View { modifier(ToastModifier(message: message)) }
}
