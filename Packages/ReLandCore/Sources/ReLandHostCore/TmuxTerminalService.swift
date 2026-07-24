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

    private let tmuxURL: URL
    private let artifactStore = TerminalArtifactStore()
    private let commandLock = NSLock()

    public init() throws {
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
    }

    public func listSessions() throws -> [TerminalSessionInfo] {
        let output: String
        do {
            output = try run([
                "list-sessions",
                "-F",
                "#{session_name}\t#{session_windows}\t"
                    + "#{session_attached}\t#{session_created}\t"
                    + "#{window_name}",
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

        let sessions: [TerminalSessionInfo] = output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let fields = line.split(
                    separator: "\t",
                    omittingEmptySubsequences: false
                )
                guard
                    fields.count == 5,
                    let windows = Int(fields[1]),
                    let attached = Int(fields[2]),
                    let created = TimeInterval(fields[3])
                else {
                    return nil
                }
                let id = String(fields[0])
                guard Self.isManagedSessionID(id) else {
                    return nil
                }
                let fallbackName = String(
                    id.dropFirst(Self.sessionPrefix.count)
                )
                return TerminalSessionInfo(
                    id: id,
                    name: Self.displayName(
                        windowName: String(fields[4]),
                        windowCount: windows,
                        fallback: fallbackName
                    ),
                    windowCount: windows,
                    attachedClientCount: attached,
                    createdAt: Date(timeIntervalSince1970: created)
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

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

    public func createSession(
        preferredName: String?,
        launchProfile: TerminalLaunchProfile = .shell,
        launchArguments: [String] = [],
        workingDirectory: URL? = nil
    ) throws -> TerminalSessionInfo {
        commandLock.lock()
        defer { commandLock.unlock() }

        let existing = Set(try listSessions().map(\.id))
        let requestedName = preferredName
            ?? (launchProfile == .shell
                ? nil
                : launchProfile.rawValue)
        let baseName = Self.sanitizedName(requestedName)
        var candidate = Self.sessionPrefix + baseName
        var suffix = 2
        while existing.contains(candidate) {
            candidate = Self.sessionPrefix + baseName + "-\(suffix)"
            suffix += 1
        }

        let resources = try artifactStore.prepareSession(
            sessionID: candidate
        )
        _ = try run([
            "new-session",
            "-d",
            "-s",
            candidate,
            "-c",
            workingDirectory?.path ?? resources.root.path,
            "-e",
            "RELAND_ARTIFACTS_DIR=\(resources.artifacts.path)",
            "-e",
            "RELAND_INSTRUCTIONS_DIR="
                + resources.instructions.path,
            "-e",
            "PATH=\(resources.bin.path):\(Self.basePath)",
        ])
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
        let script = """
        #!/bin/zsh
        export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        exec "\(tmuxURL.path)" attach-session -t "\(validatedID)"
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
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.environment = Self.processEnvironment()

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
        return String((value.isEmpty ? "terminal" : value).prefix(24))
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
        windowName: String,
        windowCount: Int,
        fallback: String
    ) -> String {
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

    private static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
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
        attachmentID: UUID,
        sessionID: String,
        columns: Int,
        rows: Int,
        outputHandler: @escaping @Sendable (Data) -> Void,
        terminationHandler: @escaping @Sendable () -> Void
    ) {
        self.tmuxPath = tmuxPath
        self.attachmentID = attachmentID
        self.sessionID = sessionID
        self.columns = max(20, min(columns, 400))
        self.rows = max(5, min(rows, 200))
        self.outputHandler = outputHandler
        self.terminationHandler = terminationHandler
    }

    func start() {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] =
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:"
            + "/usr/sbin:/sbin"
        environment["TERM"] = "xterm-256color"
        environment["HOME"] = NSHomeDirectory()
        process.startProcess(
            executable: tmuxPath,
            args: ["attach-session", "-t", sessionID],
            environment: environment.map { "\($0.key)=\($0.value)" },
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
        case .commandFilePermissionFailed:
            "The Terminal launcher could not be secured"
        case .unableToOpenTerminal:
            "Terminal.app could not be opened"
        }
    }
}
