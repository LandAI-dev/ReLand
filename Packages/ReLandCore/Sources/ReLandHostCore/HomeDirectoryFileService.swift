import Foundation
import ReLandCore
import UniformTypeIdentifiers

public struct RemoteFileRoot: Sendable {
    public let id: String
    public let name: String
    public let url: URL

    public init(id: String, name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url.standardizedFileURL
    }
}

public final class ApprovedDirectoryFileService:
    RemoteFileService,
    @unchecked Sendable
{
    private static let maximumEntryCount = 1_000

    private let lock = NSLock()
    private let fileManager: FileManager
    private var rootsByID: [String: RemoteFileRoot]

    public init(
        roots: [RemoteFileRoot],
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        rootsByID = Dictionary(
            uniqueKeysWithValues: roots.map { ($0.id, $0) }
        )
    }

    public func replaceRoots(_ roots: [RemoteFileRoot]) {
        lock.lock()
        rootsByID = Dictionary(
            uniqueKeysWithValues: roots.map { ($0.id, $0) }
        )
        lock.unlock()
    }

    public func list(
        request: RemoteFileListRequest
    ) throws -> RemoteFileListResponse {
        if request.path.isEmpty {
            return rootListing()
        }
        let location = try parseVirtualPath(request.path)
        let directory = try resolve(
            root: location.root,
            relativePath: location.relativePath
        )
        let directoryValues = try directory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard
            directoryValues.isDirectory == true,
            directoryValues.isSymbolicLink != true
        else {
            throw ApprovedDirectoryFileError.notDirectory
        }

        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .contentTypeKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isHiddenKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        let entries: [RemoteFileEntry] = try urls.compactMap {
            url -> RemoteFileEntry? in
            let values = try url.resourceValues(forKeys: keys)
            guard
                values.isHidden != true,
                !url.lastPathComponent.hasPrefix("."),
                values.isSymbolicLink != true
            else {
                return nil
            }
            let childRelativePath = location.relativePath.isEmpty
                ? url.lastPathComponent
                : "\(location.relativePath)/\(url.lastPathComponent)"
            let virtualPath = Self.virtualPath(
                rootID: location.root.id,
                relativePath: childRelativePath
            )

            if values.isDirectory == true {
                return RemoteFileEntry(
                    path: virtualPath,
                    name: url.lastPathComponent,
                    contentType: UTType.folder.identifier,
                    kind: .directory,
                    byteCount: nil,
                    modifiedAt:
                        values.contentModificationDate
                        ?? .distantPast
                )
            }
            guard
                values.isRegularFile == true,
                let fileSize = values.fileSize,
                Int64(fileSize)
                    <= ReLandConstants.maximumArtifactSize
            else {
                return nil
            }
            let contentType = values.contentType
                ?? UTType(filenameExtension: url.pathExtension)
                ?? .data
            return RemoteFileEntry(
                path: virtualPath,
                name: url.lastPathComponent,
                contentType: contentType.identifier,
                kind: Self.kind(for: contentType),
                byteCount: Int64(fileSize),
                modifiedAt:
                    values.contentModificationDate ?? .distantPast
            )
        }
        .sorted {
            if $0.kind == .directory,
               $1.kind != .directory
            {
                return true
            }
            if $0.kind != .directory,
               $1.kind == .directory
            {
                return false
            }
            return $0.name.localizedStandardCompare($1.name)
                == .orderedAscending
        }
        .prefix(Self.maximumEntryCount)
        .map { $0 }

        return RemoteFileListResponse(
            path: request.path,
            parentPath: parentPath(
                rootID: location.root.id,
                relativePath: location.relativePath
            ),
            entries: entries
        )
    }

    public func read(
        request: RemoteFileReadRequest
    ) throws -> RemoteFileChunk {
        let location = try parseVirtualPath(request.path)
        guard !location.relativePath.isEmpty else {
            throw ApprovedDirectoryFileError.fileUnavailable
        }
        let fileURL = try resolve(
            root: location.root,
            relativePath: location.relativePath
        )

        let result: ChunkedFileReadResult
        do {
            result = try ChunkedFileReader.read(
                fileURL: fileURL,
                offset: request.offset,
                length: request.length,
                maximumChunkLength:
                    ReLandConstants.artifactChunkSize,
                maximumFileSize:
                    ReLandConstants.maximumArtifactSize
            )
        } catch let error as ChunkedFileReaderError {
            switch error {
            case .invalidReadRequest:
                throw ApprovedDirectoryFileError.invalidReadRequest
            case .fileUnavailable:
                throw ApprovedDirectoryFileError.fileUnavailable
            case .fileTooLarge:
                throw ApprovedDirectoryFileError.fileTooLarge
            }
        }
        return RemoteFileChunk(
            path: request.path,
            offset: request.offset,
            totalByteCount: result.totalByteCount,
            data: result.data,
            isComplete: result.isComplete
        )
    }

    public func resolveDirectory(path: String) throws -> URL {
        let location = try parseVirtualPath(path)
        let directory = try resolve(
            root: location.root,
            relativePath: location.relativePath
        )
        let values = try directory.resourceValues(
            forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ]
        )
        guard
            values.isDirectory == true,
            values.isSymbolicLink != true
        else {
            throw ApprovedDirectoryFileError.notDirectory
        }
        return directory
    }

    private func rootListing() -> RemoteFileListResponse {
        lock.lock()
        let roots = Array(rootsByID.values)
        lock.unlock()
        let entries = roots
            .sorted {
                $0.name.localizedStandardCompare($1.name)
                    == .orderedAscending
            }
            .map { root in
                RemoteFileEntry(
                    path: Self.virtualPath(
                        rootID: root.id,
                        relativePath: ""
                    ),
                    name: root.name,
                    contentType: UTType.folder.identifier,
                    kind: .directory,
                    byteCount: nil,
                    modifiedAt: .distantPast
                )
            }
        return RemoteFileListResponse(
            path: "",
            parentPath: nil,
            entries: entries
        )
    }

    private func parseVirtualPath(
        _ path: String
    ) throws -> (root: RemoteFileRoot, relativePath: String) {
        guard path.hasPrefix("@") else {
            throw ApprovedDirectoryFileError.invalidPath
        }
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard
            let first = components.first,
            first.count > 1
        else {
            throw ApprovedDirectoryFileError.invalidPath
        }
        let rootID = String(first.dropFirst())
        lock.lock()
        let root = rootsByID[rootID]
        lock.unlock()
        guard let root else {
            throw ApprovedDirectoryFileError.invalidPath
        }
        let relativePath = components.dropFirst()
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        return (root, relativePath)
    }

    private func resolve(
        root: RemoteFileRoot,
        relativePath: String
    ) throws -> URL {
        guard
            !relativePath.hasPrefix("/"),
            !relativePath.split(separator: "/").contains(".."),
            relativePath.split(separator: "/").allSatisfy({
                !$0.hasPrefix(".")
            })
        else {
            throw ApprovedDirectoryFileError.invalidPath
        }
        let candidate = relativePath.isEmpty
            ? root.url
            : root.url.appendingPathComponent(relativePath)
                .standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath()
        guard
            resolved == candidate,
            resolved == root.url
                || resolved.path.hasPrefix(root.url.path + "/")
        else {
            throw ApprovedDirectoryFileError.invalidPath
        }
        return resolved
    }

    private func parentPath(
        rootID: String,
        relativePath: String
    ) -> String {
        guard !relativePath.isEmpty else {
            return ""
        }
        let parent = URL(fileURLWithPath: relativePath)
            .deletingLastPathComponent()
            .path
        return Self.virtualPath(
            rootID: rootID,
            relativePath:
                parent == "." || parent == "/" ? "" : parent
        )
    }

    private static func virtualPath(
        rootID: String,
        relativePath: String
    ) -> String {
        relativePath.isEmpty
            ? "@\(rootID)"
            : "@\(rootID)/\(relativePath)"
    }

    private static func kind(for type: UTType) -> RemoteFileKind {
        if type.conforms(to: .image) {
            return .image
        }
        if type.conforms(to: .movie) {
            return .video
        }
        if type.conforms(to: .text)
            || type.conforms(to: .json)
        {
            return .text
        }
        return .other
    }
}

enum ApprovedDirectoryFileError: LocalizedError {
    case invalidPath
    case notDirectory
    case fileUnavailable
    case fileTooLarge
    case invalidReadRequest

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            "The requested Mac path is not allowed."
        case .notDirectory:
            "The requested Mac folder is unavailable."
        case .fileUnavailable:
            "The requested Mac file is unavailable."
        case .fileTooLarge:
            "The requested Mac file is too large to transfer."
        case .invalidReadRequest:
            "The Mac file read request is invalid."
        }
    }
}
