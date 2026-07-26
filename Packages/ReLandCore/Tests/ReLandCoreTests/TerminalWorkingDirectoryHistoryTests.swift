import Foundation
import Testing
@testable import ReLandCore

struct TerminalWorkingDirectoryHistoryTests {
    @Test
    func remembersRecentDirectoriesPerHost() {
        var history = TerminalWorkingDirectoryHistory()
        let first = TerminalWorkingDirectory(
            path: "@projects/First",
            name: "First"
        )
        let renamed = TerminalWorkingDirectory(
            path: "@projects/First",
            name: "First Renamed"
        )
        let second = TerminalWorkingDirectory(
            path: "@projects/Second",
            name: "Second"
        )

        history.remember(first, for: "mac-a")
        history.remember(second, for: "mac-a")
        history.remember(renamed, for: "mac-a")
        history.remember(first, for: "mac-b")

        #expect(
            history.recentDirectories(for: "mac-a")
                == [renamed, second]
        )
        #expect(
            history.preferredDirectory(for: "mac-a")
                == renamed
        )
        #expect(
            history.recentDirectories(for: "mac-b")
                == [first]
        )
    }

    @Test
    func sessionWorkspaceKeepsRecentsWithoutAutoSelectingOne() {
        var history = TerminalWorkingDirectoryHistory()
        let directory = TerminalWorkingDirectory(
            path: "@projects/ReLand",
            name: "ReLand"
        )
        history.remember(directory, for: "mac")

        history.preferSessionWorkspace(for: "mac")

        #expect(history.preferredDirectory(for: "mac") == nil)
        #expect(
            history.recentDirectories(for: "mac")
                == [directory]
        )
    }

    @Test
    func limitsAndRoundTripsRecentDirectories() throws {
        var history = TerminalWorkingDirectoryHistory()
        for index in 1...7 {
            history.remember(
                TerminalWorkingDirectory(
                    path: "@projects/\(index)",
                    name: "Project \(index)"
                ),
                for: "mac"
            )
        }

        let decoded = try JSONDecoder().decode(
            TerminalWorkingDirectoryHistory.self,
            from: JSONEncoder().encode(history)
        )

        #expect(
            decoded.recentDirectories(for: "mac").map(\.name)
                == [
                    "Project 7",
                    "Project 6",
                    "Project 5",
                    "Project 4",
                    "Project 3",
                ]
        )
        #expect(decoded == history)
    }

    @Test
    func removesDirectoriesWhoseApprovalIsUnavailable() {
        var history = TerminalWorkingDirectoryHistory()
        let available = TerminalWorkingDirectory(
            path: "@available/Project",
            name: "Available"
        )
        let removed = TerminalWorkingDirectory(
            path: "@removed/Project",
            name: "Removed"
        )
        history.remember(available, for: "mac")
        history.remember(removed, for: "mac")

        history.retainDirectories(for: "mac") {
            $0.path.hasPrefix("@available/")
        }

        #expect(
            history.recentDirectories(for: "mac")
                == [available]
        )
        #expect(history.preferredDirectory(for: "mac") == nil)
    }
}
