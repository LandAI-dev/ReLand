@preconcurrency import SwiftTerm
import SwiftUI
import UIKit

struct TerminalViewportState: Equatable {
    static let initial = TerminalViewportState(
        horizontalProgress: 0,
        verticalProgress: 1,
        canScrollHorizontally: false,
        canScrollVertically: false,
        isAtBottom: true,
        usesAlternateBuffer: false
    )

    let horizontalProgress: Double
    let verticalProgress: Double
    let canScrollHorizontally: Bool
    let canScrollVertically: Bool
    let isAtBottom: Bool
    let usesAlternateBuffer: Bool
}

@MainActor
final class RemoteTerminalController {
    private weak var terminal: ReLandTerminalView?

    func attach(_ terminal: ReLandTerminalView) {
        self.terminal = terminal
    }

    func detach(_ terminal: ReLandTerminalView) {
        if self.terminal === terminal {
            self.terminal = nil
        }
    }

    func toggleKeyboard() {
        guard let terminal else {
            return
        }
        if terminal.isFirstResponder {
            _ = terminal.resignFirstResponder()
        } else {
            _ = terminal.becomeFirstResponder()
        }
    }

    func pageUp() {
        terminal?.pageUp()
    }

    func pageDown() {
        terminal?.pageDown()
    }

    func scrollToLiveEdge() {
        terminal?.scrollTo(row: .max)
    }

    func scrollViewportLeft() {
        terminal?.scrollHorizontally(pageDirection: -1)
    }

    func scrollViewportRight() {
        terminal?.scrollHorizontally(pageDirection: 1)
    }
}

struct RemoteTerminalView: UIViewRepresentable {
    @Bindable var model: ClientAppModel
    let minimumColumns: Int
    let allowsMouseReporting: Bool
    let controller: RemoteTerminalController
    let onViewportChange: (TerminalViewportState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            model: model,
            allowsMouseReporting: allowsMouseReporting,
            onViewportChange: onViewportChange
        )
    }

    func makeUIView(context: Context) -> ReLandTerminalView {
        let terminal = ReLandTerminalView(frame: .zero)
        terminal.terminalDelegate = context.coordinator
        terminal.backgroundColor = .black
        terminal.nativeBackgroundColor = .black
        terminal.nativeForegroundColor = .white
        terminal.font = UIFont.monospacedSystemFont(
            ofSize: 13,
            weight: .regular
        )
        terminal.minimumColumnCount = minimumColumns
        terminal.allowMouseReporting = allowsMouseReporting
        terminal.contentInsetAdjustmentBehavior = .never
        terminal.keyboardDismissMode = .interactive
        terminal.isDirectionalLockEnabled = true
        terminal.alwaysBounceVertical = true
        terminal.alwaysBounceHorizontal = minimumColumns > 0
        terminal.showsVerticalScrollIndicator = true
        terminal.showsHorizontalScrollIndicator = true
        terminal.indicatorStyle = .white
        terminal.inputAccessoryView = nil
        terminal.isAccessibilityElement = !model.isE2EMode
        terminal.accessibilityElementsHidden = model.isE2EMode
        if model.isE2EMode {
            terminal.getTerminal().setCursorStyle(.steadyBlock)
        }
        if !model.isE2EMode {
            terminal.accessibilityIdentifier = "terminalView"
            terminal.accessibilityLabel = "Remote terminal"
            terminal.accessibilityHint = accessibilityHint
        }
        terminal.onViewportChange = { [weak coordinator = context.coordinator] state in
            coordinator?.report(state)
        }
        terminal.panGestureRecognizer.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleTerminalPan(_:))
        )

        context.coordinator.terminal = terminal
        context.coordinator.controller = controller
        controller.attach(terminal)
        model.setTerminalOutputConsumer { [weak terminal] data in
            let bytes = [UInt8](data)
            terminal?.feed(byteArray: bytes[...])
        }
        return terminal
    }

    func updateUIView(
        _ terminal: ReLandTerminalView,
        context: Context
    ) {
        context.coordinator.model = model
        context.coordinator.allowsMouseReporting = allowsMouseReporting
        context.coordinator.onViewportChange = onViewportChange
        context.coordinator.controller = controller
        terminal.minimumColumnCount = minimumColumns
        terminal.allowMouseReporting = allowsMouseReporting
        terminal.alwaysBounceHorizontal = minimumColumns > 0
        if !model.isE2EMode {
            terminal.accessibilityHint = accessibilityHint
        }
        terminal.reportViewport()
    }

    static func dismantleUIView(
        _ terminal: ReLandTerminalView,
        coordinator: Coordinator
    ) {
        terminal.panGestureRecognizer.removeTarget(
            coordinator,
            action: #selector(Coordinator.handleTerminalPan(_:))
        )
        coordinator.controller?.detach(terminal)
        _ = terminal.resignFirstResponder()
        coordinator.model.setTerminalOutputConsumer(nil)
        coordinator.terminal = nil
    }

    private var accessibilityHint: String {
        if allowsMouseReporting {
            "Touches control mouse-aware terminal apps. Switch to Browse mode to scroll."
        } else if minimumColumns > 0 {
            "Swipe vertically for history and horizontally across wide output."
        } else {
            "Swipe vertically for terminal history."
        }
    }

    @MainActor
    final class Coordinator:
        NSObject,
        @preconcurrency TerminalViewDelegate
    {
        var model: ClientAppModel
        var allowsMouseReporting: Bool
        var onViewportChange: (TerminalViewportState) -> Void
        weak var terminal: ReLandTerminalView?
        weak var controller: RemoteTerminalController?

        private var lastViewportState: TerminalViewportState?

        init(
            model: ClientAppModel,
            allowsMouseReporting: Bool,
            onViewportChange: @escaping (TerminalViewportState) -> Void
        ) {
            self.model = model
            self.allowsMouseReporting = allowsMouseReporting
            self.onViewportChange = onViewportChange
        }

        func report(_ state: TerminalViewportState) {
            guard state != lastViewportState else {
                return
            }
            lastViewportState = state
            DispatchQueue.main.async { [weak self] in
                self?.onViewportChange(state)
            }
        }

        @objc
        func handleTerminalPan(_ recognizer: UIPanGestureRecognizer) {
            guard
                recognizer.state == .ended,
                !allowsMouseReporting,
                let terminal,
                terminal.getTerminal().isCurrentBufferAlternate
            else {
                return
            }

            let translation = recognizer.translation(in: terminal)
            guard
                abs(translation.y) >= 48,
                abs(translation.y) > abs(translation.x) * 1.2
            else {
                return
            }

            if translation.y > 0 {
                terminal.pageUp()
            } else {
                terminal.pageDown()
            }
        }

        func send(
            source _: TerminalView,
            data: ArraySlice<UInt8>
        ) {
            model.sendTerminalInput(Data(data))
        }

        func sizeChanged(
            source _: TerminalView,
            newCols: Int,
            newRows: Int
        ) {
            model.resizeTerminal(
                columns: newCols,
                rows: newRows
            )
        }

        func setTerminalTitle(
            source _: TerminalView,
            title _: String
        ) {}

        func hostCurrentDirectoryUpdate(
            source _: TerminalView,
            directory _: String?
        ) {}

        func scrolled(
            source: TerminalView,
            position _: Double
        ) {
            (source as? ReLandTerminalView)?.reportViewport()
        }

        func requestOpenLink(
            source _: TerminalView,
            link: String,
            params _: [String: String]
        ) {
            model.requestOpenTerminalLink(link)
        }

        func bell(source _: TerminalView) {}

        func clipboardCopy(
            source _: TerminalView,
            content: Data
        ) {
            model.handleTerminalClipboardCopy(content)
        }

        func clipboardRead(source _: TerminalView) -> Data? {
            nil
        }

        func iTermContent(
            source _: TerminalView,
            content _: ArraySlice<UInt8>
        ) {}

        func rangeChanged(
            source _: TerminalView,
            startY _: Int,
            endY _: Int
        ) {}
    }
}

@MainActor
final class ReLandTerminalView: TerminalView {
    var onViewportChange: ((TerminalViewportState) -> Void)?

    private var lastReportedState: TerminalViewportState?

    override var contentOffset: CGPoint {
        didSet {
            reportViewport()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportViewport()
    }

    func scrollHorizontally(pageDirection: Int) {
        let maximumX = max(
            0,
            contentSize.width - bounds.width + adjustedContentInset.right
        )
        guard maximumX > 1 else {
            return
        }
        let pageWidth = max(bounds.width * 0.72, 44)
        let targetX = min(
            max(
                contentOffset.x
                    + CGFloat(pageDirection) * pageWidth,
                0
            ),
            maximumX
        )
        setContentOffset(
            CGPoint(x: targetX, y: contentOffset.y),
            animated: false
        )
        reportViewport()
    }

    func reportViewport() {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let maximumX = max(
            0,
            contentSize.width - bounds.width + adjustedContentInset.right
        )
        let maximumY = max(
            0,
            contentSize.height - bounds.height + adjustedContentInset.bottom
        )
        let horizontalOffset = min(max(contentOffset.x, 0), maximumX)
        let verticalOffset = min(max(contentOffset.y, 0), maximumY)
        let state = TerminalViewportState(
            horizontalProgress: maximumX > 1
                ? quantizedProgress(horizontalOffset / maximumX)
                : 0,
            verticalProgress: maximumY > 1
                ? quantizedProgress(verticalOffset / maximumY)
                : 1,
            canScrollHorizontally: maximumX > 1,
            canScrollVertically: canScroll,
            isAtBottom: !canScroll || verticalOffset >= maximumY - 1,
            usesAlternateBuffer: getTerminal().isCurrentBufferAlternate
        )

        guard state != lastReportedState else {
            return
        }
        lastReportedState = state
        let horizontalPercent = Int(state.horizontalProgress * 100)
        let verticalPercent = Int(state.verticalProgress * 100)
        accessibilityValue =
            "horizontal \(horizontalPercent) percent, "
            + "vertical \(verticalPercent) percent"
        onViewportChange?(state)
    }

    private func quantizedProgress(_ value: CGFloat) -> Double {
        (Double(value) * 100).rounded() / 100
    }
}
