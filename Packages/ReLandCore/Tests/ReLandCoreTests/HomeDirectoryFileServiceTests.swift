import Foundation
import XCTest
@testable import ReLandCore
@testable import ReLandHostCore

final class HomeDirectoryFileServiceTests: XCTestCase {
    func testListsVisibleEntriesAndReadsFile() throws {
        let root = try makeRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let folder = root.appendingPathComponent(
            "Documents",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        let data = Data("remote file".utf8)
        try data.write(
            to: folder.appendingPathComponent("report.txt")
        )
        try Data("hidden".utf8).write(
            to: root.appendingPathComponent(".secret")
        )

        let service = ApprovedDirectoryFileService(
            roots: [
                RemoteFileRoot(
                    id: "test",
                    name: "Test",
                    url: root
                ),
            ]
        )
        let rootList = try service.list(
            request: RemoteFileListRequest()
        )
        XCTAssertEqual(rootList.entries.map(\.name), ["Test"])

        let folderList = try service.list(
            request: RemoteFileListRequest(
                path: "@test/Documents"
            )
        )
        let file = try XCTUnwrap(folderList.entries.first)
        XCTAssertEqual(file.kind, .text)
        XCTAssertEqual(file.byteCount, Int64(data.count))
        XCTAssertEqual(
            try service.resolveDirectory(
                path: "@test/Documents"
            ),
            folder.standardizedFileURL
        )
        XCTAssertThrowsError(
            try service.resolveDirectory(path: file.path)
        )

        let chunk = try service.read(
            request: RemoteFileReadRequest(
                path: file.path,
                offset: 0
            )
        )
        XCTAssertTrue(chunk.isComplete)
        XCTAssertEqual(chunk.data, data)
    }

    func testRejectsTraversalAndSymlinks() throws {
        let root = try makeRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReLandOutside-\(UUID().uuidString).txt"
            )
        defer {
            try? FileManager.default.removeItem(at: outside)
        }
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked.txt"),
            withDestinationURL: outside
        )

        let service = ApprovedDirectoryFileService(
            roots: [
                RemoteFileRoot(
                    id: "test",
                    name: "Test",
                    url: root
                ),
            ]
        )
        XCTAssertEqual(
            try service.list(
                request: RemoteFileListRequest()
            ).entries.map(\.name),
            ["Test"]
        )
        XCTAssertTrue(
            try service.list(
                request: RemoteFileListRequest(path: "@test")
            ).entries.isEmpty
        )
        XCTAssertThrowsError(
            try service.list(
                request: RemoteFileListRequest(path: "../")
            )
        )
        XCTAssertThrowsError(
            try service.read(
                request: RemoteFileReadRequest(
                    path: "@test/linked.txt",
                    offset: 0
                )
            )
        )
        XCTAssertThrowsError(
            try service.read(
                request: RemoteFileReadRequest(
                    path: "@test/.ssh/id_rsa",
                    offset: 0
                )
            )
        )
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReLandHome-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }
}
