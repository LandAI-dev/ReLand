import Foundation

struct ChunkedFileReadResult: Equatable {
    let totalByteCount: Int64
    let data: Data
    let isComplete: Bool
}

enum ChunkedFileReaderError: Error, Equatable {
    case invalidReadRequest
    case fileUnavailable
    case fileTooLarge
}

enum ChunkedFileReader {
    static func read(
        fileURL: URL,
        offset: Int64,
        length: Int,
        maximumChunkLength: Int,
        maximumFileSize: Int64
    ) throws -> ChunkedFileReadResult {
        guard
            offset >= 0,
            length > 0,
            maximumChunkLength > 0,
            length <= maximumChunkLength,
            maximumFileSize >= 0
        else {
            throw ChunkedFileReaderError.invalidReadRequest
        }

        let values = try fileURL.resourceValues(
            forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        )
        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let fileSize = values.fileSize
        else {
            throw ChunkedFileReaderError.fileUnavailable
        }

        let totalByteCount = Int64(fileSize)
        guard
            totalByteCount <= maximumFileSize,
            offset <= totalByteCount
        else {
            throw ChunkedFileReaderError.fileTooLarge
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        do {
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: length) ?? Data()
            try handle.close()
            return ChunkedFileReadResult(
                totalByteCount: totalByteCount,
                data: data,
                isComplete:
                    offset + Int64(data.count) >= totalByteCount
            )
        } catch {
            try? handle.close()
            throw error
        }
    }
}
