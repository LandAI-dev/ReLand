import Foundation

public struct TerminalWorkingDirectory:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let path: String
    public let name: String

    public var id: String { path }

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

public struct TerminalWorkingDirectoryHistory:
    Codable,
    Equatable,
    Sendable
{
    private struct HostHistory:
        Codable,
        Equatable,
        Sendable
    {
        var preferredPath: String?
        var directories: [TerminalWorkingDirectory]
    }

    private static let maximumRecentDirectoryCount = 5

    private var historiesByHost: [String: HostHistory] = [:]

    public init() {}

    public func preferredDirectory(
        for hostID: String
    ) -> TerminalWorkingDirectory? {
        guard let history = historiesByHost[hostID] else {
            return nil
        }
        return history.directories.first {
            $0.path == history.preferredPath
        }
    }

    public func recentDirectories(
        for hostID: String
    ) -> [TerminalWorkingDirectory] {
        historiesByHost[hostID]?.directories ?? []
    }

    public mutating func remember(
        _ directory: TerminalWorkingDirectory,
        for hostID: String
    ) {
        var history = historiesByHost[hostID]
            ?? HostHistory(
                preferredPath: nil,
                directories: []
            )
        history.directories.removeAll {
            $0.path == directory.path
        }
        history.directories.insert(directory, at: 0)
        history.directories = Array(
            history.directories.prefix(
                Self.maximumRecentDirectoryCount
            )
        )
        history.preferredPath = directory.path
        historiesByHost[hostID] = history
    }

    public mutating func preferSessionWorkspace(
        for hostID: String
    ) {
        guard var history = historiesByHost[hostID] else {
            return
        }
        history.preferredPath = nil
        historiesByHost[hostID] = history
    }

    public mutating func retainDirectories(
        for hostID: String,
        matching isAvailable:
            (TerminalWorkingDirectory) -> Bool
    ) {
        guard var history = historiesByHost[hostID] else {
            return
        }
        history.directories = history.directories.filter(
            isAvailable
        )
        if
            !history.directories.contains(where: {
                $0.path == history.preferredPath
            })
        {
            history.preferredPath = nil
        }
        if history.directories.isEmpty {
            historiesByHost.removeValue(forKey: hostID)
        } else {
            historiesByHost[hostID] = history
        }
    }
}
