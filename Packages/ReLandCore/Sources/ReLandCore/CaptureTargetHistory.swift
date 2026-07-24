import Foundation

public enum CaptureCycleDirection: Sendable {
    case next
    case previous
}

public struct CaptureTargetHistory: Sendable {
    public private(set) var orderedIDs: [String] = []

    public init() {}

    public mutating func recordExplicitSelection(id: String) {
        guard !id.isEmpty else {
            return
        }
        orderedIDs.removeAll { $0 == id }
        orderedIDs.insert(id, at: 0)
    }

    public mutating func prune(availableIDs: [String]) {
        let available = Set(availableIDs)
        orderedIDs.removeAll { !available.contains($0) }
    }

    public func targetID(
        from currentID: String?,
        direction: CaptureCycleDirection,
        availableIDs: [String]
    ) -> String? {
        var order = orderedIDs.filter(availableIDs.contains)
        for id in availableIDs where !order.contains(id) {
            order.append(id)
        }
        guard !order.isEmpty else {
            return nil
        }
        guard
            let currentID,
            let currentIndex = order.firstIndex(of: currentID)
        else {
            return order.first
        }

        switch direction {
        case .next:
            return order[(currentIndex + 1) % order.count]
        case .previous:
            return order[
                (currentIndex - 1 + order.count) % order.count
            ]
        }
    }
}
