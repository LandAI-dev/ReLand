import SwiftUI

struct HostDashboardView: View {
    @Bindable var model: HostAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                permissionsCard
                accessCard
                fileAccessCard
                pairingCard
                terminalSessionsCard
                trustedDevicesCard
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(
            "ReLand Host",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.alertMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.alertMessage = nil
            }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            model.refreshPermissions()
            model.refreshTerminalSessions()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .frame(width: 72, height: 72)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("ReLand Host")
                    .font(.largeTitle.bold())
                Text("Securely control this Mac from your paired iPhone or iPad.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
            StatusBadge(
                title: model.hostState.title,
                isReady: model.isHostRunning
            )
        }
    }

    private var permissionsCard: some View {
        HostCard(
            title: "Permissions",
            subtitle: "Both permissions are required for full remote control."
        ) {
            PermissionRow(
                title: "Screen Recording",
                detail: "Lets ReLand stream your display.",
                isGranted: model.hasScreenRecordingPermission,
                request: {
                    model.requestScreenRecordingPermission()
                },
                openSettings: {
                    model.openScreenRecordingSettings()
                }
            )

            Divider()

            PermissionRow(
                title: "Accessibility",
                detail: "Lets your paired device control the pointer and keyboard.",
                isGranted: model.hasAccessibilityPermission,
                request: {
                    model.requestAccessibilityPermission()
                },
                openSettings: {
                    model.openAccessibilitySettings()
                }
            )
        }
    }

    private var accessCard: some View {
        HostCard(
            title: "Remote access",
            subtitle: "\(model.hostName) • \(model.address)"
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        model.connectedClientCount == 1
                            ? "1 connected device"
                            : "\(model.connectedClientCount) connected devices"
                    )
                    .font(.headline)
                    Text(
                        "Connected sessions keep this Mac awake. "
                            + "Use the same private network or a Tailscale address. "
                            + "Do not expose port \(45_454) publicly."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(model.isHostRunning ? "Stop host" : "Start host") {
                    if model.isHostRunning {
                        model.stopHost()
                    } else {
                        model.startHost()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

        }
    }

    private var fileAccessCard: some View {
        HostCard(
            title: "Approved folders",
            subtitle:
                "Approve once for file browsing and terminal working folders."
        ) {
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ReLand Storage")
                        .font(.headline)
                    Text(
                        "Always available without macOS folder prompts"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ForEach(model.sharedFolders) { folder in
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .foregroundStyle(.tint)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name)
                            .font(.headline)
                        Text(folder.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) {
                        model.removeSharedFolder(folder)
                    }
                }
            }

            Divider()
            Label(
                "Phone file browsing is read-only. Terminal and AI "
                    + "commands can modify files in their working folder.",
                systemImage: "terminal"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
            HStack {
                Label(
                    "The phone file browser hides hidden files and symlinks.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.addSharedFolder()
                } label: {
                    Label("Approve Folder", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var pairingCard: some View {
        HostCard(
            title: "Pair a device",
            subtitle: "Codes expire after 10 minutes and are removed after use."
        ) {
            if let payload = model.pairingPayload {
                HStack(alignment: .top, spacing: 22) {
                    QRCodeView(value: payload)
                        .frame(width: 180, height: 180)
                        .accessibilityLabel("ReLand pairing QR code")

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Scan this one-time code in ReLand.")
                            .font(.headline)

                        Text(
                            "Pair while you are physically at this Mac. "
                                + "The credential expires after 10 minutes, "
                                + "works once, and is never copied to the clipboard."
                        )
                        .foregroundStyle(.secondary)

                        Button("Cancel code", role: .destructive) {
                            model.cancelPairingCode()
                        }
                    }
                }
            } else {
                HStack {
                    Text("Create a one-time code to trust another device.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Create pairing code") {
                        model.createPairingCode()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var trustedDevicesCard: some View {
        HostCard(
            title: "Trusted devices",
            subtitle: "Revoking a device immediately removes its access key."
        ) {
            if model.trustedDevices.isEmpty {
                ContentUnavailableView(
                    "No trusted devices",
                    systemImage: "iphone.slash",
                    description: Text("Pair your iPhone or iPad to enable unattended access.")
                )
                .frame(maxWidth: .infinity)
            } else {
                ForEach(model.trustedDevices) { device in
                    HStack(spacing: 12) {
                        Image(systemName: "iphone")
                            .foregroundStyle(.tint)
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.headline)
                            Text(
                                "Paired \(device.pairedAt.formatted(date: .abbreviated, time: .shortened))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()
                        Button("Revoke", role: .destructive) {
                            model.remove(device)
                        }
                    }
                    if device.id != model.trustedDevices.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var terminalSessionsCard: some View {
                HostCard(
                    title: "Terminal sessions",
                    subtitle:
                        "Persistent tmux shells shared by this Mac and paired devices."
                ) {
                    HStack {
                        Label(
                            "Trusted devices can run commands as your macOS user.",
                            systemImage: "exclamationmark.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            model.refreshTerminalSessions()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        Button {
                            model.createTerminalSession()
                        } label: {
                            Label("New terminal", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if model.terminalSessions.isEmpty {
                        ContentUnavailableView(
                            "No terminal sessions",
                            systemImage: "terminal",
                            description: Text(
                                "Create one here or from ReLand on your phone."
                            )
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(model.terminalSessions) { session in
                            HStack(spacing: 12) {
                                Image(systemName: "terminal")
                                    .foregroundStyle(.tint)
                                    .frame(width: 32, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.name)
                                        .font(.headline)
                                    Text(
                                        "\(session.windowCount) windows • "
                                            + "\(session.attachedClientCount) attached"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Open") {
                                    model.openTerminalSession(session)
                                }
                                Button("Stop", role: .destructive) {
                                    model.killTerminalSession(session)
                                }
                            }
                            if session.id != model.terminalSessions.last?.id {
                                Divider()
                            }
                }
            }
        }
    }
}

private struct HostCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(20)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08))
        )
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(
                systemName: isGranted
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(isGranted ? .green : .orange)
            .font(.title2)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Text("Granted")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.semibold))
            } else {
                Button("Request", action: request)
                Button("Open Settings", action: openSettings)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StatusBadge: View {
    let title: String
    let isReady: Bool

    var body: some View {
        Label(
            title,
            systemImage: isReady
                ? "checkmark.circle.fill"
                : "exclamationmark.circle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isReady ? .green : .orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            (isReady ? Color.green : Color.orange).opacity(0.12),
            in: Capsule()
        )
    }
}
