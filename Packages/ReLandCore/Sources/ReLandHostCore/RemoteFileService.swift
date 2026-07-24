import Foundation
import ReLandCore

public protocol RemoteFileService: Sendable {
    func list(
        request: RemoteFileListRequest
    ) throws -> RemoteFileListResponse
    func read(
        request: RemoteFileReadRequest
    ) throws -> RemoteFileChunk
    func resolveDirectory(path: String) throws -> URL
}
