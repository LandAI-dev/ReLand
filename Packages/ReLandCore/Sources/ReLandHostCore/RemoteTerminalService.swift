import Foundation
import ReLandCore

public protocol RemoteTerminalAttachment: AnyObject, Sendable {
    var attachmentID: UUID { get }
    var sessionID: String { get }

    func start()
    func send(_ data: Data)
    func resize(columns: Int, rows: Int)
    func close()
}

public protocol RemoteTerminalService: Sendable {
    func listSessions() throws -> [TerminalSessionInfo]
    func createSession(
        preferredName: String?,
        launchProfile: TerminalLaunchProfile,
        launchArguments: [String],
        workingDirectory: URL?
    ) throws -> TerminalSessionInfo
    func attach(
        attachmentID: UUID,
        sessionID: String,
        columns: Int,
        rows: Int,
        outputHandler: @escaping @Sendable (Data) -> Void,
        terminationHandler: @escaping @Sendable () -> Void
    ) throws -> any RemoteTerminalAttachment
    func openOnMac(sessionID: String) throws
    func renameSession(sessionID: String, name: String) throws
    func killSession(sessionID: String) throws
    func listArtifacts(
        sessionID: String
    ) throws -> [TerminalArtifactInfo]
    func readArtifact(
        request: TerminalArtifactReadRequest
    ) throws -> TerminalArtifactChunk
}
