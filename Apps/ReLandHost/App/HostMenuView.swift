import SwiftUI

struct HostMenuView: View {
    @Bindable var model: HostAppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.hostState.title)
        Text(
            model.connectedClientCount == 1
                ? "1 connected device"
                : "\(model.connectedClientCount) connected devices"
        )
        Divider()
        Button("Open ReLand Host") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(model.isHostRunning ? "Stop Host" : "Start Host") {
            if model.isHostRunning {
                model.stopHost()
            } else {
                model.startHost()
            }
        }
        SettingsLink {
            Text("Settings…")
        }
        Divider()
        Button("Quit ReLand Host") {
            NSApp.terminate(nil)
        }
    }
}
