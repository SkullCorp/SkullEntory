import Foundation

enum BridgeError: LocalizedError {
    case invalidURL(String)
    case http(Int, String)
    case decoding(String)
    case unknownSource

    var errorDescription: String? {
        switch self {
        case .invalidURL(let u): return "URL invalide : \(u)"
        case .http(let code, let body): return "HTTP \(code)" + (body.isEmpty ? "" : " – \(body.prefix(140))")
        case .decoding(let msg): return "JSON illisible : \(msg)"
        case .unknownSource: return "Web app introuvable (supprimée ?)"
        }
    }
}

struct HTTPResponse: Sendable {
    var status: Int
    var data: Data
    var text: String { String(decoding: data, as: UTF8.self) }
}

/// Toute la communication réseau avec les web apps.
struct BridgeClient: Sendable {
    static let shared = BridgeClient()

    private let session: URLSession

    init(timeout: TimeInterval = 15) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout * 2
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.waitsForConnectivity = false
        cfg.httpAdditionalHeaders = ["User-Agent": "SkullWidgets/1.0 (iOS)"]
        session = URLSession(configuration: cfg)
    }

    // MARK: Lecture du payload

    func fetchPayload(for source: Source) async throws -> WidgetPayload {
        guard let base = source.baseURL else { throw BridgeError.invalidURL(source.url) }

        var request: URLRequest
        switch source.kind {
        case .json:
            request = URLRequest(url: base)
            request.httpMethod = "GET"
        case .homeAssistant:
            request = URLRequest(url: base.appendingPathComponent("api/template"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["template": source.template])
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuth(&request, source: source)

        let response = try await send(request)
        return try decodePayload(response.data)
    }

    func decodePayload(_ data: Data) throws -> WidgetPayload {
        do {
            return try JSONDecoder().decode(WidgetPayload.self, from: data)
        } catch {
            let snippet = String(decoding: data.prefix(120), as: UTF8.self)
            throw BridgeError.decoding(snippet.isEmpty ? error.localizedDescription : snippet)
        }
    }

    // MARK: Envoi (actions des widgets, raccourcis)

    func perform(_ action: WidgetAction, source: Source) async throws -> HTTPResponse {
        var body: Data?
        if let json = action.body {
            body = try JSONEncoder().encode(json)
        }
        return try await request(path: action.url, method: action.httpMethod, body: body,
                                 contentType: body == nil ? nil : "application/json",
                                 headers: action.headers ?? [:], source: source)
    }

    /// Requête libre vers une source. `path` peut être absolu, relatif à l'URL de la source, ou vide.
    func request(path: String, method: String, body: Data?, contentType: String?,
                 headers: [String: String] = [:], source: Source) async throws -> HTTPResponse {
        let url = try resolve(path, against: source)
        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        if let body {
            request.httpBody = body
            request.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
        }
        // Le jeton n'est envoyé qu'au même hôte que la source (on ne le fuit pas vers un tiers).
        if url.host == source.baseURL?.host {
            applyAuth(&request, source: source)
        }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        return try await send(request)
    }

    func resolve(_ path: String, against source: Source) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard let base = source.baseURL else { throw BridgeError.invalidURL(source.url) }
            return base
        }
        guard let url = URL(string: trimmed, relativeTo: source.baseURL)?.absoluteURL, url.scheme != nil else {
            throw BridgeError.invalidURL(trimmed)
        }
        return url
    }

    // MARK: Interne

    private func applyAuth(_ request: inout URLRequest, source: Source) {
        let token = source.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        let header = source.tokenHeader.trimmingCharacters(in: .whitespaces).isEmpty ? "Authorization" : source.tokenHeader
        let value = (header.caseInsensitiveCompare("Authorization") == .orderedSame && !token.contains(" "))
            ? "Bearer \(token)" : token
        request.setValue(value, forHTTPHeaderField: header)
    }

    private func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw BridgeError.http(status, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return HTTPResponse(status: status, data: data)
    }
}

// MARK: - Logique commune « exécuter une action » (widget, app, raccourcis)

enum ActionRunner {
    /// Exécute l'action, mémorise le résultat et, si la web app répond avec un nouveau payload,
    /// met directement le cache à jour (le widget se redessine avec le nouvel état).
    @discardableResult
    static func run(_ action: WidgetAction, sourceID: String) async -> ActionResult {
        let store = SharedStore.shared
        guard let source = store.source(id: sourceID) else {
            return ActionResult(label: action.label, success: false,
                                message: BridgeError.unknownSource.localizedDescription, date: Date())
        }
        let result: ActionResult
        do {
            let response = try await BridgeClient.shared.perform(action, source: source)
            if let payload = try? JSONDecoder().decode(WidgetPayload.self, from: response.data), payload.looksMeaningful {
                store.storeCache(payload, for: source.id)
            }
            result = ActionResult(label: action.label, success: true, message: "HTTP \(response.status)", date: Date())
        } catch {
            result = ActionResult(label: action.label, success: false, message: error.localizedDescription, date: Date())
        }
        store.storeLastAction(result, for: source.id)
        return result
    }
}
