import Foundation
import XCTest
@testable import ReLandHostCore

final class SessionStorageCleanerTests: XCTestCase {
    func testRemovesOnlyStoppedManagedSessions() throws {
        let root = try makeRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try makeSession("rl-active", in: root)
        try makeSession("rl-stopped", in: root)
        try makeSession("unmanaged", in: root)
        let cleaner = SessionStorageCleaner(root: root)

        let summary = try cleaner.removeStoppedSessions(
            activeSessionIDs: ["rl-active"]
        )

        XCTAssertEqual(summary.removedSessionCount, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("rl-active").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("rl-stopped").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("unmanaged").path
            )
        )
    }

    func testRemovesAllManagedSessionsAndReportsBytes() throws {
        let root = try makeRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try makeSession("rl-one", in: root)
        try makeSession("rl-two", in: root)
        let cleaner = SessionStorageCleaner(root: root)

        XCTAssertGreaterThan(try cleaner.byteCount(), 0)
        let summary = try cleaner.removeAllManagedSessions()

        XCTAssertEqual(summary.removedSessionCount, 2)
        XCTAssertEqual(try cleaner.byteCount(), 0)
    }

    func testActiveSessionMatchingIsCaseInsensitive() throws {
        let root = try makeRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try makeSession("rl-Project", in: root)
        let cleaner = SessionStorageCleaner(root: root)

        let summary = try cleaner.removeStoppedSessions(
            activeSessionIDs: ["rl-project"]
        )

        XCTAssertEqual(summary.removedSessionCount, 0)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("rl-Project")
                    .path
            )
        )
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReLandSessionCleaner-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private func makeSession(
        _ id: String,
        in root: URL
    ) throws {
        let directory = root.appendingPathComponent(
            id,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("artifact".utf8).write(
            to: directory.appendingPathComponent("artifact.txt")
        )
        try Data("command".utf8).write(
            to: root
                .appendingPathComponent(id)
                .appendingPathExtension("command")
        )
    }
}
