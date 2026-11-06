import AppIntents
import SwiftUI

@main
struct SkullBridgeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            SourcesView()
                .environmentObject(model)
                .onOpenURL { model.handle(url: $0) }
        }
    }
}

struct SkullBridgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendToWebAppIntent(),
            phrases: ["Envoyer à une web app avec \(.applicationName)"],
            shortTitle: "Envoyer à une web app",
            systemImageName: "paperplane.fill"
        )
        AppShortcut(
            intent: RefreshWidgetsIntent(),
            phrases: ["Rafraîchir les widgets \(.applicationName)"],
            shortTitle: "Rafraîchir les widgets",
            systemImageName: "arrow.clockwise"
        )
    }
}
