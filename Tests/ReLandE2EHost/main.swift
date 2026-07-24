import Foundation
import ReLandCore
import ReLandHostCore

let port = UInt16(
    ProcessInfo.processInfo.environment["RELAND_E2E_PORT"] ?? ""
) ?? ReLandConstants.defaultPort
let key = Data((0..<32).map(UInt8.init))
let credential = try PSKCredential(
    id: "reland-e2e-device",
    key: key,
    name: "iOS Simulator"
)
let frameSource = SyntheticJPEGFrameSource(
    width: 960,
    height: 540,
    fps: 10
)
let inputSink = RecordingInputSink()
let permissionState = ProcessInfo.processInfo.environment[
    "RELAND_E2E_MISSING_PERMISSIONS"
] == "1"
    ? HostPermissionState(
        screenRecordingGranted: false,
        accessibilityGranted: false,
        sessionUnlocked: true
    )
    : .granted
private let terminalService = try makeTerminalService()
private let fileService = EchoRemoteFileService()
let server = RemoteHostServer(
    frameSource: frameSource,
    inputSink: inputSink,
    terminalService: terminalService,
    fileService: fileService,
    permissionStateProvider: {
        permissionState
    }
)

server.onStateChange = { state in
    switch state {
    case let .ready(activePort):
        print("RELAND_E2E_READY:\(activePort)")
        fflush(stdout)
    case let .failed(message):
        fputs("RELAND_E2E_FAILED:\(message)\n", stderr)
        fflush(stderr)
    case .starting, .stopped:
        break
    }
}

inputSink.onEvent = { event, summary in
    print("RELAND_E2E_INPUT:\(summary)")
    fflush(stdout)
    if case .text("__RELAND_DISCONNECT__") = event {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            server.disconnectClients()
        }
    }
}

server.start(
    configuration: RemoteHostConfiguration(
        hostID: "reland-e2e-host",
        hostName: "ReLand E2E Host",
        port: port,
        credentials: [credential]
    )
)

dispatchMain()

private func makeTerminalService() throws -> any RemoteTerminalService {
    if ProcessInfo.processInfo.environment[
        "RELAND_E2E_USE_TMUX"
    ] == "1" {
        return try TmuxTerminalService()
    }
    return EchoTerminalService()
}

private final class EchoTerminalService:
    RemoteTerminalService,
    @unchecked Sendable
{
    private static let artifactData = Data(
        "ReLand terminal artifact preview\n".utf8
    )

    private let lock = NSLock()
    private var sessions: [TerminalSessionInfo] = [
        TerminalSessionInfo(
            id: "rl-e2e",
            name: "E2E Terminal",
            windowCount: 1,
            attachedClientCount: 0,
            createdAt: Date()
        ),
    ]

    func listSessions() throws -> [TerminalSessionInfo] {
        lock.lock()
        defer { lock.unlock() }
        return sessions
    }

    func createSession(
        preferredName: String?,
        launchProfile _: TerminalLaunchProfile,
        launchArguments _: [String],
        workingDirectory _: URL?
    ) throws -> TerminalSessionInfo {
        lock.lock()
        defer { lock.unlock() }
        let number = sessions.count + 1
        let name = preferredName ?? "terminal-\(number)"
        let session = TerminalSessionInfo(
            id: "rl-e2e-\(number)",
            name: name,
            windowCount: 1,
            attachedClientCount: 0,
            createdAt: Date()
        )
        sessions.append(session)
        return session
    }

    func attach(
        attachmentID: UUID,
        sessionID: String,
        columns _: Int,
        rows _: Int,
        outputHandler: @escaping @Sendable (Data) -> Void,
        terminationHandler: @escaping @Sendable () -> Void
    ) throws -> any RemoteTerminalAttachment {
        guard sessions.contains(where: { $0.id == sessionID }) else {
            throw EchoTerminalError.missingSession
        }
        return EchoTerminalAttachment(
            attachmentID: attachmentID,
            sessionID: sessionID,
            outputHandler: outputHandler,
            terminationHandler: terminationHandler
        )
    }

    func openOnMac(sessionID: String) throws {
        guard sessions.contains(where: { $0.id == sessionID }) else {
            throw EchoTerminalError.missingSession
        }
    }

    func killSession(sessionID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeAll { $0.id == sessionID }
    }

    func listArtifacts(
        sessionID: String
    ) throws -> [TerminalArtifactInfo] {
        guard sessions.contains(where: { $0.id == sessionID }) else {
            throw EchoTerminalError.missingSession
        }
        return [
            TerminalArtifactInfo(
                id: "e2e-artifact",
                sessionID: sessionID,
                name: "e2e-artifact.txt",
                contentType: "public.plain-text",
                kind: .text,
                byteCount: Int64(Self.artifactData.count),
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
        ]
    }

    func readArtifact(
        request: TerminalArtifactReadRequest
    ) throws -> TerminalArtifactChunk {
        guard sessions.contains(where: {
            $0.id == request.sessionID
        }) else {
            throw EchoTerminalError.missingSession
        }
        guard
            request.artifactID == "e2e-artifact",
            request.offset >= 0,
            request.offset <= Int64(Self.artifactData.count),
            request.length > 0
        else {
            throw EchoTerminalError.missingArtifact
        }
        let start = Int(request.offset)
        let end = min(
            start + request.length,
            Self.artifactData.count
        )
        let data = Self.artifactData.subdata(in: start..<end)
        return TerminalArtifactChunk(
            sessionID: request.sessionID,
            artifactID: request.artifactID,
            offset: request.offset,
            totalByteCount: Int64(Self.artifactData.count),
            data: data,
            isComplete: end >= Self.artifactData.count
        )
    }
}

private final class EchoTerminalAttachment:
    RemoteTerminalAttachment,
    @unchecked Sendable
{
    let attachmentID: UUID
    let sessionID: String

    private let outputHandler: @Sendable (Data) -> Void
    private let terminationHandler: @Sendable () -> Void
    private let lock = NSLock()
    private var isClosed = false

    init(
        attachmentID: UUID,
        sessionID: String,
        outputHandler: @escaping @Sendable (Data) -> Void,
        terminationHandler: @escaping @Sendable () -> Void
    ) {
        self.attachmentID = attachmentID
        self.sessionID = sessionID
        self.outputHandler = outputHandler
        self.terminationHandler = terminationHandler
    }

    func start() {
        var lines = [
            "",
            "ReLand E2E terminal",
            "Swipe vertically for history and horizontally for wide output.",
        ]
        for index in 1...120 {
            let prefix = String(format: "%03d | ", index)
            let label = "terminal-scroll-fixture-\(index)"
            let padding = String(
                repeating: "-",
                count: max(1, 78 - prefix.count - label.count)
            )
            lines.append(prefix + label + padding + "|")
        }
        lines.append("$ ")
        outputHandler(Data(lines.joined(separator: "\r\n").utf8))
    }

    func send(_ data: Data) {
        outputHandler(data)
        if data.contains(0x0D) {
            outputHandler(Data("\r\n$ ".utf8))
        }
    }

    func resize(columns _: Int, rows _: Int) {}

    func close() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        isClosed = true
        lock.unlock()
        terminationHandler()
    }
}

private enum EchoTerminalError: LocalizedError {
    case missingSession
    case missingArtifact

    var errorDescription: String? {
        switch self {
        case .missingSession:
            "The E2E terminal session does not exist"
        case .missingArtifact:
            "The E2E terminal artifact does not exist"
        }
    }
}

private final class EchoRemoteFileService:
    RemoteFileService,
    @unchecked Sendable
{
    private let files: [String: Data] = [
        "@test/home-note.txt": Data(
            "ReLand home file preview\n".utf8
        ),
        "@test/Test Files/nested.txt": Data(
            "Nested ReLand file\n".utf8
        ),
    ]

    func list(
        request: RemoteFileListRequest
    ) throws -> RemoteFileListResponse {
        switch request.path {
        case "":
            RemoteFileListResponse(
                path: "",
                parentPath: nil,
                entries: [
                    RemoteFileEntry(
                        path: "@reland",
                        name: "ReLand Storage",
                        contentType: "public.folder",
                        kind: .directory,
                        byteCount: nil,
                        modifiedAt: .distantPast
                    ),
                    RemoteFileEntry(
                        path: "@test",
                        name: "Test Home",
                        contentType: "public.folder",
                        kind: .directory,
                        byteCount: nil,
                        modifiedAt: .distantPast
                    ),
                ]
            )
        case "@reland":
            RemoteFileListResponse(
                path: "@reland",
                parentPath: "",
                entries: []
            )
        case "@test":
            RemoteFileListResponse(
                path: "@test",
                parentPath: "",
                entries: [
                    RemoteFileEntry(
                        path: "@test/Test Files",
                        name: "Test Files",
                        contentType: "public.folder",
                        kind: .directory,
                        byteCount: nil,
                        modifiedAt: Date(
                            timeIntervalSince1970: 1_700_000_000
                        )
                    ),
                    fileEntry(path: "@test/home-note.txt"),
                ]
            )
        case "@test/Test Files":
            RemoteFileListResponse(
                path: "@test/Test Files",
                parentPath: "@test",
                entries: [
                    fileEntry(
                        path: "@test/Test Files/nested.txt"
                    ),
                ]
            )
        default:
            throw EchoRemoteFileError.missingPath
        }
    }

    func read(
        request: RemoteFileReadRequest
    ) throws -> RemoteFileChunk {
        guard
            let file = files[request.path],
            request.offset >= 0,
            request.offset <= Int64(file.count),
            request.length > 0
        else {
            throw EchoRemoteFileError.missingPath
        }
        let start = Int(request.offset)
        let end = min(start + request.length, file.count)
        return RemoteFileChunk(
            path: request.path,
            offset: request.offset,
            totalByteCount: Int64(file.count),
            data: file.subdata(in: start..<end),
            isComplete: end >= file.count
        )
    }

    func resolveDirectory(path: String) throws -> URL {
        let allowed = [
            "@reland",
            "@test",
            "@test/Test Files",
        ]
        guard allowed.contains(path) else {
            throw EchoRemoteFileError.missingPath
        }
        return FileManager.default.temporaryDirectory
    }

    private func fileEntry(path: String) -> RemoteFileEntry {
        RemoteFileEntry(
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            contentType: "public.plain-text",
            kind: .text,
            byteCount: Int64(files[path]?.count ?? 0),
            modifiedAt: Date(
                timeIntervalSince1970: 1_700_000_000
            )
        )
    }
}

private enum EchoRemoteFileError: LocalizedError {
    case missingPath

    var errorDescription: String? {
        "The E2E Mac file path does not exist"
    }
}
