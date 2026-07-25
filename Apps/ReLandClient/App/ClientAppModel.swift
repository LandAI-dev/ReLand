import CryptoKit
import Foundation
import ReLandCore
import Observation
import UIKit

@MainActor
@Observable
final class ClientAppModel {
    enum KeyboardModifier: String, CaseIterable, Identifiable {
        case command
        case option
        case control
        case shift

        var id: String { rawValue }

        var title: String {
            switch self {
            case .command:
                "Command"
            case .option:
                "Option"
            case .control:
                "Control"
            case .shift:
                "Shift"
            }
        }

        var symbol: String {
            switch self {
            case .command:
                "command"
            case .option:
                "option"
            case .control:
                "control"
            case .shift:
                "shift"
            }
        }

        var flag: UInt64 {
            switch self {
            case .command:
                0x0010_0000
            case .option:
                0x0008_0000
            case .control:
                0x0004_0000
            case .shift:
                0x0002_0000
            }
        }
    }

    enum ConnectionState: Equatable {
        case idle
        case connecting
        case authenticating
        case pairing
        case connected
        case reconnecting
        case failed(String)

        var title: String {
            switch self {
            case .idle:
                "Disconnected"
            case .connecting:
                "Connecting"
            case .authenticating:
                "Authenticating"
            case .pairing:
                "Pairing"
            case .connected:
                "Connected"
            case .reconnecting:
                "Reconnecting"
            case let .failed(message):
                message
            }
        }
    }

    var devices: [RemoteDevice] = []
    var connectionState: ConnectionState = .idle
    var remoteImage: UIImage?
    var frameCount = 0
    var lastInputAcknowledgement = "No input sent"
    var displayInformation: DisplayInformation?
    var isRemoteSessionPresented = false
    var isDirectTouchEnabled = false
    var isDragEnabled = false
    var isPairingSheetPresented = false
    var isSettingsPresented = false
    var hasCompletedOnboarding = false {
        didSet {
            settings.set(
                hasCompletedOnboarding,
                forKey: Self.onboardingCompleteKey
            )
        }
    }
    var alertMessage: String?
    var pendingPairingDescriptor: PairingDescriptor?
    var pendingTerminalExternalURL: URL?
    var terminalSecurityNotice: String?
    var isControllerTakeoverConfirmationPresented = false
    var keyboardModifiers: Set<KeyboardModifier> = []
    var editingDevice: RemoteDevice?
    var pointerSensitivity = 2.4 {
        didSet {
            settings.set(
                pointerSensitivity,
                forKey: Self.pointerSensitivityKey
            )
        }
    }
    var allowsTerminalClipboardWrites = false {
        didSet {
            settings.set(
                allowsTerminalClipboardWrites,
                forKey: Self.terminalClipboardWritesKey
            )
        }
    }
    var isThreeFingerSwitchingEnabled = true {
        didSet {
            settings.set(
                String(isThreeFingerSwitchingEnabled),
                forKey: Self.threeFingerSwitchingKey
            )
        }
    }
    var hapticsEnabled = true {
        didSet {
            settings.set(
                String(hapticsEnabled),
                forKey: Self.hapticsKey
            )
        }
    }
    var isAppSwitcherPinned = false {
        didSet {
            settings.set(
                isAppSwitcherPinned,
                forKey: Self.appSwitcherPinnedKey
            )
            if isAppSwitcherPinned {
                appSwitcherHideTask?.cancel()
                appSwitcherHideTask = nil
            }
        }
    }
    var cacheByteCount: Int64 = 0
    var savedAILaunchProfiles: [AILaunchProfile] = []
    var terminalSessions: [TerminalSessionInfo] = []
    var attachedTerminalSessionID: String?
    var isTerminalWorkspacePresented = false
    var terminalOutputPreview = ""
    var terminalArtifacts: [TerminalArtifactInfo] = []
    var isLoadingTerminalArtifacts = false
    var terminalArtifactDownloadProgress: Double?
    var terminalArtifactPreview: TerminalArtifactPreview?
    var remoteFilePath = ""
    var remoteFileParentPath: String?
    var remoteFiles: [RemoteFileEntry] = []
    var remoteFileRootNames: [String: String] = [:]
    var isLoadingRemoteFiles = false
    var remoteFileDownloadProgress: Double?
    var remoteFilePreview: RemoteFilePreview?
    var isRemoteFileBrowserPresented = false
    var captureTargets: [RemoteCaptureTargetInfo] = []
    var selectedCaptureTarget: RemoteCaptureTargetInfo?
    var hostPermissionState: HostPermissionState?
    var isCaptureTargetPickerPresented = false
    var captureTargetRevision = 0
    var isAppMode = false
    var isAppSwitcherVisible = false
    var isTerminalOnlyMode = false
    let isE2EMode: Bool

    private static let pointerSensitivityKey =
        "reland.pointer-sensitivity"
    private static let terminalClipboardWritesKey =
        "reland.terminal.clipboard-writes"
    private static let onboardingCompleteKey =
        "reland.onboarding.complete"
    private static let threeFingerSwitchingKey =
        "reland.controls.three-finger-switching"
    private static let hapticsKey = "reland.controls.haptics"
    private static let appSwitcherPinnedKey =
        "reland.controls.app-switcher-pinned"
    private static let aiLaunchProfilesKey =
        "reland.ai.launch-profiles"
    private let settings: any SettingsStoring
    private let deviceStore: DeviceStore
    private var activeDevice: RemoteDevice?
    private var activeCredential: PSKCredential?
    private var session: RemoteClientSession?
    private var reconnectTask: Task<Void, Never>?
    private var manualDisconnect = false
    private var openTerminalAfterConnect = false
    private var pendingCaptureIntent: CaptureIntent?
    private var pendingCaptureCycleDirection:
        CaptureCycleDirection?
    private var captureTargetHistory = CaptureTargetHistory()
    private var cyclingCaptureTargetID: String?
    private var appSwitcherHideTask: Task<Void, Never>?
    private var pendingTerminalCreationExistingIDs:
        Set<String>?
    @ObservationIgnored
    private var terminalOutputConsumer: ((Data) -> Void)?
    @ObservationIgnored
    private var pendingTerminalOutput = Data()
    @ObservationIgnored
    private var terminalArtifactDownload:
        TerminalArtifactDownload?
    @ObservationIgnored
    private var remoteFileDownload: RemoteFileDownload?

    init(
        settings: any SettingsStoring =
            UserDefaultsSettingsStore(),
        deviceStore: DeviceStore? = nil
    ) {
        self.settings = settings
        self.deviceStore = deviceStore
            ?? DeviceStore(settings: settings)
        devices = self.deviceStore.loadDevices()
        let savedSensitivity = settings.double(
            forKey: Self.pointerSensitivityKey
        )
        if savedSensitivity >= 1, savedSensitivity <= 4 {
            pointerSensitivity = savedSensitivity
        }
        allowsTerminalClipboardWrites = settings.bool(
            forKey: Self.terminalClipboardWritesKey
        )
        hasCompletedOnboarding = settings.bool(
            forKey: Self.onboardingCompleteKey
        )
        isThreeFingerSwitchingEnabled = Self.boolSetting(
            settings,
            key: Self.threeFingerSwitchingKey,
            defaultValue: true
        )
        hapticsEnabled = Self.boolSetting(
            settings,
            key: Self.hapticsKey,
            defaultValue: true
        )
        isAppSwitcherPinned = settings.bool(
            forKey: Self.appSwitcherPinnedKey
        )
        if
            let profileData = settings.data(
                forKey: Self.aiLaunchProfilesKey
            ),
            let profiles = try? JSONDecoder().decode(
                [AILaunchProfile].self,
                from: profileData
            )
        {
            savedAILaunchProfiles = profiles
        }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        isE2EMode = arguments.contains("--reland-e2e")
        if arguments.contains("--reland-reset-onboarding") {
            hasCompletedOnboarding = false
        } else if
            arguments.contains("--reland-skip-onboarding")
                || arguments.contains("--reland-device-list-e2e")
                || isE2EMode
        {
            hasCompletedOnboarding = true
        }
        if arguments.contains("--reland-device-list-e2e") {
            devices = [
                RemoteDevice(
                    id: "device-list-e2e",
                    hostID: "device-list-e2e-host",
                    name: "Percy's Very Long MacBook Pro Name",
                    address: "100.100.100.100",
                    port: ReLandConstants.defaultPort,
                    credentialID: "device-list-e2e"
                ),
            ]
        } else if isE2EMode {
            configureE2ESession(arguments: arguments)
        }
        #else
        isE2EMode = false
        #endif
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func restartOnboarding() {
        isSettingsPresented = false
        hasCompletedOnboarding = false
    }

    func refreshCacheUsage() {
        do {
            cacheByteCount = try Self.directoryByteCount(
                at: cacheRootURL()
            )
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func clearDownloadCache() {
        cancelTerminalArtifactDownload()
        cancelRemoteFileDownload()
        do {
            let root = cacheRootURL()
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
            terminalArtifactPreview = nil
            remoteFilePreview = nil
            cacheByteCount = 0
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func resetSavedAILaunchOptions() {
        for profile in TerminalLaunchProfile.allCases {
            let prefix =
                "reland.terminal.\(profile.rawValue)."
            settings.removeObject(forKey: prefix + "bypass")
            settings.removeObject(forKey: prefix + "arguments")
        }
        savedAILaunchProfiles = []
        settings.removeObject(
            forKey: Self.aiLaunchProfilesKey
        )
        terminalSecurityNotice =
            "Reset saved ReLand AI launch arguments."
    }

    func saveAILaunchProfile(
        name: String,
        tool: TerminalLaunchProfile,
        additionalArguments: String,
        bypassPermissions: Bool
    ) throws {
        let trimmedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedName.isEmpty, tool != .shell else {
            throw ClientModelError.invalidAILaunchProfile
        }
        savedAILaunchProfiles.removeAll {
            $0.name.localizedCaseInsensitiveCompare(
                trimmedName
            ) == .orderedSame
                && $0.tool == tool
        }
        savedAILaunchProfiles.append(
            AILaunchProfile(
                name: trimmedName,
                tool: tool,
                additionalArguments: additionalArguments,
                bypassPermissions: bypassPermissions
            )
        )
        savedAILaunchProfiles.sort {
            $0.name.localizedStandardCompare($1.name)
                == .orderedAscending
        }
        try persistAILaunchProfiles()
    }

    func deleteAILaunchProfile(_ profile: AILaunchProfile) {
        savedAILaunchProfiles.removeAll {
            $0.id == profile.id
        }
        do {
            try persistAILaunchProfiles()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func aiLaunchProfiles(
        for tool: TerminalLaunchProfile
    ) -> [AILaunchProfile] {
        savedAILaunchProfiles.filter { $0.tool == tool }
    }

    func preparePairing(payload: String) {
        let candidate = payload
            .trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            pendingPairingDescriptor = try PairingDescriptor(
                payload: candidate
            )
        } catch {
            pendingPairingDescriptor = nil
            alertMessage = error.localizedDescription
        }
    }

    func cancelPairingConfirmation() {
        pendingPairingDescriptor = nil
    }

    func confirmPairing() {
        guard let descriptor = pendingPairingDescriptor else {
            return
        }
        pendingPairingDescriptor = nil
        do {
            let newCredential = try PSKCredential.generate(
                name: UIDevice.current.name
            )
            let pairingSession = try RemoteClientSession(
                address: descriptor.address,
                port: descriptor.port,
                credential: descriptor.credential,
                mode: .pair(newDeviceCredential: newCredential)
            )
            configureCallbacks(
                for: pairingSession,
                pairingDescriptor: descriptor
            )
            session = pairingSession
            connectionState = .pairing
            pairingSession.connect()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func connect(
        to device: RemoteDevice,
        terminalOnly: Bool = false,
        appOnly: Bool = false
    ) {
        do {
            guard PrivateNetworkPolicy.allows(device.address) else {
                throw ClientModelError.untrustedNetworkAddress
            }
            guard let credential = try deviceStore.credential(for: device) else {
                throw ClientModelError.missingCredential
            }
            isTerminalOnlyMode = terminalOnly
            openTerminalAfterConnect = terminalOnly
            pendingCaptureIntent = terminalOnly
                ? nil
                : (appOnly ? .app : .screen)
            isAppMode = appOnly
            if appOnly {
                isDirectTouchEnabled = true
                isDragEnabled = false
            }
            startSession(device: device, credential: credential)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func disconnect() {
        manualDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        session?.disconnect()
        session = nil
        activeDevice = nil
        activeCredential = nil
        isRemoteSessionPresented = false
        connectionState = .idle
        remoteImage = nil
        frameCount = 0
        terminalSessions = []
        attachedTerminalSessionID = nil
        resetTerminalArtifacts()
        resetRemoteFiles()
        captureTargets = []
        selectedCaptureTarget = nil
        hostPermissionState = nil
        isCaptureTargetPickerPresented = false
        isAppMode = false
        isAppSwitcherVisible = false
        appSwitcherHideTask?.cancel()
        appSwitcherHideTask = nil
        pendingCaptureCycleDirection = nil
        cyclingCaptureTargetID = nil
        captureTargetHistory = CaptureTargetHistory()
        pendingCaptureIntent = nil
        isControllerTakeoverConfirmationPresented = false
        isTerminalWorkspacePresented = false
        pendingTerminalOutput.removeAll()
        isTerminalOnlyMode = false
        openTerminalAfterConnect = false
    }

    func remove(_ device: RemoteDevice) {
        do {
            try deviceStore.remove(device)
            devices = deviceStore.loadDevices()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func update(
        _ device: RemoteDevice,
        address: String,
        port: UInt16
    ) {
        var updated = device
        updated.address = address
        updated.port = port
        do {
            try deviceStore.update(updated)
            devices = deviceStore.loadDevices()
            editingDevice = nil
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func send(_ input: RemoteInputEvent) {
        session?.send(input: input)
    }

    func sendClick(button: MouseButton = .left, clickCount: Int = 1) {
        send(.button(button: button, isDown: true, clickCount: clickCount))
        send(.button(button: button, isDown: false, clickCount: clickCount))
    }

    func sendText(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        if keyboardModifierFlags == 0 {
            send(.text(text))
            return
        }

        let modifiers = keyboardModifierFlags
        for character in text.lowercased() {
            guard let code = Self.virtualKeyCode(for: character) else {
                continue
            }
            send(
                .key(
                    code: code,
                    isDown: true,
                    modifiers: modifiers
                )
            )
            send(
                .key(
                    code: code,
                    isDown: false,
                    modifiers: modifiers
                )
            )
        }
        keyboardModifiers.removeAll()
    }

    func toggle(_ modifier: KeyboardModifier) {
        if keyboardModifiers.contains(modifier) {
            keyboardModifiers.remove(modifier)
        } else {
            keyboardModifiers.insert(modifier)
        }
    }

    func sendKey(_ code: UInt16) {
        let modifiers = keyboardModifierFlags
        send(.key(code: code, isDown: true, modifiers: modifiers))
        send(.key(code: code, isDown: false, modifiers: modifiers))
        keyboardModifiers.removeAll()
    }

    func requestE2EDisconnect() {
        guard isE2EMode else {
            return
        }
        send(.text("__RELAND_DISCONNECT__"))
    }

    func openTerminalWorkspace() {
        isTerminalOnlyMode = false
        presentTerminalWorkspace()
    }

    private func presentTerminalWorkspace() {
        isTerminalWorkspacePresented = true
        requestTerminalSessions()
    }

    func closeTerminalWorkspace() {
        let shouldDisconnect = isTerminalOnlyMode
        detachTerminal()
        isTerminalWorkspacePresented = false
        if shouldDisconnect {
            disconnect()
        }
    }

    func requestTerminalSessions() {
        session?.requestTerminalSessions()
    }

    func createTerminalSession(
        preferredName: String? = nil,
        launchProfile: TerminalLaunchProfile = .shell,
        launchArguments: [String] = [],
        workingDirectoryPath: String? = nil
    ) {
        pendingTerminalCreationExistingIDs =
            launchProfile == .shell
            ? nil
            : Set(terminalSessions.map(\.id))
        session?.createTerminalSession(
            preferredName: preferredName,
            launchProfile: launchProfile,
            launchArguments: launchArguments,
            workingDirectoryPath: workingDirectoryPath
        )
    }

    func attachTerminal(
        _ sessionInfo: TerminalSessionInfo,
        columns: Int = 80,
        rows: Int = 24
    ) {
        pendingTerminalOutput.removeAll()
        terminalOutputPreview = ""
        resetTerminalArtifacts()
        session?.attachTerminal(
            sessionID: sessionInfo.id,
            columns: columns,
            rows: rows
        )
    }

    func detachTerminal() {
        session?.detachTerminal()
        attachedTerminalSessionID = nil
        terminalOutputConsumer = nil
        pendingTerminalOutput.removeAll()
        resetTerminalArtifacts()
    }

    func openTerminalOnMac(_ sessionInfo: TerminalSessionInfo) {
        session?.openTerminalOnMac(sessionID: sessionInfo.id)
    }

    func killTerminal(_ sessionInfo: TerminalSessionInfo) {
        session?.killTerminalSession(sessionID: sessionInfo.id)
    }

    func sendTerminalInput(_ data: Data) {
        session?.sendTerminalInput(data)
    }

    func requestOpenTerminalLink(_ value: String) {
        let policy = TerminalContentPolicy(
            allowsClipboardWrites: allowsTerminalClipboardWrites
        )
        guard let url = policy.externalURL(from: value) else {
            terminalSecurityNotice =
                "ReLand blocked a terminal link with an unsafe scheme."
            return
        }
        pendingTerminalExternalURL = url
    }

    func confirmOpenTerminalLink() {
        guard let url = pendingTerminalExternalURL else {
            return
        }
        pendingTerminalExternalURL = nil
        UIApplication.shared.open(url)
    }

    func cancelOpenTerminalLink() {
        pendingTerminalExternalURL = nil
    }

    func handleTerminalClipboardCopy(_ content: Data) {
        let policy = TerminalContentPolicy(
            allowsClipboardWrites: allowsTerminalClipboardWrites
        )
        guard let value = policy.clipboardText(from: content) else {
            terminalSecurityNotice = allowsTerminalClipboardWrites
                ? "ReLand blocked invalid or oversized terminal clipboard content."
                : "Terminal clipboard writes are disabled in ReLand Settings."
            return
        }
        UIPasteboard.general.string = value
        terminalSecurityNotice = "Copied terminal content to the clipboard."
    }

    var artifactStorageInstruction: String {
        """
        For this ReLand terminal session, whenever I ask you to create a screenshot, recording, report, log, or other file that I may want to inspect on my phone, save or publish the completed file in `$RELAND_ARTIFACTS_DIR`. If the file already exists elsewhere, run `reland-ai artifact add "<path>"`. Use a descriptive filename, confirm the published filename, and never publish credentials, pairing codes, tokens, private keys, or unrelated personal files.
        """
    }

    func sendArtifactStorageInstruction() {
        guard attachedTerminalSessionID != nil else {
            alertMessage =
                "Attach to a terminal before sending the artifact instruction."
            return
        }
        sendTerminalInput(
            Data((artifactStorageInstruction + "\r").utf8)
        )
    }

    func copyArtifactStorageInstruction() {
        UIPasteboard.general.string = artifactStorageInstruction
        terminalSecurityNotice =
            "Copied the ReLand artifact instruction."
    }

    func resizeTerminal(columns: Int, rows: Int) {
        session?.resizeTerminal(columns: columns, rows: rows)
    }

    func requestTerminalArtifacts(sessionID: String) {
        guard let session else {
            isLoadingTerminalArtifacts = false
            alertMessage =
                TerminalArtifactDownloadError.notConnected
                    .localizedDescription
            return
        }
        isLoadingTerminalArtifacts = true
        session.requestTerminalArtifacts(sessionID: sessionID)
    }

    func downloadTerminalArtifact(
        _ artifact: TerminalArtifactInfo
    ) {
        do {
            cancelTerminalArtifactDownload()
            guard
                artifact.byteCount >= 0,
                artifact.byteCount
                    <= ReLandConstants.maximumArtifactSize
            else {
                throw TerminalArtifactDownloadError.invalidMetadata
            }
            let fileURL = try artifactCacheURL(for: artifact)
            terminalArtifactDownload = TerminalArtifactDownload(
                info: artifact,
                writer: try ChunkedDownloadWriter(
                    fileURL: fileURL,
                    expectedByteCount: artifact.byteCount,
                    maximumByteCount:
                        ReLandConstants.maximumArtifactSize
                )
            )
            terminalArtifactDownloadProgress = 0
            requestNextArtifactChunk()
        } catch {
            failTerminalArtifactDownload(error)
        }
    }

    func openRemoteFileBrowser() {
        isRemoteFileBrowserPresented = true
        requestRemoteFiles(path: "")
    }

    func openCaptureTargetPicker() {
        isCaptureTargetPickerPresented = true
        requestCaptureTargets()
    }

    func requestCaptureTargets() {
        session?.requestCaptureTargets()
    }

    func requestHostStatus() {
        session?.requestHostStatus()
    }

    func openMacScreenForPermission() {
        pendingCaptureIntent = .screen
        requestCaptureTargets()
    }

    func selectCaptureTarget(
        _ target: RemoteCaptureTargetInfo
    ) {
        if target.kind == .window {
            captureTargetHistory.recordExplicitSelection(
                id: target.id
            )
            showAppSwitcher()
        }
        session?.selectCaptureTarget(id: target.id)
    }

    func cycleCaptureTarget(
        direction: CaptureCycleDirection
    ) {
        guard isAppMode else {
            return
        }
        pendingCaptureCycleDirection = direction
        showAppSwitcher()
        requestCaptureTargets()
    }

    func showAppSwitcher() {
        guard isAppMode else {
            return
        }
        isAppSwitcherVisible = true
        appSwitcherHideTask?.cancel()
        guard !isAppSwitcherPinned else {
            appSwitcherHideTask = nil
            return
        }
        appSwitcherHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else {
                return
            }
            self?.isAppSwitcherVisible = false
        }
    }

    func closeRemoteFileBrowser() {
        isRemoteFileBrowserPresented = false
        remoteFilePreview = nil
    }

    func requestRemoteFiles(path: String) {
        guard let session else {
            isLoadingRemoteFiles = false
            alertMessage =
                RemoteFileDownloadError.notConnected
                    .localizedDescription
            return
        }
        isLoadingRemoteFiles = true
        session.requestFiles(path: path)
    }

    func openRemoteFile(_ entry: RemoteFileEntry) {
        if entry.kind == .directory {
            requestRemoteFiles(path: entry.path)
        } else {
            downloadRemoteFile(entry)
        }
    }

    func navigateToParentRemoteFolder() {
        guard let remoteFileParentPath else {
            return
        }
        requestRemoteFiles(path: remoteFileParentPath)
    }

    func setTerminalOutputConsumer(
        _ consumer: ((Data) -> Void)?
    ) {
        terminalOutputConsumer = consumer
        if let consumer, !pendingTerminalOutput.isEmpty {
            consumer(pendingTerminalOutput)
            pendingTerminalOutput.removeAll()
        }
    }

    private func startSession(
        device: RemoteDevice,
        credential: PSKCredential,
        requestsControllerTakeover: Bool = false
    ) {
        reconnectTask?.cancel()
        let previousSession = session
        session = nil
        previousSession?.disconnect()
        manualDisconnect = false
        activeDevice = device
        activeCredential = credential
        isRemoteSessionPresented = true
        connectionState = .connecting
        isControllerTakeoverConfirmationPresented = false

        do {
            let newSession = try RemoteClientSession(
                address: device.address,
                port: device.port,
                credential: credential,
                requestsControllerTakeover:
                    requestsControllerTakeover
            )
            configureCallbacks(for: newSession)
            session = newSession
            newSession.connect()
        } catch {
            connectionState = .failed(error.localizedDescription)
            scheduleReconnect()
        }
    }

    private func configureCallbacks(
        for clientSession: RemoteClientSession,
        pairingDescriptor: PairingDescriptor? = nil
    ) {
        clientSession.onStateChange = {
            [weak self, weak clientSession] state in
            Task { @MainActor in
                guard
                    let self,
                    self.session === clientSession
                else {
                    return
                }
                self.handle(state)
            }
        }
        clientSession.onRemoteError = {
            [weak self, weak clientSession] error in
            Task { @MainActor in
                guard
                    let self,
                    self.session === clientSession
                else {
                    return
                }
                switch error.code {
                case .hostBusy:
                    self.reconnectTask?.cancel()
                    self.reconnectTask = nil
                    self.isControllerTakeoverConfirmationPresented =
                        true
                case .sessionTakenOver:
                    self.reconnectTask?.cancel()
                    self.reconnectTask = nil
                    self.manualDisconnect = true
                    self.alertMessage = error.message
                default:
                    self.pendingTerminalCreationExistingIDs = nil
                    self.alertMessage = error.message
                }
            }
        }
        clientSession.onDisplayInformation = { [weak self] information in
            Task { @MainActor in
                self?.displayInformation = information
            }
        }
        clientSession.onFrame = { [weak self] data in
            Task { @MainActor in
                guard let self, let image = UIImage(data: data) else {
                    return
                }
                self.remoteImage = image
                self.frameCount += 1
            }
        }
        clientSession.onInputAcknowledgement = { [weak self] acknowledgement in
            Task { @MainActor in
                self?.lastInputAcknowledgement = acknowledgement.summary
            }
        }
        clientSession.onPaired = { [weak self] accepted, credential in
            Task { @MainActor in
                guard let self, let pairingDescriptor else {
                    return
                }
                do {
                    let device = RemoteDevice(
                        hostID: accepted.hostID,
                        name: accepted.hostName,
                        address: pairingDescriptor.address,
                        port: pairingDescriptor.port,
                        credentialID: credential.id
                    )
                    try self.deviceStore.save(
                        device,
                        credential: credential
                    )
                    self.devices = self.deviceStore.loadDevices()
                    self.isPairingSheetPresented = false
                    self.startSession(
                        device: device,
                        credential: credential
                    )
                } catch {
                    self.alertMessage = error.localizedDescription
                }
            }
        }
        clientSession.onTerminalSessions = { [weak self] sessions in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.terminalSessions = sessions
                if
                    let existing =
                        self.pendingTerminalCreationExistingIDs,
                    let created = sessions.first(where: {
                        !existing.contains($0.id)
                    })
                {
                    self.pendingTerminalCreationExistingIDs = nil
                    self.attachTerminal(created)
                }
            }
        }
        clientSession.onTerminalAttached = { [weak self] attached in
            Task { @MainActor in
                self?.attachedTerminalSessionID = attached.sessionID
            }
        }
        clientSession.onTerminalOutput = { [weak self] data in
            Task { @MainActor in
                self?.receiveTerminalOutput(data)
            }
        }
        clientSession.onTerminalDetached = { [weak self] in
            Task { @MainActor in
                self?.attachedTerminalSessionID = nil
            }
        }
        clientSession.onTerminalArtifacts = { [weak self] response in
            Task { @MainActor in
                guard
                    let self,
                    response.sessionID
                        == self.attachedTerminalSessionID
                else {
                    return
                }
                self.terminalArtifacts = response.artifacts
                self.isLoadingTerminalArtifacts = false
            }
        }
        clientSession.onTerminalArtifactChunk = { [weak self] chunk in
            Task { @MainActor in
                self?.receiveTerminalArtifactChunk(chunk)
            }
        }
        clientSession.onFiles = { [weak self] response in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.remoteFilePath = response.path
                self.remoteFileParentPath = response.parentPath
                self.remoteFiles = response.entries
                if response.path.isEmpty {
                    self.remoteFileRootNames = Dictionary(
                        uniqueKeysWithValues: response.entries.map {
                            ($0.path, $0.name)
                        }
                    )
                }
                self.isLoadingRemoteFiles = false
            }
        }
        clientSession.onFileChunk = { [weak self] chunk in
            Task { @MainActor in
                self?.receiveRemoteFileChunk(chunk)
            }
        }
        clientSession.onCaptureTargets = { [weak self] response in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.captureTargets = response.targets
                self.selectedCaptureTarget =
                    response.targets.first(where: {
                        $0.id == response.selectedTargetID
                    })
                let windows = response.targets.filter {
                    $0.kind == .window
                }
                self.captureTargetHistory.prune(
                    availableIDs: windows.map(\.id)
                )
                switch self.pendingCaptureIntent {
                case .screen:
                    if
                        let display = response.targets.first(where: {
                            $0.kind == .display
                        }),
                        display.id != response.selectedTargetID
                    {
                        self.selectCaptureTarget(display)
                    }
                    self.pendingCaptureIntent = nil
                case .app:
                    self.isCaptureTargetPickerPresented = true
                    self.pendingCaptureIntent = nil
                case nil:
                    break
                }
                if
                    let direction =
                        self.pendingCaptureCycleDirection,
                    let targetID =
                        self.captureTargetHistory.targetID(
                            from: self.selectedCaptureTarget?.id,
                            direction: direction,
                            availableIDs: windows.map(\.id)
                        ),
                    targetID != self.selectedCaptureTarget?.id
                {
                    self.pendingCaptureCycleDirection = nil
                    self.cyclingCaptureTargetID = targetID
                    self.session?.selectCaptureTarget(id: targetID)
                } else {
                    self.pendingCaptureCycleDirection = nil
                }
            }
        }
        clientSession.onCaptureTargetSelected = {
            [weak self] selected in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.selectedCaptureTarget = selected.target
                self.displayInformation =
                    selected.displayInformation
                self.isAppMode = selected.target.kind == .window
                if self.isAppMode {
                    if
                        self.cyclingCaptureTargetID
                            != selected.target.id
                    {
                        self.captureTargetHistory
                            .recordExplicitSelection(
                                id: selected.target.id
                            )
                    }
                    self.cyclingCaptureTargetID = nil
                    self.showAppSwitcher()
                    self.isDirectTouchEnabled = true
                    self.isDragEnabled = false
                } else {
                    self.isAppSwitcherVisible = false
                    self.appSwitcherHideTask?.cancel()
                    self.appSwitcherHideTask = nil
                }
                self.captureTargetRevision += 1
                self.isCaptureTargetPickerPresented = false
            }
        }
        clientSession.onHostPermissionState = {
            [weak self, weak clientSession] state in
            Task { @MainActor in
                guard
                    let self,
                    self.session === clientSession
                else {
                    return
                }
                self.hostPermissionState = state
            }
        }
    }

    private func handle(_ state: RemoteClientSession.State) {
        switch state {
        case .idle:
            connectionState = .idle
        case .connecting:
            connectionState = .connecting
        case .authenticating:
            connectionState = .authenticating
        case .pairing:
            connectionState = .pairing
        case .connected:
            reconnectTask?.cancel()
            reconnectTask = nil
            isControllerTakeoverConfirmationPresented = false
            connectionState = .connected
            if openTerminalAfterConnect {
                openTerminalAfterConnect = false
                presentTerminalWorkspace()
                return
            }
            if pendingCaptureIntent != nil {
                requestCaptureTargets()
            }
            if isTerminalWorkspacePresented {
                requestTerminalSessions()
            }
        case .waiting:
            connectionState = .reconnecting
        case let .failed(message):
            connectionState = .failed(message)
            scheduleReconnect()
        case .disconnected:
            if manualDisconnect {
                connectionState = .idle
            } else if activeDevice != nil {
                connectionState = .reconnecting
                scheduleReconnect()
            }
        }
    }

    private func scheduleReconnect() {
        guard
            !manualDisconnect,
            !isControllerTakeoverConfirmationPresented,
            reconnectTask == nil,
            let activeDevice,
            let activeCredential
        else {
            return
        }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard let self else {
                    return
                }
                self.reconnectTask = nil
                self.startSession(
                    device: activeDevice,
                    credential: activeCredential
                )
            }
        }
    }

    func cancelControllerTakeover() {
        isControllerTakeoverConfirmationPresented = false
        disconnect()
    }

    func confirmControllerTakeover() {
        guard let activeDevice, let activeCredential else {
            isControllerTakeoverConfirmationPresented = false
            return
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        session?.disconnect()
        startSession(
            device: activeDevice,
            credential: activeCredential,
            requestsControllerTakeover: true
        )
    }

    #if DEBUG
    private func configureE2ESession(arguments: [String]) {
        let host = arguments.value(after: "--e2e-host") ?? "127.0.0.1"
        let port = UInt16(
            arguments.value(after: "--e2e-port") ?? ""
        ) ?? ReLandConstants.defaultPort
        let key = Data((0..<32).map(UInt8.init))
        do {
            let credential = try PSKCredential(
                id: "reland-e2e-device",
                key: key,
                name: "iOS Simulator"
            )
            let device = RemoteDevice(
                id: "reland-e2e-device",
                hostID: "reland-e2e-host",
                name: "ReLand E2E Host",
                address: host,
                port: port,
                credentialID: credential.id
            )
            pendingCaptureIntent = .screen
            isAppMode = false
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.startSession(device: device, credential: credential)
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }
    #endif

    private var keyboardModifierFlags: UInt64 {
        keyboardModifiers.reduce(0) { result, modifier in
            result | modifier.flag
        }
    }

    private static func virtualKeyCode(for character: Character) -> UInt16? {
        let mapping: [Character: UInt16] = [
            "a": 0,
            "s": 1,
            "d": 2,
            "f": 3,
            "h": 4,
            "g": 5,
            "z": 6,
            "x": 7,
            "c": 8,
            "v": 9,
            "b": 11,
            "q": 12,
            "w": 13,
            "e": 14,
            "r": 15,
            "y": 16,
            "t": 17,
            "1": 18,
            "2": 19,
            "3": 20,
            "4": 21,
            "6": 22,
            "5": 23,
            "=": 24,
            "9": 25,
            "7": 26,
            "-": 27,
            "8": 28,
            "0": 29,
            "]": 30,
            "o": 31,
            "u": 32,
            "[": 33,
            "i": 34,
            "p": 35,
            "l": 37,
            "j": 38,
            "'": 39,
            "k": 40,
            ";": 41,
            "\\": 42,
            ",": 43,
            "/": 44,
            "n": 45,
            "m": 46,
            ".": 47,
            " ": 49,
        ]
        return mapping[character]
    }

    private func receiveTerminalOutput(_ data: Data) {
        let decoded = String(decoding: data, as: UTF8.self)
        terminalOutputPreview = String(
            (terminalOutputPreview + decoded).suffix(512)
        )
        if let terminalOutputConsumer {
            terminalOutputConsumer(data)
            return
        }
        pendingTerminalOutput.append(data)
        if pendingTerminalOutput.count > 1_048_576 {
            pendingTerminalOutput.removeFirst(
                pendingTerminalOutput.count - 1_048_576
            )
        }
    }

    private func cacheRootURL() -> URL {
        FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent(
            "ReLand",
            isDirectory: true
        )
    }

    private func artifactCacheURL(
        for artifact: TerminalArtifactInfo
    ) throws -> URL {
        guard let activeDevice else {
            throw TerminalArtifactDownloadError.cacheUnavailable
        }
        let cacheRoot = cacheRootURL()
        .appendingPathComponent(
            "TerminalArtifacts",
            isDirectory: true
        )
        let safeName = URL(
            fileURLWithPath: artifact.name
        ).lastPathComponent
        guard !safeName.isEmpty else {
            throw TerminalArtifactDownloadError.invalidMetadata
        }
        return cacheRoot
            .appendingPathComponent(
                safePathComponent(activeDevice.hostID),
                isDirectory: true
            )
            .appendingPathComponent(
                safePathComponent(artifact.sessionID),
                isDirectory: true
            )
            .appendingPathComponent(
                safePathComponent(artifact.id),
                isDirectory: true
            )
            .appendingPathComponent(safeName)
    }

    private func safePathComponent(_ value: String) -> String {
        let sanitized = value.map { character -> Character in
            character.isLetter || character.isNumber
                || character == "-"
                || character == "_"
                ? character
                : "_"
        }
        return String(sanitized.prefix(128))
    }

    private func requestNextArtifactChunk() {
        guard let download = terminalArtifactDownload else {
            return
        }
        guard let session else {
            failTerminalArtifactDownload(
                TerminalArtifactDownloadError.notConnected
            )
            return
        }
        session.requestTerminalArtifactChunk(
            sessionID: download.info.sessionID,
            artifactID: download.info.id,
            offset: download.writer.nextOffset
        )
    }

    private func receiveTerminalArtifactChunk(
        _ chunk: TerminalArtifactChunk
    ) {
        do {
            guard
                let download = terminalArtifactDownload,
                chunk.sessionID == download.info.sessionID,
                chunk.artifactID == download.info.id,
                chunk.offset == download.writer.nextOffset
            else {
                throw TerminalArtifactDownloadError.invalidChunk
            }
            let progress = try download.writer.append(
                offset: chunk.offset,
                totalByteCount: chunk.totalByteCount,
                data: chunk.data,
                isComplete: chunk.isComplete
            )
            terminalArtifactDownloadProgress = progress.progress

            if progress.isComplete {
                terminalArtifactDownload = nil
                terminalArtifactDownloadProgress = nil
                terminalArtifactPreview = TerminalArtifactPreview(
                    info: download.info,
                    fileURL: download.writer.fileURL
                )
            } else {
                requestNextArtifactChunk()
            }
        } catch {
            failTerminalArtifactDownload(error)
        }
    }

    private func cancelTerminalArtifactDownload() {
        guard let download = terminalArtifactDownload else {
            return
        }
        do {
            try download.writer.cancel()
        } catch {
            if alertMessage == nil {
                alertMessage = error.localizedDescription
            }
        }
        terminalArtifactDownload = nil
        terminalArtifactDownloadProgress = nil
    }

    private func failTerminalArtifactDownload(_ error: Error) {
        cancelTerminalArtifactDownload()
        alertMessage = error.localizedDescription
    }

    private func resetTerminalArtifacts() {
        cancelTerminalArtifactDownload()
        terminalArtifacts = []
        isLoadingTerminalArtifacts = false
        terminalArtifactPreview = nil
    }

    private func downloadRemoteFile(_ entry: RemoteFileEntry) {
        do {
            cancelRemoteFileDownload()
            guard
                let byteCount = entry.byteCount,
                byteCount >= 0,
                byteCount
                    <= ReLandConstants.maximumArtifactSize
            else {
                throw RemoteFileDownloadError.invalidMetadata
            }
            let fileURL = try remoteFileCacheURL(for: entry)
            remoteFileDownload = RemoteFileDownload(
                entry: entry,
                writer: try ChunkedDownloadWriter(
                    fileURL: fileURL,
                    expectedByteCount: byteCount,
                    maximumByteCount:
                        ReLandConstants.maximumArtifactSize
                )
            )
            remoteFileDownloadProgress = 0
            requestNextRemoteFileChunk()
        } catch {
            failRemoteFileDownload(error)
        }
    }

    private func remoteFileCacheURL(
        for entry: RemoteFileEntry
    ) throws -> URL {
        guard let activeDevice else {
            throw RemoteFileDownloadError.cacheUnavailable
        }
        let cacheRoot = cacheRootURL()
        .appendingPathComponent(
            "RemoteFiles",
            isDirectory: true
        )
        let safeName = URL(
            fileURLWithPath: entry.name
        ).lastPathComponent
        guard !safeName.isEmpty else {
            throw RemoteFileDownloadError.invalidMetadata
        }
        let pathHash = SHA256.hash(
            data: Data(entry.path.utf8)
        )
        .map { String(format: "%02x", $0) }
        .joined()
        return cacheRoot
            .appendingPathComponent(
                safePathComponent(activeDevice.hostID),
                isDirectory: true
            )
            .appendingPathComponent(
                pathHash,
                isDirectory: true
            )
            .appendingPathComponent(safeName)
    }

    private func requestNextRemoteFileChunk() {
        guard let download = remoteFileDownload else {
            return
        }
        guard let session else {
            failRemoteFileDownload(
                RemoteFileDownloadError.notConnected
            )
            return
        }
        session.requestFileChunk(
            path: download.entry.path,
            offset: download.writer.nextOffset
        )
    }

    private func receiveRemoteFileChunk(_ chunk: RemoteFileChunk) {
        do {
            guard
                let download = remoteFileDownload,
                chunk.path == download.entry.path,
                chunk.offset == download.writer.nextOffset
            else {
                throw RemoteFileDownloadError.invalidChunk
            }
            let progress = try download.writer.append(
                offset: chunk.offset,
                totalByteCount: chunk.totalByteCount,
                data: chunk.data,
                isComplete: chunk.isComplete
            )
            remoteFileDownloadProgress = progress.progress
            if progress.isComplete {
                remoteFileDownload = nil
                remoteFileDownloadProgress = nil
                remoteFilePreview = RemoteFilePreview(
                    entry: download.entry,
                    fileURL: download.writer.fileURL
                )
            } else {
                requestNextRemoteFileChunk()
            }
        } catch {
            failRemoteFileDownload(error)
        }
    }

    private func cancelRemoteFileDownload() {
        guard let download = remoteFileDownload else {
            return
        }
        do {
            try download.writer.cancel()
        } catch {
            if alertMessage == nil {
                alertMessage = error.localizedDescription
            }
        }
        remoteFileDownload = nil
        remoteFileDownloadProgress = nil
    }

    private func failRemoteFileDownload(_ error: Error) {
        cancelRemoteFileDownload()
        alertMessage = error.localizedDescription
    }

    private func resetRemoteFiles() {
        cancelRemoteFileDownload()
        remoteFilePath = ""
        remoteFileParentPath = nil
        remoteFiles = []
        remoteFileRootNames = [:]
        isLoadingRemoteFiles = false
        remoteFilePreview = nil
        isRemoteFileBrowserPresented = false
    }

    private static func boolSetting(
        _ settings: any SettingsStoring,
        key: String,
        defaultValue: Bool
    ) -> Bool {
        guard let stored = settings.string(forKey: key) else {
            return defaultValue
        }
        return stored == String(true)
    }

    private func persistAILaunchProfiles() throws {
        settings.set(
            try JSONEncoder().encode(savedAILaunchProfiles),
            forKey: Self.aiLaunchProfilesKey
        )
    }

    private static func directoryByteCount(
        at root: URL
    ) throws -> Int64 {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else {
            return 0
        }
        var enumerationError: Error?
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .fileSizeKey,
                    .isRegularFileKey,
                ],
                options: [.skipsHiddenFiles],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                }
            )
        else {
            throw ClientModelError.cacheUnavailable
        }

        var result: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [
                    .fileSizeKey,
                    .isRegularFileKey,
                ]
            )
            if
                values.isRegularFile == true,
                let fileSize = values.fileSize
            {
                result += Int64(fileSize)
            }
        }
        if let enumerationError {
            throw enumerationError
        }
        return result
    }
}

private enum CaptureIntent {
    case screen
    case app
}

private enum ClientModelError: LocalizedError {
    case missingCredential
    case untrustedNetworkAddress
    case cacheUnavailable
    case invalidAILaunchProfile

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            "The saved access credential is missing. Pair this Mac again."
        case .untrustedNetworkAddress:
            "ReLand only connects to private LAN or Tailscale addresses."
        case .cacheUnavailable:
            "ReLand could not inspect its download cache."
        case .invalidAILaunchProfile:
            "Enter a name for a ReLand AI launch profile."
        }
    }
}

private final class TerminalArtifactDownload {
    let info: TerminalArtifactInfo
    let writer: ChunkedDownloadWriter

    init(
        info: TerminalArtifactInfo,
        writer: ChunkedDownloadWriter
    ) {
        self.info = info
        self.writer = writer
    }
}

private enum TerminalArtifactDownloadError: LocalizedError {
    case invalidMetadata
    case invalidChunk
    case cacheUnavailable
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidMetadata:
            "The terminal artifact metadata is invalid."
        case .invalidChunk:
            "The terminal artifact transfer was interrupted."
        case .cacheUnavailable:
            "ReLand could not create the artifact cache."
        case .notConnected:
            "The Mac is not connected."
        }
    }
}

private final class RemoteFileDownload {
    let entry: RemoteFileEntry
    let writer: ChunkedDownloadWriter

    init(
        entry: RemoteFileEntry,
        writer: ChunkedDownloadWriter
    ) {
        self.entry = entry
        self.writer = writer
    }
}

private enum RemoteFileDownloadError: LocalizedError {
    case invalidMetadata
    case invalidChunk
    case cacheUnavailable
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidMetadata:
            "The Mac file metadata is invalid."
        case .invalidChunk:
            "The Mac file transfer was interrupted."
        case .cacheUnavailable:
            "ReLand could not create the Mac file cache."
        case .notConnected:
            "The Mac is not connected."
        }
    }
}

private extension Array where Element == String {
    func value(after flag: String) -> String? {
        guard
            let index = firstIndex(of: flag),
            indices.contains(index + 1)
        else {
            return nil
        }
        return self[index + 1]
    }
}
