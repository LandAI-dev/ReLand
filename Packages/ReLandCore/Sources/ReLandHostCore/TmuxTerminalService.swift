import AppKit
import Darwin
import Foundation
import ReLandCore
import SwiftTerm

public final class TmuxTerminalService:
    RemoteTerminalService,
    @unchecked Sendable
{
    private static let sessionPrefix = "rl-"
    private static let basePath =
        "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:"
        + "/usr/sbin:/sbin"
    private static let maximumSessionReservationAttempts = 1_000
    private static let commandLock = NSLock()

    private let tmuxURL: URL
    private let artifactStore: TerminalArtifactStore
    private let serverArguments: [String]
    private let commandEnvironment: [String: String]

    public convenience init() throws {
        try self.init(
            artifactRoot: nil,
            serverName: nil
        )
    }

    init(
        artifactRoot: URL?,
        serverName: String?,
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) throws {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]
        guard
            let path = candidates.first(where: {
                FileManager.default.isExecutableFile(atPath: $0)
            })
        else {
            throw TerminalServiceError.tmuxUnavailable
        }
        tmuxURL = URL(fileURLWithPath: path)
        artifactStore = TerminalArtifactStore(root: artifactRoot)
        serverArguments = serverName.map {
            ["-L", $0]
        } ?? []
        commandEnvironment = Self.processEnvironment(
            inheriting: environment
        )
    }

    public func listSessions() throws -> [TerminalSessionInfo] {
        let output: String
        do {
            output = try run([
                "list-sessions",
                "-F",
                "#{session_id}",
            ])
        } catch let error as TerminalServiceError {
            if case let .commandFailed(message) = error,
               message.localizedCaseInsensitiveContains(
                   "no server running"
               )
                || message.localizedCaseInsensitiveContains(
                    "error connecting to"
                )
                || message.localizedCaseInsensitiveContains(
                    "no sessions"
                )
            {
                return []
            }
            throw error
        }

        let sessionIDs = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter(Self.isTmuxSessionID)
        let sessions = try sessionIDs.compactMap {
            try sessionInfo(tmuxSessionID: $0)
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        for session in sessions {
            let resources = try artifactStore.prepareSession(
                sessionID: session.id
            )
            try configureEnvironment(
                sessionID: session.id,
                resources: resources
            )
        }
        return sessions
    }

    private func sessionInfo(
        tmuxSessionID: String
    ) throws -> TerminalSessionInfo? {
        let id = try formatValue(
            tmuxSessionID: tmuxSessionID,
            format: "#{session_name}"
        )
        guard Self.isManagedSessionID(id) else {
            return nil
        }
        let metadata = try formatValue(
            tmuxSessionID: tmuxSessionID,
            format:
                "#{session_windows}|#{session_attached}|"
                + "#{session_created}"
        )
        let fields = metadata.split(
            separator: "|",
            omittingEmptySubsequences: false
        )
        guard
            fields.count == 3,
            let windows = Int(fields[0]),
            let attached = Int(fields[1]),
            let created = TimeInterval(fields[2])
        else {
            return nil
        }
        let customName = Self.removingOutputTerminator(
            try run([
                "show-options",
                "-qv",
                "-t",
                tmuxSessionID,
                "@reland_name",
            ])
        )
        let windowName = try formatValue(
            tmuxSessionID: tmuxSessionID,
            format: "#{window_name}"
        )
        let fallbackName = String(
            id.dropFirst(Self.sessionPrefix.count)
        )
        return TerminalSessionInfo(
            id: id,
            name: Self.displayName(
                customName: customName,
                windowName: windowName,
                windowCount: windows,
                fallback: fallbackName
            ),
            windowCount: windows,
            attachedClientCount: attached,
            createdAt: Date(timeIntervalSince1970: created)
        )
    }

    private func formatValue(
        tmuxSessionID: String,
        format: String
    ) throws -> String {
        Self.removingOutputTerminator(
            try run([
                "display-message",
                "-p",
                "-t",
                tmuxSessionID,
                format,
            ])
        )
    }

    private static func removingOutputTerminator(
        _ output: String
    ) -> String {
        var value = output
        if value.hasSuffix("\n") {
            value.removeLast()
        }
        if value.hasSuffix("\r") {
            value.removeLast()
        }
        return value
    }

    private static func isTmuxSessionID(_ id: String) -> Bool {
        guard id.first == "$", id.count > 1 else {
            return false
        }
        return id.dropFirst().allSatisfy {
            $0.isASCII && $0.isNumber
        }
    }

    public func createSession(
        preferredName: String?,
        launchProfile: TerminalLaunchProfile = .shell,
        launchArguments: [String] = [],
        workingDirectory: URL? = nil
    ) throws -> TerminalSessionInfo {
        Self.commandLock.lock()
        defer { Self.commandLock.unlock() }

        let existing = Set(try listSessions().map(\.id))
            .union(try artifactStore.existingSessionIDs())
        let requestedName = preferredName
            ?? (launchProfile == .shell
                ? nil
                : launchProfile.rawValue)
        let baseName = Self.sanitizedName(requestedName)
        let displayName = Self.creationDisplayName(requestedName)
        var createdResources:
            TerminalArtifactStore.SessionResources?
        let candidate = try Self.reserveSessionID(
            baseName: baseName,
            existingIDs: existing
        ) { candidate in
            let resources = try artifactStore.prepareSession(
                sessionID: candidate
            )
            do {
                _ = try run([
                    "new-session",
                    "-d",
                    "-s",
                    candidate,
                    "-c",
                    workingDirectory?.path ?? resources.root.path,
                    "-e",
                    "RELAND_ARTIFACTS_DIR="
                        + resources.artifacts.path,
                    "-e",
                    "RELAND_INSTRUCTIONS_DIR="
                        + resources.instructions.path,
                    "-e",
                    "PATH=\(resources.bin.path):\(Self.basePath)",
                ])
                createdResources = resources
                return true
            } catch let error as TerminalServiceError {
                guard error.isDuplicateSession else {
                    throw error
                }
                return false
            }
        }
        guard let resources = createdResources else {
            throw TerminalServiceError.sessionCreationFailed
        }
        if let displayName {
            _ = try run([
                "set-option",
                "-t",
                candidate,
                "@reland_name",
                displayName,
            ])
        }
        _ = try? run([
            "set-window-option",
            "-t",
            candidate,
            "window-size",
            "latest",
        ])
        let helperPath = Self.shellQuoted(resources.bin.path)
        var bootstrapCommand =
            "export PATH=\(helperPath):\"$PATH\""
        if launchProfile != .shell {
            let command = (
                ["reland-ai", launchProfile.rawValue]
                    + launchArguments
            )
            .map(Self.shellQuoted)
            .joined(separator: " ")
            bootstrapCommand += "; \(command)"
        }
        _ = try run([
            "send-keys",
            "-t",
            candidate,
            bootstrapCommand,
            "Enter",
        ])
        guard
            let session = try listSessions().first(where: {
                $0.id == candidate
            })
        else {
            throw TerminalServiceError.sessionCreationFailed
        }
        return session
    }

    static func reserveSessionID(
        baseName: String,
        existingIDs: Set<String>,
        reserve: (String) throws -> Bool
    ) throws -> String {
        let normalizedBaseName = baseName.lowercased()
        var unavailableIDs = Set(
            existingIDs.map { $0.lowercased() }
        )
        for ordinal in 1...maximumSessionReservationAttempts {
            let candidate = sessionPrefix
                + normalizedBaseName
                + (ordinal == 1 ? "" : "-\(ordinal)")
            guard !unavailableIDs.contains(candidate) else {
                continue
            }
            if try reserve(candidate) {
                return candidate
            }
            unavailableIDs.insert(candidate)
        }
        throw TerminalServiceError.sessionCreationFailed
    }

    public func attach(
        attachmentID: UUID,
        sessionID: String,
        columns: Int,
        rows: Int,
        outputHandler: @escaping @Sendable (Data) -> Void,
        terminationHandler: @escaping @Sendable () -> Void
    ) throws -> any RemoteTerminalAttachment {
        let validatedID = try validate(sessionID: sessionID)
        let attachment = TmuxTerminalAttachment(
            tmuxPath: tmuxURL.path,
            serverArguments: serverArguments,
            commandEnvironment: commandEnvironment,
            attachmentID: attachmentID,
            sessionID: validatedID,
            columns: columns,
            rows: rows,
            outputHandler: outputHandler,
            terminationHandler: terminationHandler
        )
        return attachment
    }

    public func openOnMac(sessionID: String) throws {
        let validatedID = try validate(sessionID: sessionID)
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent(
            "ReLand/TerminalSessions",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let scriptURL = directory
            .appendingPathComponent(validatedID)
            .appendingPathExtension("command")
        let command = (
            [tmuxURL.path]
                + serverArguments
                + ["attach-session", "-t", validatedID]
        )
        .map(Self.shellQuoted)
        .joined(separator: " ")
        let script = """
        #!/bin/zsh
        export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        unset TMUX TMUX_PANE
        exec \(command)
        """
        try Data(script.utf8).write(
            to: scriptURL,
            options: .atomic
        )
        guard chmod(scriptURL.path, 0o700) == 0 else {
            throw TerminalServiceError.commandFilePermissionFailed
        }
        guard NSWorkspace.shared.open(scriptURL) else {
            throw TerminalServiceError.unableToOpenTerminal
        }
    }

    public func renameSession(
        sessionID: String,
        name: String
    ) throws {
        Self.commandLock.lock()
        defer { Self.commandLock.unlock() }

        let validatedID = try validate(sessionID: sessionID)
        let validatedName = try Self.validatedDisplayName(name)
        _ = try run([
            "set-option",
            "-t",
            validatedID,
            "@reland_name",
            validatedName,
        ])
    }

    public func killSession(sessionID: String) throws {
        let validatedID = try validate(sessionID: sessionID)
        _ = try run(["kill-session", "-t", validatedID])
    }

    public func listArtifacts(
        sessionID: String
    ) throws -> [TerminalArtifactInfo] {
        let validatedID = try validate(sessionID: sessionID)
        return try artifactStore.listArtifacts(
            sessionID: validatedID
        )
    }

    public func readArtifact(
        request: TerminalArtifactReadRequest
    ) throws -> TerminalArtifactChunk {
        let validatedID = try validate(
            sessionID: request.sessionID
        )
        return try artifactStore.readArtifact(
            request: TerminalArtifactReadRequest(
                sessionID: validatedID,
                artifactID: request.artifactID,
                offset: request.offset,
                length: request.length
            )
        )
    }

    private func validate(sessionID: String) throws -> String {
        guard
            Self.isManagedSessionID(sessionID),
            try listSessions().contains(where: { $0.id == sessionID })
        else {
            throw TerminalServiceError.invalidSession
        }
        return sessionID
    }

    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = tmuxURL
        process.arguments = serverArguments + arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.environment = commandEnvironment

        try process.run()
        let outputData = standardOutput.fileHandleForReading
            .readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading
            .readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: errorData.isEmpty ? outputData : errorData,
                as: UTF8.self
            )
            throw TerminalServiceError.commandFailed(message)
        }

        return String(decoding: outputData, as: UTF8.self)
    }

    private func configureEnvironment(
        sessionID: String,
        resources: TerminalArtifactStore.SessionResources
    ) throws {
        _ = try run([
            "set-environment",
            "-u",
            "-t",
            sessionID,
            "COPILOT_CUSTOM_INSTRUCTIONS_DIRS",
        ])
        for (name, value) in [
            (
                "RELAND_ARTIFACTS_DIR",
                resources.artifacts.path
            ),
            (
                "RELAND_INSTRUCTIONS_DIR",
                resources.instructions.path
            ),
            (
                "PATH",
                "\(resources.bin.path):\(Self.basePath)"
            ),
        ] {
            _ = try run([
                "set-environment",
                "-t",
                sessionID,
                name,
                value,
            ])
        }
    }

    private static func sanitizedName(_ preferredName: String?) -> String {
        let source = preferredName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = source?.isEmpty == false ? source! : "terminal"
        let sanitized = fallback.map { character -> Character in
            if character.isLetter
                || character.isNumber
                || character == "-"
                || character == "_"
            {
                return character
            }
            return "-"
        }
        let value = String(sanitized)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        let normalized = (value.isEmpty ? "terminal" : value)
            .lowercased()
        return String(normalized.prefix(24))
    }

    private static func creationDisplayName(
        _ requestedName: String?
    ) -> String? {
        guard let requestedName else {
            return nil
        }
        let sanitized = requestedName.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.newlines.contains(scalar)
                ? " "
                : String(scalar)
        }
        .joined()
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
        guard !sanitized.isEmpty else {
            return nil
        }
        return String(
            sanitized.prefix(
                ReLandConstants.maximumTerminalNameLength
            )
        )
    }

    private static func validatedDisplayName(
        _ name: String
    ) throws -> String {
        let value = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard
            !value.isEmpty,
            value.count <= ReLandConstants.maximumTerminalNameLength,
            value.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
                    && !CharacterSet.newlines.contains($0)
            })
        else {
            throw TerminalServiceError.invalidSessionName
        }
        return value
    }

    private static func shellQuoted(_ value: String) -> String {
        "'"
            + value.replacingOccurrences(
                of: "'",
                with: "'\\''"
            )
            + "'"
    }

    private static func isManagedSessionID(_ id: String) -> Bool {
        guard
            id.hasPrefix(sessionPrefix),
            id.count > sessionPrefix.count,
            id.count <= 36
        else {
            return false
        }
        return id.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
        }
    }

    private static func displayName(
        customName: String,
        windowName: String,
        windowCount: Int,
        fallback: String
    ) -> String {
        if !customName.isEmpty {
            return customName
        }
        let genericWindowNames = [
            "bash",
            "fish",
            "sh",
            "tmux",
            "zsh",
        ]
        guard
            windowCount == 1,
            !windowName.isEmpty,
            !genericWindowNames.contains(windowName.lowercased())
        else {
            return fallback
        }
        return windowName
    }

    static func processEnvironment(
        inheriting inheritedEnvironment: [String: String]
    ) -> [String: String] {
        var environment = inheritedEnvironment
        environment.removeValue(forKey: "TMUX")
        environment.removeValue(forKey: "TMUX_PANE")
        environment["PATH"] = basePath
        environment["TERM"] = "xterm-256color"
        environment["HOME"] = NSHomeDirectory()
        return environment
    }
}

private final class TmuxTerminalAttachment:
    NSObject,
    RemoteTerminalAttachment,
    LocalProcessDelegate,
    @unchecked Sendable
{
    let attachmentID: UUID
    let sessionID: String

    private let tmuxPath: String
    private let serverArguments: [String]
    private let commandEnvironment: [String: String]
    private let outputHandler: @Sendable (Data) -> Void
    private let terminationHandler: @Sendable () -> Void
    private let lock = NSLock()
    private var columns: Int
    private var rows: Int
    private var isClosed = false
    private lazy var process = LocalProcess(
        delegate: self,
        dispatchQueue: DispatchQueue(
            label: "com.landai.reland.tmux.\(sessionID)"
        )
    )

    init(
        tmuxPath: String,
        serverArguments: [String],
        commandEnvironment: [String: String],
        attachmentID: UUID,
        sessionID: String,
        columns: Int,
        rows: Int,
        outputHandler: @escaping @Sendable (Data) -> Void,
        terminationHandler: @escaping @Sendable () -> Void
    ) {
        self.tmuxPath = tmuxPath
        self.serverArguments = serverArguments
        self.commandEnvironment = commandEnvironment
        self.attachmentID = attachmentID
        self.sessionID = sessionID
        self.columns = max(20, min(columns, 400))
        self.rows = max(5, min(rows, 200))
        self.outputHandler = outputHandler
        self.terminationHandler = terminationHandler
    }

    func start() {
        process.startProcess(
            executable: tmuxPath,
            args:
                serverArguments
                + ["attach-session", "-t", sessionID],
            environment: commandEnvironment.map {
                "\($0.key)=\($0.value)"
            },
            execName: "tmux",
            currentDirectory: NSHomeDirectory()
        )
    }

    func send(_ data: Data) {
        lock.lock()
        let closed = isClosed
        lock.unlock()
        guard !closed else {
            return
        }
        let bytes = [UInt8](data)
        process.send(data: bytes[...])
    }

    func resize(columns: Int, rows: Int) {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        self.columns = max(20, min(columns, 400))
        self.rows = max(5, min(rows, 200))
        var size = winsize(
            ws_row: UInt16(self.rows),
            ws_col: UInt16(self.columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        let fileDescriptor = process.childfd
        lock.unlock()

        if fileDescriptor >= 0 {
            _ = ioctl(fileDescriptor, TIOCSWINSZ, &size)
        }
    }

    func close() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        isClosed = true
        lock.unlock()
        process.terminate()
    }

    func processTerminated(_: LocalProcess, exitCode _: Int32?) {
        terminationHandler()
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        outputHandler(Data(slice))
    }

    func getWindowSize() -> winsize {
        lock.lock()
        defer { lock.unlock() }
        return winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
    }

    deinit {
        close()
    }
}

private enum TerminalServiceError: LocalizedError {
    case tmuxUnavailable
    case commandFailed(String)
    case sessionCreationFailed
    case invalidSession
    case invalidSessionName
    case commandFilePermissionFailed
    case unableToOpenTerminal

    var errorDescription: String? {
        switch self {
        case .tmuxUnavailable:
            "tmux is not installed"
        case let .commandFailed(message):
            message.isEmpty ? "The tmux command failed" : message
        case .sessionCreationFailed:
            "The terminal session could not be created"
        case .invalidSession:
            "The terminal session is invalid or no longer exists"
        case .invalidSessionName:
            "Terminal names must be 1–\(ReLandConstants.maximumTerminalNameLength) characters and cannot contain line breaks or control characters"
        case .commandFilePermissionFailed:
            "The Terminal launcher could not be secured"
        case .unableToOpenTerminal:
            "Terminal.app could not be opened"
        }
    }

    var isDuplicateSession: Bool {
        guard case let .commandFailed(message) = self else {
            return false
        }
        return message.localizedCaseInsensitiveContains(
            "duplicate session"
        )
    }
}
