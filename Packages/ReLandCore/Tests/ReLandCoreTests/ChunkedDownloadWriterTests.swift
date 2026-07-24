import Foundation
import XCTest
@testable import ReLandCore

final class ChunkedDownloadWriterTests: XCTestCase {
    func testWritesValidatedChunksAndKeepsCompletedFile() throws {
        let file = temporaryFileURL()
        defer {
            try? FileManager.default.removeItem(
                at: file.deletingLastPathComponent()
            )
        }
        let writer = try ChunkedDownloadWriter(
            fileURL: file,
            expectedByteCount: 8,
            maximumByteCount: 8
        )

        let first = try writer.append(
            offset: 0,
            totalByteCount: 8,
            data: Data("abcd".utf8),
            isComplete: false
        )
        XCTAssertEqual(first.progress, 0.5)
        XCTAssertFalse(first.isComplete)

        let second = try writer.append(
            offset: 4,
            totalByteCount: 8,
            data: Data("efgh".utf8),
            isComplete: true
        )
        XCTAssertEqual(second.progress, 1)
        XCTAssertTrue(second.isComplete)
        XCTAssertEqual(
            try Data(contentsOf: file),
            Data("abcdefgh".utf8)
        )
    }

    func testRejectsOutOfOrderOrMismatchedChunks() throws {
        let file = temporaryFileURL()
        defer {
            try? FileManager.default.removeItem(
                at: file.deletingLastPathComponent()
            )
        }
        let writer = try ChunkedDownloadWriter(
            fileURL: file,
            expectedByteCount: 4,
            maximumByteCount: 4
        )

        XCTAssertThrowsError(
            try writer.append(
                offset: 1,
                totalByteCount: 4,
                data: Data("a".utf8),
                isComplete: false
            )
        ) { error in
            XCTAssertEqual(
                error as? ChunkedDownloadWriterError,
                .invalidChunk
            )
        }
        XCTAssertThrowsError(
            try writer.append(
                offset: 0,
                totalByteCount: 5,
                data: Data("abcd".utf8),
                isComplete: true
            )
        ) { error in
            XCTAssertEqual(
                error as? ChunkedDownloadWriterError,
                .invalidChunk
            )
        }
    }

    func testCancelRemovesPartialFile() throws {
        let file = temporaryFileURL()
        defer {
            try? FileManager.default.removeItem(
                at: file.deletingLastPathComponent()
            )
        }
        let writer = try ChunkedDownloadWriter(
            fileURL: file,
            expectedByteCount: 4,
            maximumByteCount: 4
        )
        _ = try writer.append(
            offset: 0,
            totalByteCount: 4,
            data: Data("ab".utf8),
            isComplete: false
        )

        try writer.cancel()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path)
        )
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReLandChunkedDownload-\(UUID().uuidString)",
                isDirectory: true
            )
            .appendingPathComponent("download.bin")
    }
}
