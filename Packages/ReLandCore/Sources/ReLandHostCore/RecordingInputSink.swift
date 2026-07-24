import Foundation
import ReLandCore

public final class RecordingInputSink: RemoteInputSink, @unchecked Sendable {
    public var onEvent: (@Sendable (RemoteInputEvent, String) -> Void)?

    private let lock = NSLock()
    private var events: [RemoteInputEvent] = []

    public init() {}

    public func handle(_ event: RemoteInputEvent) -> String {
        lock.lock()
        events.append(event)
        let count = events.count
        lock.unlock()

        let summary = "\(count): \(Self.summary(for: event))"
        onEvent?(event, summary)
        return summary
    }

    public func recordedEvents() -> [RemoteInputEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    private static func summary(for event: RemoteInputEvent) -> String {
        switch event {
        case let .pointerDelta(x, y):
            "move \(Int(x)),\(Int(y))"
        case let .pointerAbsolute(x, y):
            "absolute \(x),\(y)"
        case let .button(button, isDown, clickCount):
            "\(button.rawValue) \(isDown ? "down" : "up") x\(clickCount)"
        case let .scroll(x, y):
            "scroll \(Int(x)),\(Int(y))"
        case let .text(value):
            "text \(value.count) characters"
        case let .key(code, isDown, _):
            "key \(code) \(isDown ? "down" : "up")"
        }
    }
}
