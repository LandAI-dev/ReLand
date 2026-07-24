import Foundation
import XCTest
@testable import ReLandCore
@testable import ReLandHostCore

final class TerminalArtifactStoreTests: XCTestCase {
    func testListsAndReadsArtifactChunks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReLandArtifactStore-\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = TerminalArtifactStore(root: root)
        let resources = try store.prepareSession(
            sessionID: "rl-artifacts"
        )
        let artifactData = Data(
            repeating: 0x41,
            count: ReLandConstants.artifactChunkSize + 17
        )
        let artifactURL = resources.artifacts
            .appendingPathComponent("capture.txt")
        try artifactData.write(to: artifactURL)

        let artifacts = try store.listArtifacts(
            sessionID: "rl-artifacts"
        )
        let artifact = try XCTUnwrap(artifacts.first)
        XCTAssertEqual(artifact.name, "capture.txt")
        XCTAssertEqual(artifact.kind, .text)
        XCTAssertEqual(
            artifact.byteCount,
            Int64(artifactData.count)
        )

        let first = try store.readArtifact(
            request: TerminalArtifactReadRequest(
                sessionID: "rl-artifacts",
                artifactID: artifact.id,
                offset: 0
            )
        )
        XCTAssertFalse(first.isComplete)
        XCTAssertEqual(
            first.data.count,
            ReLandConstants.artifactChunkSize
        )

        let second = try store.readArtifact(
            request: TerminalArtifactReadRequest(
                sessionID: "rl-artifacts",
                artifactID: artifact.id,
                offset: Int64(first.data.count)
            )
        )
        XCTAssertTrue(second.isComplete)
        XCTAssertEqual(first.data + second.data, artifactData)
    }

    func testCreatesCopilotInstructionsAndHelper() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReLandArtifactInstructions-\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = TerminalArtifactStore(root: root)
        let resources = try store.prepareSession(
            sessionID: "rl-copilot"
        )
        let instructionURL = resources.instructions
            .appendingPathComponent(
                "reland-artifacts.instructions.md"
            )
        let instructions = try String(
            contentsOf: instructionURL,
            encoding: .utf8
        )
        XCTAssertTrue(
            instructions.contains(resources.artifacts.path)
        )
        XCTAssertTrue(
            instructions.contains("reland-ai artifact add")
        )
        for fileName in [
            "AGENTS.md",
            "CLAUDE.md",
            "GEMINI.md",
            "reland-artifacts.md",
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: resources.instructions
                        .appendingPathComponent(fileName).path
                )
            )
        }

        let helper = resources.bin.appendingPathComponent(
            "reland-artifact"
        )
        XCTAssertTrue(
            FileManager.default.isExecutableFile(
                atPath: helper.path
            )
        )
        XCTAssertTrue(
            FileManager.default.isExecutableFile(
                atPath: resources.bin
                    .appendingPathComponent("reland-ai").path
            )
        )
        XCTAssertTrue(
            FileManager.default.isExecutableFile(
                atPath: resources.bin
                    .appendingPathComponent("landai").path
            )
        )
    }

    func testSymlinksAreNotExposed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReLandArtifactSymlink-\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = TerminalArtifactStore(root: root)
        let resources = try store.prepareSession(
            sessionID: "rl-links"
        )
        let outside = root.appendingPathComponent("private.txt")
        try Data("private".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: resources.artifacts.appendingPathComponent(
                "linked.txt"
            ),
            withDestinationURL: outside
        )

        XCTAssertTrue(
            try store.listArtifacts(
                sessionID: "rl-links"
            ).isEmpty
        )
    }

    func testLandAIWrapperConfiguresSupportedTools() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReLandAIWrapper-\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let fakeBin = root.appendingPathComponent(
            "fake-bin",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: fakeBin,
            withIntermediateDirectories: true
        )
        for tool in ["copilot", "claude", "codex", "gemini"] {
            let script = """
            #!/bin/zsh
            print -r -- "TOOL=\(tool)"
            print -r -- "COPILOT_DIRS=${COPILOT_CUSTOM_INSTRUCTIONS_DIRS:-}"
            print -l -- "$@"
            """
            let url = fakeBin.appendingPathComponent(tool)
            try Data(script.utf8).write(to: url)
            XCTAssertEqual(chmod(url.path, 0o700), 0)
        }

        let resources = try TerminalArtifactStore(root: root)
            .prepareSession(sessionID: "rl-ai")
        let wrapper = resources.bin.appendingPathComponent(
            "reland-ai"
        )
        let environment = [
            "HOME": NSHomeDirectory(),
            "RELAND_ARTIFACTS_DIR":
                resources.artifacts.path,
            "RELAND_INSTRUCTIONS_DIR":
                resources.instructions.path,
            "PATH":
                "\(resources.bin.path):\(fakeBin.path):"
                + "/usr/bin:/bin:/usr/sbin:/sbin",
        ]

        let copilot = try run(
            wrapper,
            arguments: ["copilot", "--test"],
            environment: environment
        )
        XCTAssertTrue(
            copilot.contains(
                "COPILOT_DIRS=\(resources.instructions.path)"
            )
        )

        let claude = try run(
            wrapper,
            arguments: ["claude", "--test"],
            environment: environment
        )
        XCTAssertTrue(
            claude.contains("--append-system-prompt-file")
        )
        XCTAssertTrue(
            claude.contains("reland-artifacts.md")
        )

        let codex = try run(
            wrapper,
            arguments: ["codex", "--test"],
            environment: environment
        )
        XCTAssertTrue(codex.contains("--config"))
        XCTAssertTrue(
            codex.contains("model_instructions_file=")
        )

        let gemini = try run(
            wrapper,
            arguments: ["gemini", "--test"],
            environment: environment
        )
        XCTAssertTrue(gemini.contains("--include-directories"))
        XCTAssertTrue(
            gemini.contains(resources.instructions.path)
        )

        let alias = resources.bin.appendingPathComponent("landai")
        let aliased = try run(
            alias,
            arguments: ["copilot", "--test"],
            environment: environment
        )
        XCTAssertTrue(aliased.contains("TOOL=copilot"))
    }

    private func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let outputData = output.fileHandleForReading
            .readDataToEndOfFile()
        let errorData = error.fileHandleForReading
            .readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            String(decoding: errorData, as: UTF8.self)
        )
        return String(decoding: outputData, as: UTF8.self)
    }
}
