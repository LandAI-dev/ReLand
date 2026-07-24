import ReLandCore
import SwiftUI

struct HostSettingsView: View {
    @Bindable var model: HostAppModel

    @State private var isClearStoppedPresented = false
    @State private var isDeleteAllPresented = false

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Launch ReLand Host at login",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { enabled in
                            model.setLaunchAtLogin(enabled)
                        }
                    )
                )
                LabeledContent(
                    "Host status",
                    value: model.hostState.title
                )
                LabeledContent(
                    "Port",
                    value: String(ReLandConstants.defaultPort)
                )
            }

            Section("Permissions") {
                permissionRow(
                    title: "Screen Recording",
                    isGranted:
                        model.hasScreenRecordingPermission,
                    openSettings: {
                        model.openScreenRecordingSettings()
                    }
                )
                permissionRow(
                    title: "Accessibility",
                    isGranted:
                        model.hasAccessibilityPermission,
                    openSettings: {
                        model.openAccessibilitySettings()
                    }
                )
            }

            Section("Sessions & Storage") {
                LabeledContent("Active sessions") {
                    Text(String(model.terminalSessions.count))
                        .monospacedDigit()
                }
                LabeledContent("Managed session files") {
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount:
                                model.terminalStorageByteCount,
                            countStyle: .file
                        )
                    )
                }
                Button("Reveal ReLand session storage") {
                    model.revealReLandStorage()
                }
                Button("Clear stopped session files") {
                    isClearStoppedPresented = true
                }
                Button(
                    "Delete all terminal sessions and files",
                    role: .destructive
                ) {
                    isDeleteAllPresented = true
                }
            }

            Section("Network") {
                Text(
                    "Connect only over a trusted LAN or private "
                        + "Tailscale network. Never expose port "
                        + "\(ReLandConstants.defaultPort) publicly."
                )
                Link(
                    "Tailscale setup",
                    destination: URL(
                        string:
                            "https://tailscale.com/docs/getting-started"
                    )!
                )
            }

            Section("Privacy & Security") {
                Text(
                    "ReLand Host has no cloud relay. Screen Recording "
                        + "and Accessibility remain controlled by macOS."
                )
                Text(
                    "Approved folders are read-only. Cleanup actions "
                        + "never delete the underlying approved folders."
                )
            }

            Section("About") {
                LabeledContent("App", value: "ReLand Host")
                LabeledContent(
                    "Protocol",
                    value: String(
                        ReLandConstants.protocolVersion
                    )
                )
                Text("Apache License 2.0")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 620)
        .task {
            model.refreshPermissions()
            model.refreshTerminalSessions()
        }
        .confirmationDialog(
            "Clear stopped session files?",
            isPresented: $isClearStoppedPresented
        ) {
            Button("Clear Stopped Files", role: .destructive) {
                model.clearStoppedTerminalSessionFiles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Active tmux sessions and their files are preserved."
            )
        }
        .confirmationDialog(
            "Delete every ReLand terminal session?",
            isPresented: $isDeleteAllPresented
        ) {
            Button("Delete All", role: .destructive) {
                model.deleteAllTerminalSessionsAndFiles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This stops managed tmux sessions and deletes their "
                    + "Artifacts, Instructions, and helper files."
            )
        }
    }

    private func permissionRow(
        title: String,
        isGranted: Bool,
        openSettings: @escaping () -> Void
    ) -> some View {
        HStack {
            Label(
                title,
                systemImage: isGranted
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(isGranted ? .green : .orange)
            Spacer()
            if !isGranted {
                Button("Open Settings", action: openSettings)
            }
        }
    }
}
