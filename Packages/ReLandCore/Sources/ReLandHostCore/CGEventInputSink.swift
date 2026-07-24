import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import ReLandCore

public final class CGEventInputSink: RemoteInputSink, @unchecked Sendable {
    private let lock = NSLock()
    private let targetBoundsProvider:
        @Sendable () -> CGRect?
    private let targetFocusHandler: @Sendable () -> Void
    private var leftButtonIsDown = false
    private var rightButtonIsDown = false

    public init(
        targetBoundsProvider:
            @escaping @Sendable () -> CGRect? = { nil },
        targetFocusHandler:
            @escaping @Sendable () -> Void = {}
    ) {
        self.targetBoundsProvider = targetBoundsProvider
        self.targetFocusHandler = targetFocusHandler
    }

    public func handle(_ event: RemoteInputEvent) -> String {
        guard AXIsProcessTrusted() else {
            return "Accessibility permission required"
        }

        targetFocusHandler()

        lock.lock()
        defer { lock.unlock() }

        switch event {
        case let .pointerDelta(x, y):
            let current = CGEvent(source: nil)?.location ?? .zero
            let destination = CGPoint(
                x: current.x + x,
                y: current.y + y
            )
            postPointer(at: destination)
            return "move \(Int(x)),\(Int(y))"

        case let .pointerAbsolute(x, y):
            let bounds = targetBoundsProvider()
                ?? CGDisplayBounds(CGMainDisplayID())
            let destination =
                PointerCoordinateMapper.absolutePoint(
                    x: x,
                    y: y,
                    in: bounds
            )
            postPointer(at: destination)
            return "absolute \(x),\(y)"

        case let .button(button, isDown, clickCount):
            postButton(
                button: button,
                isDown: isDown,
                clickCount: clickCount
            )
            return "\(button.rawValue) \(isDown ? "down" : "up")"

        case let .scroll(x, y):
            let scroll = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(y.rounded()),
                wheel2: Int32(x.rounded()),
                wheel3: 0
            )
            scroll?.post(tap: .cghidEventTap)
            return "scroll \(Int(x)),\(Int(y))"

        case let .text(value):
            postText(value)
            return "text \(value.count) characters"

        case let .key(code, isDown, modifiers):
            let keyEvent = CGEvent(
                keyboardEventSource: nil,
                virtualKey: CGKeyCode(code),
                keyDown: isDown
            )
            keyEvent?.flags = CGEventFlags(rawValue: modifiers)
            keyEvent?.post(tap: .cghidEventTap)
            return "key \(code) \(isDown ? "down" : "up")"
        }
    }

    private func postPointer(at point: CGPoint) {
        let type: CGEventType
        let button: CGMouseButton
        if leftButtonIsDown {
            type = .leftMouseDragged
            button = .left
        } else if rightButtonIsDown {
            type = .rightMouseDragged
            button = .right
        } else {
            type = .mouseMoved
            button = .left
        }
        CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        )?.post(tap: .cghidEventTap)
    }

    private func postButton(
        button: MouseButton,
        isDown: Bool,
        clickCount: Int
    ) {
        let current = CGEvent(source: nil)?.location ?? .zero
        let eventType: CGEventType
        let mouseButton: CGMouseButton

        switch button {
        case .left:
            leftButtonIsDown = isDown
            eventType = isDown ? .leftMouseDown : .leftMouseUp
            mouseButton = .left
        case .right:
            rightButtonIsDown = isDown
            eventType = isDown ? .rightMouseDown : .rightMouseUp
            mouseButton = .right
        }

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: current,
            mouseButton: mouseButton
        )
        event?.setIntegerValueField(
            .mouseEventClickState,
            value: Int64(clickCount)
        )
        event?.post(tap: .cghidEventTap)
    }

    private func postText(_ text: String) {
        guard !text.isEmpty else {
            return
        }

        var chunk: [UniChar] = []
        for scalar in text.unicodeScalars {
            let scalarUnits = Array(String(scalar).utf16)
            if !chunk.isEmpty && chunk.count + scalarUnits.count > 20 {
                postUTF16Chunk(chunk)
                chunk.removeAll(keepingCapacity: true)
            }
            chunk.append(contentsOf: scalarUnits)
        }
        if !chunk.isEmpty {
            postUTF16Chunk(chunk)
        }
    }

    private func postUTF16Chunk(_ chunk: [UniChar]) {
        let down = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )
        down?.keyboardSetUnicodeString(
            stringLength: chunk.count,
            unicodeString: chunk
        )
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: false
        )
        up?.keyboardSetUnicodeString(
            stringLength: chunk.count,
            unicodeString: chunk
        )
        up?.post(tap: .cghidEventTap)
    }
}
