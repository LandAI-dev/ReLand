import CryptoKit
import Foundation
import ReLandCore
import UniformTypeIdentifiers

final class TerminalArtifactStore: @unchecked Sendable {
    struct SessionResources {
        let root: URL
        let artifacts: URL
        let instructions: URL
        let bin: URL
    }

    private static let maximumArtifactCount = 500
    private static let instructionFileName =
        "reland-artifacts.instructions.md"

    private let root: URL
    private let fileManager: FileManager

    init(
        root: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.root = root
            ?? fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            .appendingPathComponent(
                "ReLand/TerminalSessions",
                isDirectory: true
            )
    }

    func prepareSession(
        sessionID: String
    ) throws -> SessionResources {
        let resources = try sessionResources(sessionID: sessionID)
        for directory in [
            resources.root,
            resources.artifacts,
            resources.instructions,
            resources.bin,
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        try writeInstructions(to: resources)
        try writeHelpers(to: resources)
        return resources
    }

    func listArtifacts(
        sessionID: String
    ) throws -> [TerminalArtifactInfo] {
        let resources = try prepareSession(sessionID: sessionID)
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .contentTypeKey,
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: resources.artifacts,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )

        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: keys)
            guard
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                let fileSize = values.fileSize,
                Int64(fileSize)
                    <= ReLandConstants.maximumArtifactSize
            else {
                return nil
            }
            let contentType = values.contentType
                ?? UTType(filenameExtension: url.pathExtension)
                ?? .data
            return TerminalArtifactInfo(
                id: Self.artifactID(for: url.lastPathComponent),
                sessionID: sessionID,
                name: url.lastPathComponent,
                contentType: contentType.identifier,
                kind: Self.kind(for: contentType),
                byteCount: Int64(fileSize),
                modifiedAt:
                    values.contentModificationDate ?? .distantPast
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
        .prefix(Self.maximumArtifactCount)
        .map { $0 }
    }

    func readArtifact(
        request: TerminalArtifactReadRequest
    ) throws -> TerminalArtifactChunk {
        let resources = try prepareSession(
            sessionID: request.sessionID
        )
        let artifact = try artifactURL(
            artifactID: request.artifactID,
            in: resources.artifacts
        )

        let result: ChunkedFileReadResult
        do {
            result = try ChunkedFileReader.read(
                fileURL: artifact,
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
                throw TerminalArtifactStoreError.invalidReadRequest
            case .fileUnavailable:
                throw TerminalArtifactStoreError.artifactUnavailable
            case .fileTooLarge:
                throw TerminalArtifactStoreError.artifactTooLarge
            }
        }
        return TerminalArtifactChunk(
            sessionID: request.sessionID,
            artifactID: request.artifactID,
            offset: request.offset,
            totalByteCount: result.totalByteCount,
            data: result.data,
            isComplete: result.isComplete
        )
    }

    private func sessionResources(
        sessionID: String
    ) throws -> SessionResources {
        guard Self.isSafeSessionID(sessionID) else {
            throw TerminalArtifactStoreError.invalidSession
        }
        let sessionRoot = root
            .appendingPathComponent(sessionID, isDirectory: true)
            .standardizedFileURL
        guard
            sessionRoot.deletingLastPathComponent()
                == root.standardizedFileURL
        else {
            throw TerminalArtifactStoreError.invalidSession
        }
        return SessionResources(
            root: sessionRoot,
            artifacts: sessionRoot.appendingPathComponent(
                "Artifacts",
                isDirectory: true
            ),
            instructions: sessionRoot.appendingPathComponent(
                "Instructions",
                isDirectory: true
            ),
            bin: sessionRoot.appendingPathComponent(
                "bin",
                isDirectory: true
            )
        )
    }

    private func artifactURL(
        artifactID: String,
        in artifactsDirectory: URL
    ) throws -> URL {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: artifactsDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        guard
            let match = try urls.first(where: { url in
                let values = try url.resourceValues(forKeys: keys)
                return values.isRegularFile == true
                    && values.isSymbolicLink != true
                    && Self.artifactID(
                        for: url.lastPathComponent
                    ) == artifactID
            })
        else {
            throw TerminalArtifactStoreError.artifactUnavailable
        }
        let resolvedDirectory = artifactsDirectory
            .resolvingSymlinksInPath()
        let resolvedMatch = match.resolvingSymlinksInPath()
        guard
            resolvedMatch.deletingLastPathComponent()
                == resolvedDirectory
        else {
            throw TerminalArtifactStoreError.artifactUnavailable
        }
        return resolvedMatch
    }

    private func writeInstructions(
        to resources: SessionResources
    ) throws {
        let body = """
        # ReLand session artifacts

        When the user asks for screenshots, recordings, test reports, exported logs, or other files they may want to inspect on their phone:

        - This session's artifact directory is `\(resources.artifacts.path)`.
        - Prefer creating the file in the current workspace, then publish it with `reland-ai artifact add "<path>"`.
        - `$RELAND_ARTIFACTS_DIR` is the canonical phone-visible storage directory.
        - Save directly there only when your file tools have permission to access that path.
        - Use descriptive filenames and include the saved filename in your response.
        - Never place credentials, pairing links, tokens, private keys, or unrelated user files in this directory.
        """
        let copilot = """
        ---
        applyTo: "**"
        ---

        \(body)
        """
        try writeIfChanged(
            Data(copilot.utf8),
            to: resources.instructions.appendingPathComponent(
                Self.instructionFileName
            )
        )
        for fileName in [
            "AGENTS.md",
            "CLAUDE.md",
            "GEMINI.md",
            "reland-artifacts.md",
        ] {
            try writeIfChanged(
                Data(body.utf8),
                to: resources.instructions.appendingPathComponent(
                    fileName
                )
            )
        }
    }

    private func writeHelpers(
        to resources: SessionResources
    ) throws {
        let artifactHelper = resources.bin.appendingPathComponent(
            "reland-artifact"
        )
        let artifactContents = """
        #!/bin/zsh
        set -eu

        : "${RELAND_ARTIFACTS_DIR:?ReLand artifact directory is unavailable}"

        command_name="${1:-}"
        case "$command_name" in
          path)
            print -r -- "$RELAND_ARTIFACTS_DIR"
            ;;
          add)
            source_path="${2:-}"
            if [ -z "$source_path" ] || [ ! -f "$source_path" ]; then
              print -u2 "Usage: reland-artifact add <file>"
              exit 2
            fi
            file_name="$(basename "$source_path")"
            destination="$RELAND_ARTIFACTS_DIR/$file_name"
            if [ -e "$destination" ]; then
              timestamp="$(date +%Y%m%d-%H%M%S)"
              extension="${file_name##*.}"
              stem="${file_name%.*}"
              if [ "$extension" = "$file_name" ]; then
                destination="$RELAND_ARTIFACTS_DIR/$file_name-$timestamp"
              else
                destination="$RELAND_ARTIFACTS_DIR/$stem-$timestamp.$extension"
              fi
            fi
            cp -p "$source_path" "$destination"
            print -r -- "$destination"
            ;;
          *)
            print -u2 "Usage: reland-artifact {path|add <file>}"
            exit 2
            ;;
        esac
        """
        try writeIfChanged(
            Data(artifactContents.utf8),
            to: artifactHelper
        )

        let aiHelper = resources.bin.appendingPathComponent(
            "reland-ai"
        )
        let aiContents = """
        #!/bin/zsh
        set -eu

        : "${RELAND_INSTRUCTIONS_DIR:?ReLand instruction directory is unavailable}"

        command_name="${1:-}"
        if [ -z "$command_name" ]; then
          print -u2 "Usage: reland-ai {copilot|claude|codex|gemini|artifact} [arguments...]"
          exit 2
        fi
        shift

        script_directory="${0:A:h}"
        case "$command_name" in
          artifact)
            exec "$script_directory/reland-artifact" "$@"
            ;;
          copilot)
            executable="$(whence -p copilot || true)"
            [ -n "$executable" ] || { print -u2 "copilot is not installed"; exit 127; }
            export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="$RELAND_INSTRUCTIONS_DIR"
            exec "$executable" "$@"
            ;;
          claude)
            executable="$(whence -p claude || true)"
            [ -n "$executable" ] || { print -u2 "claude is not installed"; exit 127; }
            exec "$executable" \
              --append-system-prompt-file "$RELAND_INSTRUCTIONS_DIR/reland-artifacts.md" \
              "$@"
            ;;
          codex)
            executable="$(whence -p codex || true)"
            [ -n "$executable" ] || { print -u2 "codex is not installed"; exit 127; }
            exec "$executable" \
              --config "model_instructions_file=\\"$RELAND_INSTRUCTIONS_DIR/AGENTS.md\\"" \
              "$@"
            ;;
          gemini)
            executable="$(whence -p gemini || true)"
            [ -n "$executable" ] || { print -u2 "gemini is not installed"; exit 127; }
            exec "$executable" \
              --include-directories "$RELAND_INSTRUCTIONS_DIR" \
              "$@"
            ;;
          *)
            print -u2 "Unsupported ReLand AI command: $command_name"
            exit 2
            ;;
        esac
        """
        try writeIfChanged(Data(aiContents.utf8), to: aiHelper)

        let landAIHelper = resources.bin.appendingPathComponent(
            "landai"
        )
        let landAIContents = """
        #!/bin/zsh
        set -eu

        script_directory="${0:A:h}"
        exec "$script_directory/reland-ai" "$@"
        """
        try writeIfChanged(
            Data(landAIContents.utf8),
            to: landAIHelper
        )

        guard
            chmod(artifactHelper.path, 0o700) == 0,
            chmod(aiHelper.path, 0o700) == 0,
            chmod(landAIHelper.path, 0o700) == 0
        else {
            throw TerminalArtifactStoreError.helperPermissionFailed
        }
    }

    private func writeIfChanged(
        _ data: Data,
        to url: URL
    ) throws {
        if
            let existing = try? Data(contentsOf: url),
            existing == data
        {
            return
        }
        try data.write(to: url, options: .atomic)
    }

    private static func artifactID(for fileName: String) -> String {
        SHA256.hash(data: Data(fileName.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func kind(
        for contentType: UTType
    ) -> TerminalArtifactKind {
        if contentType.conforms(to: .image) {
            return .image
        }
        if contentType.conforms(to: .movie) {
            return .video
        }
        if contentType.conforms(to: .text)
            || contentType.conforms(to: .json)
        {
            return .text
        }
        return .other
    }

    private static func isSafeSessionID(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 64
            && value.allSatisfy {
                $0.isLetter
                    || $0.isNumber
                    || $0 == "-"
                    || $0 == "_"
            }
    }
}

enum TerminalArtifactStoreError: LocalizedError {
    case invalidSession
    case artifactUnavailable
    case artifactTooLarge
    case invalidReadRequest
    case helperPermissionFailed

    var errorDescription: String? {
        switch self {
        case .invalidSession:
            "The terminal artifact session is invalid."
        case .artifactUnavailable:
            "The terminal artifact is no longer available."
        case .artifactTooLarge:
            "The terminal artifact is too large to transfer."
        case .invalidReadRequest:
            "The terminal artifact read request is invalid."
        case .helperPermissionFailed:
            "The terminal artifact helper could not be secured."
        }
    }
}
