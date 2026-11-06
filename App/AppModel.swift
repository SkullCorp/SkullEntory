import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sources: [Source] = []
    @Published private(set) var cache: [UUID: CachedPayload] = [:]
    @Published private(set) var errors: [UUID: String] = [:]
    @Published private(set) var loading: Set<UUID> = []
    @Published var pendingImport: Source?
    @Published var selection: UUID?
    @Published var toast: String?

    let store = SharedStore.shared

    init() {
        reload()
    }

    func reload() {
        sources = store.loadSources()
        var c: [UUID: CachedPayload] = [:]
        for s in sources { c[s.id] = store.cached(for: s.id) }
        cache = c
    }

    // MARK: CRUD

    func upsert(_ source: Source) {
        if let i = sources.firstIndex(where: { $0.id == source.id }) {
            sources[i] = source
        } else {
            sources.append(source)
        }
        persist()
        Task { await refresh(source) }
    }

    func delete(at offsets: IndexSet) {
        for i in offsets { store.purge(sources[i].id) }
        sources.remove(atOffsets: offsets)
        persist()
    }

    func move(from: IndexSet, to: Int) {
        sources.move(fromOffsets: from, toOffset: to)
        persist()
    }

    func importSources(_ imported: [Source]) {
        for s in imported {
            if let i = sources.firstIndex(where: { $0.id == s.id }) { sources[i] = s } else { sources.append(s) }
        }
        persist()
        Task { await refreshAll() }
    }

    private func persist() {
        store.saveSources(sources)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Réseau

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for s in sources { group.addTask { await self.refresh(s) } }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refresh(_ source: Source) async {
        loading.insert(source.id)
        defer { loading.remove(source.id) }
        do {
            let payload = try await BridgeClient.shared.fetchPayload(for: source)
            store.storeCache(payload, for: source.id)
            cache[source.id] = CachedPayload(payload: payload, date: Date())
            errors[source.id] = nil
        } catch {
            errors[source.id] = error.localizedDescription
        }
    }

    func run(_ action: WidgetAction, on source: Source) async {
        let result = await ActionRunner.run(action, sourceID: source.id.uuidString)
        toast = result.success ? "✓ \(action.label)" : "✗ \(action.label) : \(result.message ?? "")"
        await refresh(source)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Liens skullbridge://

    /// - `skullbridge://open?url=https://…`           ouvre une URL (utilisé par le tap sur le widget)
    /// - `skullbridge://source?id=UUID`               affiche une web app
    /// - `skullbridge://add?name=…&url=…&token=…&kind=json|homeAssistant&header=…`
    ///                                                propose d'ajouter une web app (lien à mettre dans ta web app)
    /// - `skullbridge://refresh`                      rafraîchit tout
    func handle(url: URL) {
        guard url.scheme == "skullbridge" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }

        switch url.host {
        case "open":
            if let target = q("url").flatMap(URL.init(string:)) {
                UIApplication.shared.open(target)
            }
        case "source":
            if let id = q("id").flatMap(UUID.init(uuidString:)) { selection = id }
        case "add":
            var s = Source()
            s.name = q("name") ?? ""
            s.url = q("url") ?? ""
            s.token = q("token") ?? ""
            s.tokenHeader = q("header") ?? "Authorization"
            s.kind = q("kind").flatMap(SourceKind.init(rawValue:)) ?? .json
            s.template = q("template") ?? ""
            pendingImport = s
        case "refresh":
            Task { await refreshAll() }
        default:
            break
        }
    }
}
