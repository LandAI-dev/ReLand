import SwiftUI

@main
struct ReLandHostApp: App {
    @State private var model = HostAppModel()

    var body: some Scene {
        Window("ReLand Host", id: "main") {
            HostDashboardView(model: model)
                .frame(minWidth: 720, minHeight: 600)
                .tint(.accentColor)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra(
            "ReLand",
            systemImage: model.isHostRunning
                ? "display.and.arrow.down"
                : "display.trianglebadge.exclamationmark"
        ) {
            HostMenuView(model: model)
        }

        Settings {
            HostSettingsView(model: model)
        }
    }
}
