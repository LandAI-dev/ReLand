import Testing
@testable import ReLandCore

struct CaptureTargetHistoryTests {
    @Test
    func cyclesStableMRUOrderWithoutBouncing() {
        var history = CaptureTargetHistory()
        history.recordExplicitSelection(id: "window-b")
        history.recordExplicitSelection(id: "window-a")
        let available = [
            "window-a",
            "window-b",
            "window-c",
        ]

        let second = history.targetID(
            from: "window-a",
            direction: .next,
            availableIDs: available
        )
        let third = history.targetID(
            from: second,
            direction: .next,
            availableIDs: available
        )
        let wrapped = history.targetID(
            from: third,
            direction: .next,
            availableIDs: available
        )

        #expect(second == "window-b")
        #expect(third == "window-c")
        #expect(wrapped == "window-a")
    }

    @Test
    func cyclesBackwardAndPrunesClosedWindows() {
        var history = CaptureTargetHistory()
        history.recordExplicitSelection(id: "window-c")
        history.recordExplicitSelection(id: "window-b")
        history.recordExplicitSelection(id: "window-a")
        history.prune(availableIDs: ["window-a", "window-c"])

        #expect(
            history.targetID(
                from: "window-a",
                direction: .previous,
                availableIDs: ["window-a", "window-c"]
            ) == "window-c"
        )
        #expect(history.orderedIDs == ["window-a", "window-c"])
    }
}
