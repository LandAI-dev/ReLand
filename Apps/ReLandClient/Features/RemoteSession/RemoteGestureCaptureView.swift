import ReLandCore
import SwiftUI
import UIKit

struct RemoteGestureCaptureView: UIViewRepresentable {
    let directTouch: Bool
    let dragEnabled: Bool
    let pointerSensitivity: Double
    let hapticsEnabled: Bool
    let zoomScale: CGFloat
    let viewportOffset: CGSize
    let contentAspectRatio: CGFloat?
    let onZoom: (CGFloat) -> Void
    let onViewportPan: (CGSize) -> Void
    let onPointerPosition: (CGPoint) -> Void
    let onWindowCycle: (CaptureCycleDirection) -> Void
    let send: (RemoteInputEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.singleTap(_:))
        )
        singleTap.numberOfTapsRequired = 1

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.doubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)

        let rightClick = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.rightClick(_:))
        )
        rightClick.numberOfTouchesRequired = 2

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.longPress(_:))
        )
        longPress.minimumPressDuration = 0.55

        let pointerPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.pointerPan(_:))
        )
        pointerPan.minimumNumberOfTouches = 1
        pointerPan.maximumNumberOfTouches = 1

        let scrollPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.scrollPan(_:))
        )
        scrollPan.minimumNumberOfTouches = 2
        scrollPan.maximumNumberOfTouches = 2
        scrollPan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.pinch(_:))
        )
        pinch.delegate = context.coordinator

        let windowCyclePan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.windowCyclePan(_:))
        )
        windowCyclePan.minimumNumberOfTouches = 3
        windowCyclePan.maximumNumberOfTouches = 3
        windowCyclePan.delegate = context.coordinator

        for recognizer in [
            singleTap,
            doubleTap,
            rightClick,
            longPress,
            pointerPan,
            scrollPan,
            pinch,
            windowCyclePan,
        ] {
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        uiView.accessibilityIdentifier = "remoteCanvas"
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: RemoteGestureCaptureView
        private var lastTranslation = CGPoint.zero
        private var isPinching = false
        private var virtualPointer = CGPoint(x: 0.5, y: 0.5)

        init(parent: RemoteGestureCaptureView) {
            self.parent = parent
        }

        @objc
        func singleTap(_ recognizer: UITapGestureRecognizer) {
            if parent.directTouch {
                sendAbsoluteLocation(recognizer.location(in: recognizer.view), in: recognizer.view)
            }
            sendClick(button: .left, count: 1)
        }

        @objc
        func doubleTap(_ recognizer: UITapGestureRecognizer) {
            if parent.directTouch {
                sendAbsoluteLocation(recognizer.location(in: recognizer.view), in: recognizer.view)
            }
            sendClick(button: .left, count: 2)
        }

        @objc
        func rightClick(_: UITapGestureRecognizer) {
            sendClick(button: .right, count: 1)
        }

        @objc
        func longPress(_ recognizer: UILongPressGestureRecognizer) {
            guard
                recognizer.state == .began,
                let view = recognizer.view
            else {
                return
            }
            if parent.directTouch {
                sendAbsoluteLocation(
                    recognizer.location(in: view),
                    in: view
                )
            }
            sendClick(button: .right, count: 1)
        }

        @objc
        func pointerPan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else {
                return
            }

            switch recognizer.state {
            case .began:
                lastTranslation = .zero
                if parent.dragEnabled {
                    parent.send(
                        .button(button: .left, isDown: true, clickCount: 1)
                    )
                }
                if parent.directTouch {
                    sendAbsoluteLocation(
                        recognizer.location(in: view),
                        in: view
                    )
                }

            case .changed:
                if parent.directTouch {
                    sendAbsoluteLocation(
                        recognizer.location(in: view),
                        in: view
                    )
                } else {
                    let translation = recognizer.translation(in: view)
                    let delta = CGPoint(
                        x: translation.x - lastTranslation.x,
                        y: translation.y - lastTranslation.y
                    )
                    lastTranslation = translation
                    let magnitude = hypot(delta.x, delta.y)
                    let acceleration = 1
                        + min(magnitude / 10, 1.2)
                    let scale = parent.pointerSensitivity
                        * Double(acceleration)
                    virtualPointer = CGPoint(
                        x: min(
                            max(
                                virtualPointer.x
                                    + delta.x * CGFloat(scale)
                                    / max(view.bounds.width, 1),
                                0
                            ),
                            1
                        ),
                        y: min(
                            max(
                                virtualPointer.y
                                    + delta.y * CGFloat(scale)
                                    / max(view.bounds.height, 1),
                                0
                            ),
                            1
                        )
                    )
                    parent.onPointerPosition(virtualPointer)
                    parent.send(
                        .pointerDelta(
                            x: Double(delta.x) * scale,
                            y: Double(delta.y) * scale
                        )
                    )
                }

            case .ended, .cancelled, .failed:
                if parent.dragEnabled {
                    parent.send(
                        .button(button: .left, isDown: false, clickCount: 1)
                    )
                }
                lastTranslation = .zero

            default:
                break
            }
        }

        @objc
        func scrollPan(_ recognizer: UIPanGestureRecognizer) {
            guard
                recognizer.state == .changed,
                !isPinching
            else {
                return
            }

            if parent.zoomScale > 1.01 {
                let translation = recognizer.translation(
                    in: recognizer.view
                )
                recognizer.setTranslation(.zero, in: recognizer.view)
                parent.onViewportPan(
                    CGSize(
                        width: translation.x,
                        height: translation.y
                    )
                )
                return
            }

            let velocity = recognizer.velocity(in: recognizer.view)
            parent.send(
                .scroll(
                    x: Double(velocity.x / 30),
                    y: Double(velocity.y / 30)
                )
            )
        }

        @objc
        func pinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                isPinching = true
            case .changed:
                parent.onZoom(recognizer.scale)
                recognizer.scale = 1
            case .ended, .cancelled, .failed:
                isPinching = false
            default:
                break
            }
        }

        @objc
        func windowCyclePan(
            _ recognizer: UIPanGestureRecognizer
        ) {
            guard
                recognizer.state == .ended,
                let view = recognizer.view
            else {
                return
            }
            let translation = recognizer.translation(in: view)
            let velocity = recognizer.velocity(in: view)
            guard
                let direction =
                    CaptureCycleGestureClassifier.direction(
                        translation: CGSize(
                            width: translation.x,
                            height: translation.y
                        ),
                        horizontalVelocity: velocity.x
                    )
            else {
                return
            }
            if parent.hapticsEnabled {
                UIImpactFeedbackGenerator(style: .medium)
                    .impactOccurred()
            }
            parent.onWindowCycle(direction)
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func sendAbsoluteLocation(
            _ location: CGPoint,
            in view: UIView?
        ) {
            guard
                let view,
                view.bounds.width > 0,
                view.bounds.height > 0
            else {
                return
            }

            let center = CGPoint(
                x: view.bounds.midX,
                y: view.bounds.midY
            )
            let untransformed = CGPoint(
                x:
                    (location.x - parent.viewportOffset.width - center.x)
                    / parent.zoomScale
                    + center.x,
                y:
                    (location.y - parent.viewportOffset.height - center.y)
                    / parent.zoomScale
                    + center.y
            )
            let contentFrame = fittedContentFrame(in: view.bounds)
            let normalized = CGPoint(
                x: min(
                    max(
                        (untransformed.x - contentFrame.minX)
                            / contentFrame.width,
                        0
                    ),
                    1
                ),
                y: min(
                    max(
                        (untransformed.y - contentFrame.minY)
                            / contentFrame.height,
                        0
                    ),
                    1
                )
            )
            virtualPointer = normalized
            parent.onPointerPosition(normalized)
            parent.send(
                .pointerAbsolute(
                    x: Double(normalized.x),
                    y: Double(normalized.y)
                )
            )
        }

        private func fittedContentFrame(in bounds: CGRect) -> CGRect {
            guard
                let aspectRatio = parent.contentAspectRatio,
                aspectRatio > 0
            else {
                return bounds
            }
            let containerAspect = bounds.width / bounds.height
            if containerAspect > aspectRatio {
                let width = bounds.height * aspectRatio
                return CGRect(
                    x: bounds.midX - width / 2,
                    y: bounds.minY,
                    width: width,
                    height: bounds.height
                )
            }
            let height = bounds.width / aspectRatio
            return CGRect(
                x: bounds.minX,
                y: bounds.midY - height / 2,
                width: bounds.width,
                height: height
            )
        }

        private func sendClick(button: MouseButton, count: Int) {
            parent.send(
                .button(button: button, isDown: true, clickCount: count)
            )
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(60)
            ) { [parent] in
                parent.send(
                    .button(
                        button: button,
                        isDown: false,
                        clickCount: count
                    )
                )
            }
        }
    }
}
