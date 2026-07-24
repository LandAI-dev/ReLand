import Foundation
import XCTest
@testable import ReLandHostCore

final class ChunkedFileReaderTests: XCTestCase {
    func testReadsChunksAndCompletesAtFileBoundary() throws {
        let file = try makeFile(Data("abcdefgh".utf8))
        defer {
            try? FileManager.default.removeItem(
                at: file.deletingLastPathComponent()
            )
        }

        let first = try ChunkedFileReader.read(
            fileURL: file,
            offset: 0,
            length: 4,
            maximumChunkLength: 4,
            maximumFileSize: 8
        )
        XCTAssertEqual(first.data, Data("abcd".utf8))
        XCTAssertEqual(first.totalByteCount, 8)
        XCTAssertFalse(first.isComplete)

        let second = try ChunkedFileReader.read(
            fileURL: file,
            offset: 4,
            length: 4,
            maximumChunkLength: 4,
            maximumFileSize: 8
        )
        XCTAssertEqual(second.data, Data("efgh".utf8))
        XCTAssertTrue(second.isComplete)

        let boundary = try ChunkedFileReader.read(
            fileURL: file,
            offset: 8,
            length: 4,
            maximumChunkLength: 4,
            maximumFileSize: 8
        )
        XCTAssertTrue(boundary.data.isEmpty)
        XCTAssertTrue(boundary.isComplete)
    }

    func testRejectsInvalidRequestsAndOversizedFiles() throws {
        let file = try makeFile(Data("abcde".utf8))
        defer {
            try? FileManager.default.removeItem(
                at: file.deletingLastPathComponent()
            )
        }

        XCTAssertThrowsError(
            try ChunkedFileReader.read(
                fileURL: file,
                offset: -1,
                length: 1,
                maximumChunkLength: 4,
                maximumFileSize: 8
            )
        ) { error in
            XCTAssertEqual(
                error as? ChunkedFileReaderError,
                .invalidReadRequest
            )
        }
        XCTAssertThrowsError(
            try ChunkedFileReader.read(
                fileURL: file,
                offset: 0,
                length: 5,
                maximumChunkLength: 4,
                maximumFileSize: 8
            )
        ) { error in
            XCTAssertEqual(
                error as? ChunkedFileReaderError,
                .invalidReadRequest
            )
        }
        XCTAssertThrowsError(
            try ChunkedFileReader.read(
                fileURL: file,
                offset: 0,
                length: 4,
                maximumChunkLength: 4,
                maximumFileSize: 4
            )
        ) { error in
            XCTAssertEqual(
                error as? ChunkedFileReaderError,
                .fileTooLarge
            )
        }
    }

    private func makeFile(_ data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReLandChunkedFile-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent("file.bin")
        try data.write(to: file)
        return file
    }
}
