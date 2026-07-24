import Foundation

public struct ChunkedDownloadProgress: Equatable, Sendable {
    public let progress: Double
    public let isComplete: Bool
}

public enum ChunkedDownloadWriterError:
    Error,
    Equatable,
    LocalizedError
{
    case invalidMetadata
    case invalidChunk
    case cacheUnavailable
    case closed

    public var errorDescription: String? {
        switch self {
        case .invalidMetadata:
            "The download metadata is invalid."
        case .invalidChunk:
            "The received download chunk is invalid."
        case .cacheUnavailable:
            "ReLand could not prepare its download cache."
        case .closed:
            "The download is already closed."
        }
    }
}

public final class ChunkedDownloadWriter {
    public let fileURL: URL
    public let expectedByteCount: Int64
    public private(set) var nextOffset: Int64 = 0

    private var handle: FileHandle?

    public init(
        fileURL: URL,
        expectedByteCount: Int64,
        maximumByteCount: Int64
    ) throws {
        guard
            expectedByteCount >= 0,
            expectedByteCount <= maximumByteCount
        else {
            throw ChunkedDownloadWriterError.invalidMetadata
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            guard fileManager.createFile(
                atPath: fileURL.path,
                contents: nil
            ) else {
                throw ChunkedDownloadWriterError.cacheUnavailable
            }
            handle = try FileHandle(forWritingTo: fileURL)
        } catch let error as ChunkedDownloadWriterError {
            throw error
        } catch {
            throw ChunkedDownloadWriterError.cacheUnavailable
        }

        self.fileURL = fileURL
        self.expectedByteCount = expectedByteCount
    }

    public func append(
        offset: Int64,
        totalByteCount: Int64,
        data: Data,
        isComplete: Bool
    ) throws -> ChunkedDownloadProgress {
        guard let handle else {
            throw ChunkedDownloadWriterError.closed
        }
        guard
            offset == nextOffset,
            totalByteCount == expectedByteCount,
            nextOffset + Int64(data.count) <= expectedByteCount,
            isComplete || !data.isEmpty
        else {
            throw ChunkedDownloadWriterError.invalidChunk
        }

        try handle.write(contentsOf: data)
        nextOffset += Int64(data.count)

        if isComplete {
            guard nextOffset == expectedByteCount else {
                throw ChunkedDownloadWriterError.invalidChunk
            }
            try handle.close()
            self.handle = nil
        } else if nextOffset >= expectedByteCount {
            throw ChunkedDownloadWriterError.invalidChunk
        }

        return ChunkedDownloadProgress(
            progress: expectedByteCount == 0
                ? 1
                : Double(nextOffset) / Double(expectedByteCount),
            isComplete: isComplete
        )
    }

    public func cancel() throws {
        var firstError: Error?
        if let handle {
            do {
                try handle.close()
            } catch {
                firstError = error
            }
            self.handle = nil
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            throw firstError
        }
    }
}
