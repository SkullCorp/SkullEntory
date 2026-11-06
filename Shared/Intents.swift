import AppIntents
import Foundation
import WidgetKit

// MARK: - Entité « web app » (choix dans la config du widget et dans Raccourcis)

struct SourceEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Web app"
    static let defaultQuery = SourceQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ source: Source) {
        self.init(id: source.id.uuidString, name: source.displayName)
    }
}

struct SourceQuery: EntityQuery {
    init() {}

    func entities(for identifiers: [SourceEntity.ID]) async throws -> [SourceEntity] {
        SharedStore.shared.loadSources()
            .filter { identifiers.contains($0.id.uuidString) }
            .map(SourceEntity.init)
    }

    func suggestedEntities() async throws -> [SourceEntity] {
        SharedStore.shared.loadSources().map(SourceEntity.init)
    }

    func defaultResult() async -> SourceEntity? {
        SharedStore.shared.loadSources().first.map(SourceEntity.init)
    }
}

// MARK: - Configuration du widget

struct SelectSourceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Web app affichée"
    static let description = IntentDescription("Choisis la web app que ce widget affiche.")

    @Parameter(title: "Web app")
    var source: SourceEntity?

    init() {}

    init(source: SourceEntity?) {
        self.source = source
    }
}

// MARK: - Bouton interactif du widget → requête HTTP vers la web app

struct RunWidgetActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Action de widget SkullBridge"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "Source")
    var sourceID: String

    /// L'action complète est encodée ici : le bouton reste fonctionnel même si le cache change.
    @Parameter(title: "Action")
    var actionJSON: String

    init() {}

    init(sourceID: String, action: WidgetAction) {
        self.sourceID = sourceID
        self.actionJSON = (try? JSONEncoder().encode(action)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    func perform() async throws -> some IntentResult {
        if let action = try? JSONDecoder().decode(WidgetAction.self, from: Data(actionJSON.utf8)) {
            await ActionRunner.run(action, sourceID: sourceID)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Raccourcis : envoyer des données à une web app

enum HTTPMethodOption: String, AppEnum {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Méthode HTTP"
    static let caseDisplayRepresentations: [HTTPMethodOption: DisplayRepresentation] = [
        .get: "GET", .post: "POST", .put: "PUT", .patch: "PATCH", .delete: "DELETE",
    ]
}

struct SendToWebAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Envoyer à une web app"
    static let description = IntentDescription(
        "Envoie une requête HTTP (avec le jeton de la web app) et renvoie la réponse en texte."
    )

    @Parameter(title: "Web app")
    var source: SourceEntity

    @Parameter(title: "Chemin ou URL", description: "Relatif à l'URL de la web app (ex. /api/events) ou absolu.", default: "")
    var path: String

    @Parameter(title: "Méthode", default: .post)
    var method: HTTPMethodOption

    @Parameter(title: "Corps", description: "JSON (envoyé en application/json) ou texte brut.")
    var body: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Envoyer \(\.$body) à \(\.$source)") {
            \.$path
            \.$method
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let src = SharedStore.shared.source(id: source.id) else { throw BridgeError.unknownSource }

        var data: Data?
        var contentType: String?
        if let body, !body.isEmpty {
            data = Data(body.utf8)
            contentType = (try? JSONSerialization.jsonObject(with: data!, options: [.fragmentsAllowed])) != nil
                ? "application/json" : "text/plain; charset=utf-8"
        }
        let response = try await BridgeClient.shared.request(
            path: path, method: method.rawValue, body: data, contentType: contentType, source: src
        )
        if let payload = try? JSONDecoder().decode(WidgetPayload.self, from: response.data), payload.looksMeaningful {
            SharedStore.shared.storeCache(payload, for: src.id)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(value: response.text)
    }
}

struct RefreshWidgetsIntent: AppIntent {
    static let title: LocalizedStringResource = "Rafraîchir les widgets SkullBridge"
    static let description = IntentDescription("Force le rechargement de tous les widgets SkullBridge.")
    static let openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
