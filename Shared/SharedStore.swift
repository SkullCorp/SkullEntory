import Foundation

/// Résout l'identifiant de l'App Group.
///
/// AltStore / SideStore signent l'app avec ton Apple ID gratuit et renomment l'App Group
/// (ex. `group.com.skullcorp.skullwidgets.ABCDE12345`). Ils écrivent les groupes réels dans la
/// clé `ALTAppGroups` de l'Info.plist : on la lit (dans l'app ET, depuis le widget, dans l'app parente).
enum AppGroup {
    static let base = "group.com.skullcorp.skullwidgets"

    static let identifier: String = {
        var candidates: [String] = []

        func groups(_ info: [String: Any]?) -> [String] {
            (info?["ALTAppGroups"] as? [String] ?? []).filter { $0.contains("skullwidgets") }
        }

        candidates += groups(Bundle.main.infoDictionary)

        // Depuis l'extension : …/SkullWidgets.app/PlugIns/SkullWidgetsWidget.appex
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        if parent.pathExtension == "app", let app = Bundle(url: parent) {
            candidates += groups(app.infoDictionary)
        }
        candidates.append(base)

        for id in candidates where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil {
            return id
        }
        return base
    }()
}

final class SharedStore: @unchecked Sendable {
    static let shared = SharedStore()

    let root: URL
    /// Faux si l'App Group n'est pas disponible : l'app marche, mais le widget ne verra pas la config.
    let isShared: Bool

    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        let fm = FileManager.default
        if let url = fm.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) {
            root = url.appendingPathComponent("SkullWidgets", isDirectory: true)
            isShared = true
        } else {
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
            root = support.appendingPathComponent("SkullWidgets", isDirectory: true)
            isShared = false
        }
        try? fm.createDirectory(at: root.appendingPathComponent("cache", isDirectory: true),
                                withIntermediateDirectories: true)
    }

    // MARK: Fichiers

    private var sourcesURL: URL { root.appendingPathComponent("sources.json") }
    private func cacheURL(_ id: UUID) -> URL { root.appendingPathComponent("cache/\(id.uuidString).json") }
    private func actionURL(_ id: UUID) -> URL { root.appendingPathComponent("cache/\(id.uuidString).action.json") }

    private func read<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func remove(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Sources

    func loadSources() -> [Source] { read([Source].self, at: sourcesURL) ?? [] }

    func saveSources(_ sources: [Source]) { write(sources, to: sourcesURL) }

    func source(id: String) -> Source? {
        loadSources().first { $0.id.uuidString == id }
    }

    // MARK: Cache

    func cached(for id: UUID) -> CachedPayload? { read(CachedPayload.self, at: cacheURL(id)) }

    func storeCache(_ payload: WidgetPayload, for id: UUID, date: Date = Date()) {
        write(CachedPayload(payload: payload, date: date), to: cacheURL(id))
    }

    func lastAction(for id: UUID) -> ActionResult? { read(ActionResult.self, at: actionURL(id)) }

    func storeLastAction(_ result: ActionResult, for id: UUID) { write(result, to: actionURL(id)) }

    func purge(_ id: UUID) {
        remove(cacheURL(id))
        remove(actionURL(id))
    }

    // MARK: Export / import de la config (JSON lisible)

    func exportJSON() -> String {
        guard let data = try? encoder.encode(loadSources()) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    func decodeSources(from text: String) -> [Source]? {
        try? decoder.decode([Source].self, from: Data(text.utf8))
    }
}
