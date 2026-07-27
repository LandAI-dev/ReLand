import AppKit
import Foundation
import ReLandCore
import ReLandHostCore
import Observation
import ServiceManagement

@MainActor
@Observable
final class HostAppModel {
    #if DEBUG
    private static let liveE2EEnvironmentKey =
        "RELAND_LIVE_E2E"
    #endif
    enum HostState: Equatable {
        case stopped
        case starting
        case ready(UInt16)
        case failed(String)

        var title: String {
            switch self {
            case .stopped:
                "Stopped"
            case .starting:
                "Starting"
            case let .ready(port):
                "Ready on port \(port)"
            case let .failed(message):
                message
            }
        }
    }

    private static var isLiveE2E: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment[
            liveE2EEnvironmentKey
        ] == "1"
        #else
        false
        #endif
    }

    private static var configuredPort: UInt16 {
        #if DEBUG
        UInt16(
            ProcessInfo.processInfo.environment[
                "RELAND_E2E_PORT"
            ] ?? ""
        ) ?? ReLandConstants.defaultPort
        #else
        ReLandConstants.defaultPort
        #endif
    }

    var hostState: HostState = .stopped
    var hasScreenRecordingPermission = false
    var hasAccessibilityPermission = false
    var pairingPayload: String?
    var trustedDevices: [HostTrustedDevice] = []
    var connectedClientCount = 0
    var launchAtLoginEnabled = false
    var terminalSessions: [TerminalSessionInfo] = []
    var terminalStorageByteCount: Int64 = 0
    var sharedFolders: [HostSharedFolder] = []
    var alertMessage: String?

    var isHostRunning: Bool {
        if case .ready = hostState {
            return true
        }
        return false
    }

    let hostName: String
    let address: String

    private let hostID: String
    private let store: HostCredentialStore
    private let server: RemoteHostServer
    private let powerManager = RemoteSessionPowerManager()
    private let fileAccessStore: HostFileAccessStore
    private let fileService: ApprovedDirectoryFileService
    private let terminalService: TmuxTerminalService?
    private let sessionStorageCleaner: SessionStorageCleaner
    private var pairingCredential: PSKCredential?
    private var pairingExpiryTask: Task<Void, Never>?

    init(
        settings: any SettingsStoring =
            UserDefaultsSettingsStore(),
        credentials: any CredentialStoring =
            KeychainSecretStore(
                service:
                    "com.landai.reland.host-device-credentials"
            ),
        sessionStorageCleaner: SessionStorageCleaner =
            SessionStorageCleaner()
    ) {
        let credentialStore = HostCredentialStore(
            settings: settings,
            credentials: credentials
        )
        store = credentialStore
        self.sessionStorageCleaner = sessionStorageCleaner
        hostID = credentialStore.loadOrCreateHostID()
        hostName = Host.current().localizedName
            ?? ProcessInfo.processInfo.hostName
        address = NetworkAddressResolver.preferredAddress()

        #if DEBUG
        let useSynthetic = ProcessInfo.processInfo.environment[
            "RELAND_SYNTHETIC"
        ] == "1"
        #else
        let useSynthetic = false
        #endif
        let screenCaptureSource = useSynthetic
            ? nil
            : ScreenCaptureJPEGFrameSource()
        let frameSource: any RemoteFrameSource =
            screenCaptureSource
            ?? SyntheticJPEGFrameSource()
        let inputSink: any RemoteInputSink = useSynthetic
            ? RecordingInputSink()
            : CGEventInputSink(
                targetBoundsProvider: {
                    screenCaptureSource?.currentInputBounds()
                },
                targetFocusHandler: {
                    screenCaptureSource?.focusSelectedTarget()
                }
            )
        let terminalService = try? TmuxTerminalService()
        self.terminalService = terminalService
        let fileAccessStore = HostFileAccessStore(
            settings: settings
        )
        self.fileAccessStore = fileAccessStore
        let fileService = ApprovedDirectoryFileService(
            roots: Self.fileRoots(from: fileAccessStore)
        )
        self.fileService = fileService
        server = RemoteHostServer(
            frameSource: frameSource,
            inputSink: inputSink,
            terminalService: terminalService,
            fileService: fileService,
            permissionStateProvider: {
                Self.currentPermissionState()
            }
        )

        trustedDevices = store.loadDevices()
        sharedFolders = fileAccessStore.folders
        refreshTerminalSessions()
        configureServerCallbacks()
        refreshPermissions()
        refreshLaunchAtLogin()
        if Self.isLiveE2E {
            startHost()
        } else if trustedDevices.isEmpty {
            createPairingCode()
        } else {
            startHost()
        }
    }

    func startHost() {
        let credentials = activeCredentials()
        if credentials.isEmpty {
            createPairingCode()
            return
        }
        server.start(
            configuration: RemoteHostConfiguration(
                hostID: hostID,
                hostName: hostName,
                port: Self.configuredPort,
                credentials: activeCredentials()
            )
        )
    }

    func stopHost() {
        server.stop()
    }

    func createPairingCode() {
        pairingExpiryTask?.cancel()
        do {
            let credential = try PSKCredential.generate(
                name: "Pairing code",
                isPairingCredential: true
            )
            guard PrivateNetworkPolicy.allows(address) else {
                throw ReLandSecurityError.untrustedNetworkAddress
            }
            let expiresAt = Date().addingTimeInterval(600)
            let descriptor = PairingDescriptor(
                hostID: hostID,
                hostName: hostName,
                address: address,
                port: ReLandConstants.defaultPort,
                credential: credential,
                expiresAt: expiresAt
            )
            let payload = try descriptor.encodedPayload()
            pairingCredential = credential
            pairingPayload = payload
            pairingExpiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    guard self?.pairingCredential?.id == credential.id else {
                        return
                    }
                    self?.cancelPairingCode()
                }
            }
            if isHostRunning {
                server.replaceCredentials(activeCredentials())
            } else {
                startHost()
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func cancelPairingCode() {
        pairingExpiryTask?.cancel()
        pairingExpiryTask = nil
        pairingCredential = nil
        pairingPayload = nil
        if trustedDevices.isEmpty {
            stopHost()
        } else {
            server.replaceCredentials(activeCredentials())
        }
    }

    func remove(_ device: HostTrustedDevice) {
        do {
            try store.remove(device)
            trustedDevices = store.loadDevices()
            server.disconnectClients()
            if trustedDevices.isEmpty && pairingCredential == nil {
                createPairingCode()
            } else {
                server.replaceCredentials(activeCredentials())
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func refreshPermissions() {
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func requestScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
        refreshPermissions()
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissions()
    }

    func openScreenRecordingSettings() {
        openPrivacySettings(anchor: "Privacy_ScreenCapture")
    }

    func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLogin()
        } catch {
            alertMessage = error.localizedDescription
            refreshLaunchAtLogin()
        }
    }

    func refreshTerminalSessions() {
        guard let terminalService else {
            terminalSessions = []
            return
        }
        do {
            terminalSessions = try terminalService.listSessions()
            terminalStorageByteCount =
                try sessionStorageCleaner.byteCount()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func clearStoppedTerminalSessionFiles() {
        do {
            let activeIDs = Set(
                try terminalService?.listSessions().map(\.id)
                    ?? []
            )
            let summary =
                try sessionStorageCleaner.removeStoppedSessions(
                    activeSessionIDs: activeIDs
                )
            refreshTerminalSessions()
            alertMessage =
                "Removed \(summary.removedSessionCount) stopped "
                + "session folder(s)."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func deleteAllTerminalSessionsAndFiles() {
        do {
            if let terminalService {
                for session in try terminalService.listSessions() {
                    try terminalService.killSession(
                        sessionID: session.id
                    )
                }
            }
            let summary =
                try sessionStorageCleaner
                    .removeAllManagedSessions()
            refreshTerminalSessions()
            alertMessage =
                "Deleted \(summary.removedSessionCount) ReLand "
                + "terminal session(s) and their files."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func revealReLandStorage() {
        do {
            try FileManager.default.createDirectory(
                at: sessionStorageCleaner.rootURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.activateFileViewerSelecting(
                [sessionStorageCleaner.rootURL]
            )
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func createTerminalSession() {
        guard let terminalService else {
            alertMessage = "tmux is not installed."
            return
        }
        do {
            let session = try terminalService.createSession(
                preferredName: nil
            )
            terminalSessions = try terminalService.listSessions()
            try terminalService.openOnMac(sessionID: session.id)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func openTerminalSession(_ session: TerminalSessionInfo) {
        do {
            try terminalService?.openOnMac(sessionID: session.id)
            refreshTerminalSessions()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func killTerminalSession(_ session: TerminalSessionInfo) {
        do {
            try terminalService?.killSession(sessionID: session.id)
            refreshTerminalSessions()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func addSharedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Approve Folder for ReLand"
        panel.message =
            "Approve a parent folder once. ReLand will reuse this "
            + "access for file browsing and terminal working folders "
            + "until you remove it."
        panel.prompt = "Approve Folder"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try fileAccessStore.addFolder(url)
            refreshSharedFolders()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func removeSharedFolder(_ folder: HostSharedFolder) {
        do {
            try fileAccessStore.removeFolder(id: folder.id)
            refreshSharedFolders()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func configureServerCallbacks() {
        let powerManager = powerManager
        server.onStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else {
                    return
                }
                switch state {
                case .stopped:
                    self.hostState = .stopped
                case .starting:
                    self.hostState = .starting
                case let .ready(port):
                    self.hostState = .ready(port)
                case let .failed(message):
                    self.hostState = .failed(message)
                }
#if DEBUG
                print("RELAND_HOST_STATE:\(self.hostState.title)")
#endif
            }
        }
        server.onClientCountChange = {
            [weak self, powerManager] count in
            let errorMessage: String?
            do {
                try powerManager.setRemoteSessionActive(
                    count > 0
                )
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.connectedClientCount = count
                if let errorMessage {
                    self.reportPowerManagementError(errorMessage)
                }
            }
        }
        server.onUserActivity = { [weak self, powerManager] in
            let errorMessage: String?
            do {
                try powerManager.noteRemoteUserActivity()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            guard let errorMessage else {
                return
            }
            Task { @MainActor in
                self?.reportPowerManagementError(errorMessage)
            }
        }
        server.onPairingAccepted = { [weak self] credential in
            Task { @MainActor in
                guard let self else {
                    return
                }
                do {
                    try self.store.save(credential)
                    self.trustedDevices = self.store.loadDevices()
                    self.pairingExpiryTask?.cancel()
                    self.pairingExpiryTask = nil
                    self.pairingCredential = nil
                    self.pairingPayload = nil
                } catch {
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    private func activeCredentials() -> [PSKCredential] {
        #if DEBUG
        if Self.isLiveE2E {
            let key = Data((0..<32).map(UInt8.init))
            if let credential = try? PSKCredential(
                id: "reland-e2e-device",
                key: key,
                name: "iOS Simulator"
            ) {
                return [credential]
            }
        }
        #endif
        var credentials = store.loadCredentials()
        if let pairingCredential {
            credentials.append(pairingCredential)
        }
        return credentials
    }

    private func reportPowerManagementError(_ message: String) {
#if DEBUG
        print("RELAND_POWER_ERROR:\(message)")
#endif
        if alertMessage == nil {
            alertMessage = message
        }
    }

    private func refreshSharedFolders() {
        sharedFolders = fileAccessStore.folders
        fileService.replaceRoots(
            Self.fileRoots(from: fileAccessStore)
        )
    }

    private static func fileRoots(
        from store: HostFileAccessStore
    ) -> [RemoteFileRoot] {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent(
            "ReLand",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: true
        )
        return [
            RemoteFileRoot(
                id: "reland",
                name: "ReLand Storage",
                url: applicationSupport
            ),
        ] + store.remoteRoots()
    }

    private func refreshLaunchAtLogin() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func openPrivacySettings(anchor: String) {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:"
                    + "com.apple.preference.security?\(anchor)"
            )
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    nonisolated private static func currentPermissionState()
        -> HostPermissionState
    {
        let session =
            CGSessionCopyCurrentDictionary()
                as? [String: Any]
        let isLocked =
            session?["CGSSessionScreenIsLocked"]
                as? Bool ?? false
        return HostPermissionState(
            screenRecordingGranted:
                CGPreflightScreenCaptureAccess(),
            accessibilityGranted: AXIsProcessTrusted(),
            sessionUnlocked: !isLocked
        )
    }
}
