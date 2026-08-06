import Foundation
import XCTest
@testable import ReLandCore
@testable import ReLandHostCore

final class TmuxTerminalServiceTests: XCTestCase, @unchecked Sendable {
    func testCreatedSessionLookupRetriesUntilVisible() throws {
        let expected = TerminalSessionInfo(
            id: "rl-terminal",
            name: "terminal",
            windowCount: 1,
            attachedClientCount: 0,
            createdAt: .now
        )
        var attempts = 0
        var delays = 0

        let resolved = try TmuxTerminalService.resolveCreatedSession(
            sessionID: expected.id,
            maximumAttempts: 3,
            retryDelay: {
                delays += 1
            },
            listSessions: {
                attempts += 1
                return attempts == 1 ? [] : [expected]
            }
        )

        XCTAssertEqual(resolved, expected)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(delays, 1)
    }

    func testCreatedSessionLookupStopsAfterMaximumAttempts() throws {
        var attempts = 0
        var delays = 0

        let resolved = try TmuxTerminalService.resolveCreatedSession(
            sessionID: "rl-terminal",
            maximumAttempts: 3,
            retryDelay: {
                delays += 1
            },
            listSessions: {
                attempts += 1
                return []
            }
        )

        XCTAssertNil(resolved)
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(delays, 2)
    }

    func testSessionReservationRetriesAfterDuplicateName() throws {
        var attempts: [String] = []

        let sessionID = try TmuxTerminalService.reserveSessionID(
            baseName: "terminal",
            existingIDs: []
        ) { candidate in
            attempts.append(candidate)
            return attempts.count > 1
        }

        XCTAssertEqual(attempts, ["rl-terminal", "rl-terminal-2"])
        XCTAssertEqual(sessionID, "rl-terminal-2")
    }

    func testSessionReservationSkipsRetainedStorageID() throws {
        var attempts: [String] = []

        let sessionID = try TmuxTerminalService.reserveSessionID(
            baseName: "terminal",
            existingIDs: ["rl-terminal"]
        ) { candidate in
            attempts.append(candidate)
            return true
        }

        XCTAssertEqual(attempts, ["rl-terminal-2"])
        XCTAssertEqual(sessionID, "rl-terminal-2")
    }

    func testSessionReservationTreatsIDsCaseInsensitively() throws {
        var attempts: [String] = []

        let sessionID = try TmuxTerminalService.reserveSessionID(
            baseName: "Project",
            existingIDs: ["rl-project"]
        ) { candidate in
            attempts.append(candidate)
            return true
        }

        XCTAssertEqual(attempts, ["rl-project-2"])
        XCTAssertEqual(sessionID, "rl-project-2")
    }

    func testRepeatedDefaultSessionCreationUsesDistinctNames() throws {
        let (service, root) = try makeService()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let first = try service.createSession(preferredName: nil)
        defer {
            try? service.killSession(sessionID: first.id)
        }
        let second = try service.createSession(preferredName: nil)
        defer {
            try? service.killSession(sessionID: second.id)
        }

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(first.id.hasPrefix("rl-terminal"))
        XCTAssertTrue(second.id.hasPrefix("rl-terminal"))
    }

    func testRenameSessionPreservesStableSessionID() throws {
        let (service, root) = try makeService()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let session = try service.createSession(
            preferredName: "rename-\(UUID().uuidString.prefix(8))"
        )
        defer {
            try? service.killSession(sessionID: session.id)
        }

        try service.renameSession(
            sessionID: session.id,
            name: "Project API"
        )

        let renamed = try XCTUnwrap(
            service.listSessions().first {
                $0.id == session.id
            }
        )
        XCTAssertEqual(renamed.id, session.id)
        XCTAssertEqual(renamed.name, "Project API")
    }

    func testRenameSessionRejectsUnicodeLineSeparators() throws {
        let (service, root) = try makeService()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let session = try service.createSession(
            preferredName: "rename-lines"
        )
        defer {
            try? service.killSession(sessionID: session.id)
        }

        XCTAssertThrowsError(
            try service.renameSession(
                sessionID: session.id,
                name: "Project\u{2028}API"
            )
        )
    }

    func testNewSessionReceivesArtifactEnvironment() throws {
        let (service, root) = try makeService()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let session = try service.createSession(
            preferredName: "artifact-env-\(UUID().uuidString.prefix(8))"
        )
        defer {
            try? service.killSession(sessionID: session.id)
        }
        XCTAssertTrue(session.id.hasPrefix("rl-"))

        let output = expectation(
            description: "Artifact environment available"
        )
        let collector = TerminalOutputCollector(
            token: "RELAND_WORKSPACE_OK",
            expectation: output
        )
        let attachment = try service.attach(
            attachmentID: UUID(),
            sessionID: session.id,
            columns: 80,
            rows: 24,
            outputHandler: collector.receive,
            terminationHandler: {}
        )
        attachment.start()
        Thread.sleep(forTimeInterval: 0.5)
        attachment.send(
            Data(
                """
                test -d "$RELAND_ARTIFACTS_DIR" \
                && test -n "$RELAND_INSTRUCTIONS_DIR" \
                && test "$PWD" = "$(dirname "$RELAND_ARTIFACTS_DIR")" \
                && command -v reland-artifact >/dev/null \
                && command -v reland-ai >/dev/null \
                && command -v landai >/dev/null \
                && printf 'RELAND_%s\\n' 'WORKSPACE_OK'\r
                """.utf8
            )
        )
        wait(for: [output], timeout: 5)
        attachment.close()
    }

    func testSessionPersistsAcrossRemoteAttachments() throws {
        let (service, root) = try makeService()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let preferredName = "test-\(UUID().uuidString.prefix(8))"
        let session = try service.createSession(
            preferredName: preferredName
        )
        defer {
            try? service.killSession(sessionID: session.id)
        }

        let firstToken = "RELAND_FIRST_\(UUID().uuidString)"
        let firstOutput = expectation(description: "First attachment output")
        let firstCollector = TerminalOutputCollector(
            token: firstToken,
            expectation: firstOutput
        )
        let firstAttachment = try service.attach(
            attachmentID: UUID(),
            sessionID: session.id,
            columns: 100,
            rows: 30,
            outputHandler: firstCollector.receive,
            terminationHandler: {}
        )
        firstAttachment.start()
        Thread.sleep(forTimeInterval: 0.5)
        firstAttachment.send(
            Data("printf '\(firstToken)\\n'\r".utf8)
        )
        wait(for: [firstOutput], timeout: 5)
        firstAttachment.close()

        let secondToken = "RELAND_SECOND_\(UUID().uuidString)"
        let secondOutput = expectation(
            description: "Second attachment output"
        )
        let secondCollector = TerminalOutputCollector(
            token: secondToken,
            expectation: secondOutput
        )
        let secondAttachment = try service.attach(
            attachmentID: UUID(),
            sessionID: session.id,
            columns: 80,
            rows: 24,
            outputHandler: secondCollector.receive,
            terminationHandler: {}
        )
        secondAttachment.start()
        Thread.sleep(forTimeInterval: 0.5)
        secondAttachment.send(
            Data("printf '\(secondToken)\\n'\r".utf8)
        )
        wait(for: [secondOutput], timeout: 5)
        secondAttachment.close()

        XCTAssertTrue(
            try service.listSessions().contains {
                $0.id == session.id
            }
        )
    }

    func testSessionUsesApprovedWorkingDirectory() throws {
        let (service, root) = try makeService()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReLandWorkingDirectory-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: workingDirectory
            )
        }

        let session = try service.createSession(
            preferredName: "working-directory",
            launchProfile: .shell,
            launchArguments: [],
            workingDirectory: workingDirectory
        )
        defer {
            try? service.killSession(sessionID: session.id)
        }
        let output = expectation(
            description: "Approved working directory used"
        )
        let collector = TerminalOutputCollector(
            token: "RELAND_PROJECT_DIRECTORY_OK",
            expectation: output
        )
        let attachment = try service.attach(
            attachmentID: UUID(),
            sessionID: session.id,
            columns: 80,
            rows: 24,
            outputHandler: collector.receive,
            terminationHandler: {}
        )
        attachment.start()
        Thread.sleep(forTimeInterval: 0.5)
        attachment.send(
            Data(
                """
                test "$PWD" = "\(workingDirectory.path)" \
                && printf 'RELAND_%s\\n' 'PROJECT_DIRECTORY_OK'\r
                """.utf8
            )
        )
        wait(for: [output], timeout: 5)
        attachment.close()
    }

    private func makeService() throws -> (
        service: TmuxTerminalService,
        root: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReLandTmuxService-\(UUID().uuidString)",
                isDirectory: true
            )
        do {
            return (
                try TmuxTerminalService(
                    artifactRoot: root,
                    serverName:
                        "reland-test-"
                        + UUID().uuidString.lowercased()
                ),
                root
            )
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw XCTSkip("tmux is not installed")
        }
    }
}

private final class TerminalOutputCollector: @unchecked Sendable {
    private let token: String
    private let expectation: XCTestExpectation
    private let lock = NSLock()
    private var buffer = Data()
    private var fulfilled = false

    init(token: String, expectation: XCTestExpectation) {
        self.token = token
        self.expectation = expectation
    }

    func receive(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !fulfilled else {
            return
        }
        buffer.append(data)
        if String(decoding: buffer, as: UTF8.self).contains(token) {
            fulfilled = true
            expectation.fulfill()
        }
    }
}
