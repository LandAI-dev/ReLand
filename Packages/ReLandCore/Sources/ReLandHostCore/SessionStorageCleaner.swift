import Foundation

public struct SessionCleanupSummary: Equatable, Sendable {
    public let removedSessionCount: Int
    public let removedByteCount: Int64
}

public struct SessionStorageCleaner {
    private let root: URL
    private let fileManager: FileManager

    public init(
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

    public var rootURL: URL {
        root
    }

    public func byteCount() throws -> Int64 {
        try managedSessionIDs().reduce(0) { result, id in
            result + (try byteCount(for: id))
        }
    }

    public func removeStoppedSessions(
        activeSessionIDs: Set<String>
    ) throws -> SessionCleanupSummary {
        try removeManagedSessions(
            matching: { !activeSessionIDs.contains($0) }
        )
    }

    public func removeAllManagedSessions()
        throws -> SessionCleanupSummary
    {
        try removeManagedSessions(matching: { _ in true })
    }

    private func removeManagedSessions(
        matching shouldRemove: (String) -> Bool
    ) throws -> SessionCleanupSummary {
        var removedSessionCount = 0
        var removedByteCount: Int64 = 0
        for id in try managedSessionIDs().sorted()
        where shouldRemove(id) {
            removedByteCount += try byteCount(for: id)
            let directory = root.appendingPathComponent(
                id,
                isDirectory: true
            )
            let command = root
                .appendingPathComponent(id)
                .appendingPathExtension("command")
            for url in [directory, command]
            where fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            removedSessionCount += 1
        }
        return SessionCleanupSummary(
            removedSessionCount: removedSessionCount,
            removedByteCount: removedByteCount
        )
    }

    private func managedSessionIDs() throws -> Set<String> {
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }
        let entries = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return Set(entries.compactMap { url in
            let candidate = url.pathExtension == "command"
                ? url.deletingPathExtension().lastPathComponent
                : url.lastPathComponent
            return Self.isManagedSessionID(candidate)
                ? candidate
                : nil
        })
    }

    private func byteCount(for sessionID: String) throws -> Int64 {
        let directory = root.appendingPathComponent(
            sessionID,
            isDirectory: true
        )
        let command = root
            .appendingPathComponent(sessionID)
            .appendingPathExtension("command")
        return try [directory, command].reduce(0) { result, url in
            result + (try byteCount(at: url))
        }
    }

    private func byteCount(at url: URL) throws -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else {
            return 0
        }
        let values = try url.resourceValues(
            forKeys: [
                .fileSizeKey,
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        )
        if values.isSymbolicLink == true {
            return 0
        }
        if values.isRegularFile == true {
            return Int64(values.fileSize ?? 0)
        }
        guard values.isDirectory == true else {
            return 0
        }
        let children = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try children.reduce(0) {
            $0 + (try byteCount(at: $1))
        }
    }

    private static func isManagedSessionID(
        _ value: String
    ) -> Bool {
        guard value.hasPrefix("rl-"), value.count > 3 else {
            return false
        }
        return value.allSatisfy {
            $0.isLetter
                || $0.isNumber
                || $0 == "-"
                || $0 == "_"
        }
    }
}
