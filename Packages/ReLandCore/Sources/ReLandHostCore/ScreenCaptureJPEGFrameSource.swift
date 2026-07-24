import AppKit
import ApplicationServices
import CoreImage
import CoreMedia
import Foundation
import ImageIO
import ReLandCore
import ScreenCaptureKit
import UniformTypeIdentifiers

public final class ScreenCaptureJPEGFrameSource:
    NSObject,
    RemoteCaptureTargetSource,
    SCStreamOutput,
    SCStreamDelegate,
    @unchecked Sendable
{
    private struct PreparedTarget {
        let info: RemoteCaptureTargetInfo
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
        let windowID: CGWindowID?
        let ownerProcessID: pid_t?
        let inputBounds: CGRect
    }

    private struct WindowMetadata {
        let layer: Int
        let alpha: Double
        let ownerName: String
        let title: String
    }

    public var displayInformation: DisplayInformation {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentDisplayInformation
    }

    private let sampleQueue = DispatchQueue(
        label: "com.landai.reland.screen-capture.samples"
    )
    private let ciContext = CIContext(
        options: [.cacheIntermediates: false]
    )
    private let encodingLock = NSLock()
    private let stateLock = NSLock()
    private var isEncodingFrame = false
    private var stream: SCStream?
    private var frameHandler: (@Sendable (Data) -> Void)?
    private var errorHandler: (@Sendable (Error) -> Void)?
    private var selectedTargetID: String?
    private var selectedWindowID: CGWindowID?
    private var selectedOwnerProcessID: pid_t?
    private var selectedWindowTitle = ""
    private var lastFocusTime: TimeInterval = 0
    private var selectedInputBounds = CGRect.zero
    private var currentDisplayInformation = DisplayInformation(
        width: 1_440,
        height: 900,
        framesPerSecond: 12
    )

    public override init() {
        super.init()
    }

    public func start(
        frameHandler: @escaping @Sendable (Data) -> Void,
        errorHandler: @escaping @Sendable (Error) -> Void
    ) {
        self.frameHandler = frameHandler
        self.errorHandler = errorHandler

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let content = try await shareableContent()
                let target = try prepareSelectedTarget(
                    from: content
                )
                let stream = SCStream(
                    filter: target.filter,
                    configuration: target.configuration,
                    delegate: self
                )
                try stream.addStreamOutput(
                    self,
                    type: .screen,
                    sampleHandlerQueue: sampleQueue
                )
                stateLock.withLock {
                    self.stream = stream
                    applyPreparedState(target)
                }
                try await stream.startCapture()
            } catch {
                errorHandler(error)
            }
        }
    }

    public func stop() {
        stateLock.lock()
        let activeStream = stream
        stream = nil
        stateLock.unlock()
        Task { [weak self] in
            do {
                try await activeStream?.stopCapture()
            } catch {
                self?.errorHandler?(error)
            }
        }
    }

    public func listCaptureTargets(
        completion: @escaping @Sendable (
            Result<
                RemoteCaptureTargetListResponse,
                RemoteCaptureTargetSourceError
            >
        ) -> Void
    ) {
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let content = try await shareableContent()
                let targets = captureTargets(from: content)
                let selected = stateLock.withLock {
                    selectedTargetID
                        ?? targets.first?.id
                        ?? ""
                }
                completion(
                    .success(
                        RemoteCaptureTargetListResponse(
                            targets: targets,
                            selectedTargetID: selected
                        )
                    )
                )
            } catch {
                completion(
                    .failure(.message(error.localizedDescription))
                )
            }
        }
    }

    public func selectCaptureTarget(
        id: String,
        completion: @escaping @Sendable (
            Result<
                RemoteCaptureTargetSelected,
                RemoteCaptureTargetSourceError
            >
        ) -> Void
    ) {
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let content = try await shareableContent()
                let target = try prepareTarget(
                    id: id,
                    from: content
                )
                let activeStream = stateLock.withLock {
                    stream
                }
                if let activeStream {
                    try await activeStream.updateContentFilter(
                        target.filter
                    )
                    try await activeStream.updateConfiguration(
                        target.configuration
                    )
                }
                stateLock.withLock {
                    applyPreparedState(target)
                }
                focus(target: target, movePointer: true)
                try await Task.sleep(
                    for: .milliseconds(350)
                )
                completion(
                    .success(
                        RemoteCaptureTargetSelected(
                            target: target.info,
                            displayInformation:
                                displayInformation
                        )
                    )
                )
            } catch {
                completion(
                    .failure(.message(error.localizedDescription))
                )
            }
        }
    }

    public func currentInputBounds() -> CGRect? {
        stateLock.lock()
        let windowID = selectedWindowID
        let fallback = selectedInputBounds
        stateLock.unlock()
        guard let windowID else {
            return fallback.isEmpty ? nil : fallback
        }
        return Self.windowBounds(windowID: windowID)
            ?? (fallback.isEmpty ? nil : fallback)
    }

    public func focusSelectedTarget() {
        let now = ProcessInfo.processInfo.systemUptime
        let target: (
            windowID: CGWindowID?,
            ownerProcessID: pid_t?,
            title: String,
            fallbackBounds: CGRect
        )? = stateLock.withLock {
            guard now - lastFocusTime >= 0.5 else {
                return nil
            }
            lastFocusTime = now
            return (
                windowID: selectedWindowID,
                ownerProcessID: selectedOwnerProcessID,
                title: selectedWindowTitle,
                fallbackBounds: selectedInputBounds
            )
        }
        guard
            let target,
            let windowID = target.windowID,
            let ownerProcessID = target.ownerProcessID
        else {
            return
        }
        let bounds = Self.windowBounds(windowID: windowID)
            ?? target.fallbackBounds
        Self.focusWindow(
            ownerProcessID: ownerProcessID,
            windowID: windowID,
            title: target.title,
            bounds: bounds
        )
    }

    public func stream(
        _: SCStream,
        didStopWithError error: any Error
    ) {
        errorHandler?(error)
    }

    public func stream(
        _: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard
            outputType == .screen,
            sampleBuffer.isValid,
            let pixelBuffer = sampleBuffer.imageBuffer
        else {
            return
        }

        encodingLock.lock()
        guard !isEncodingFrame else {
            encodingLock.unlock()
            return
        }
        isEncodingFrame = true
        encodingLock.unlock()

        defer {
            encodingLock.lock()
            isEncodingFrame = false
            encodingLock.unlock()
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard
            let cgImage = ciContext.createCGImage(
                image,
                from: image.extent
            ),
            let jpeg = Self.jpegData(from: cgImage)
        else {
            return
        }
        frameHandler?(jpeg)
    }

    private func shareableContent() async throws
        -> SCShareableContent
    {
        try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
    }

    private func prepareSelectedTarget(
        from content: SCShareableContent
    ) throws -> PreparedTarget {
        let selectedID: String? = stateLock.withLock {
            self.selectedTargetID
        }
        if let selectedID,
           let target = try? prepareTarget(
               id: selectedID,
               from: content
           )
        {
            return target
        }
        guard let display = content.displays.first else {
            throw ScreenCaptureError.noDisplay
        }
        return prepareDisplay(display)
    }

    private func prepareTarget(
        id: String,
        from content: SCShareableContent
    ) throws -> PreparedTarget {
        if id.hasPrefix("display-"),
           let display = content.displays.first(where: {
               Self.displayID(for: $0) == id
           })
        {
            return prepareDisplay(display)
        }
        let metadata = Self.windowMetadata()
        if id.hasPrefix("window-"),
           let window = content.windows.first(where: {
               Self.windowID(for: $0) == id
                    && Self.isSelectable(
                        $0,
                        metadata: metadata[$0.windowID]
                    )
           })
        {
            return prepareWindow(window)
        }
        throw ScreenCaptureError.targetUnavailable
    }

    private func prepareDisplay(_ display: SCDisplay)
        -> PreparedTarget
    {
        let size = Self.outputSize(
            width: CGFloat(display.width),
            height: CGFloat(display.height),
            maximumWidth: 1_440,
            maximumHeight: 900
        )
        let configuration = makeConfiguration(
            width: size.width,
            height: size.height,
            showsCursor: true
        )
        return PreparedTarget(
            info: RemoteCaptureTargetInfo(
                id: Self.displayID(for: display),
                kind: .display,
                applicationName: "Mac",
                title: "Entire Display",
                width: size.width,
                height: size.height
            ),
            filter: SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            ),
            configuration: configuration,
            windowID: nil,
            ownerProcessID: nil,
            inputBounds: display.frame
        )
    }

    private func prepareWindow(_ window: SCWindow)
        -> PreparedTarget
    {
        let size = Self.outputSize(
            width: window.frame.width,
            height: window.frame.height,
            maximumWidth: 1_440,
            maximumHeight: 1_000
        )
        let applicationName =
            window.owningApplication?.applicationName
            ?? "Mac App"
        let title = window.title?.isEmpty == false
            ? window.title!
            : applicationName
        return PreparedTarget(
            info: RemoteCaptureTargetInfo(
                id: Self.windowID(for: window),
                kind: .window,
                applicationName: applicationName,
                title: title,
                width: size.width,
                height: size.height
            ),
            filter: SCContentFilter(
                desktopIndependentWindow: window
            ),
            configuration: makeConfiguration(
                width: size.width,
                height: size.height,
                showsCursor: true
            ),
            windowID: window.windowID,
            ownerProcessID:
                window.owningApplication?.processID,
            inputBounds: window.frame
        )
    }

    private func captureTargets(
        from content: SCShareableContent
    ) -> [RemoteCaptureTargetInfo] {
        let metadata = Self.windowMetadata()
        let displays = content.displays.map { display in
            let size = Self.outputSize(
                width: CGFloat(display.width),
                height: CGFloat(display.height),
                maximumWidth: 1_440,
                maximumHeight: 900
            )
            return RemoteCaptureTargetInfo(
                id: Self.displayID(for: display),
                kind: .display,
                applicationName: "Mac",
                title: "Entire Display",
                width: size.width,
                height: size.height
            )
        }
        let windows = content.windows.compactMap {
            window -> RemoteCaptureTargetInfo? in
            guard
                Self.isSelectable(
                    window,
                    metadata: metadata[window.windowID]
                ),
                let application =
                    window.owningApplication,
                application.bundleIdentifier
                    != "com.landai.reland.host"
            else {
                return nil
            }
            let size = Self.outputSize(
                width: window.frame.width,
                height: window.frame.height,
                maximumWidth: 1_440,
                maximumHeight: 1_000
            )
            return RemoteCaptureTargetInfo(
                id: Self.windowID(for: window),
                kind: .window,
                applicationName: application.applicationName,
                title:
                    window.title?.isEmpty == false
                    ? window.title!
                    : application.applicationName,
                width: size.width,
                height: size.height
            )
        }
        .sorted {
            if $0.applicationName != $1.applicationName {
                return $0.applicationName
                    .localizedStandardCompare($1.applicationName)
                    == .orderedAscending
            }
            return $0.title.localizedStandardCompare($1.title)
                == .orderedAscending
        }
        return displays + windows
    }

    private func makeConfiguration(
        width: Int,
        height: Int,
        showsCursor: Bool
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(
                currentDisplayInformation.framesPerSecond
            )
        )
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = showsCursor
        configuration.capturesAudio = false
        return configuration
    }

    private func applyPreparedState(_ target: PreparedTarget) {
        selectedTargetID = target.info.id
        selectedWindowID = target.windowID
        selectedOwnerProcessID = target.ownerProcessID
        selectedWindowTitle = target.info.title
        selectedInputBounds = target.inputBounds
        currentDisplayInformation = DisplayInformation(
            width: target.info.width,
            height: target.info.height,
            framesPerSecond:
                currentDisplayInformation.framesPerSecond
        )
    }

    private func focus(
        target: PreparedTarget,
        movePointer: Bool
    ) {
        guard
            let ownerProcessID = target.ownerProcessID,
            target.windowID != nil
        else {
            return
        }
        Self.focusWindow(
            ownerProcessID: ownerProcessID,
            windowID: target.windowID!,
            title: target.info.title,
            bounds: target.inputBounds
        )
        if movePointer {
            let center = CGPoint(
                x: target.inputBounds.midX,
                y: target.inputBounds.midY
            )
            CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: center,
                mouseButton: .left
            )?.post(tap: .cghidEventTap)
        }
    }

    private static func focusWindow(
        ownerProcessID: pid_t,
        windowID: CGWindowID,
        title: String,
        bounds: CGRect
    ) {
        let application = AXUIElementCreateApplication(
            ownerProcessID
        )
        let activate: @MainActor () -> Void = {
            _ = NSRunningApplication(
                processIdentifier: ownerProcessID
            )?.activate(
                options: [.activateAllWindows]
            )
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                activate()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    activate()
                }
            }
        }
        _ = AXUIElementSetAttributeValue(
            application,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        var value: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(
                application,
                kAXWindowsAttribute as CFString,
                &value
            )
        let windows = value as? [AXUIElement] ?? []
        let window = windows.first(where: {
                matches(
                    element: $0,
                    title: title,
                    bounds: bounds
                )
            })
        if let window {
            _ = AXUIElementSetAttributeValue(
                window,
                kAXMainAttribute as CFString,
                kCFBooleanTrue
            )
            _ = AXUIElementSetAttributeValue(
                window,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            _ = AXUIElementSetAttributeValue(
                application,
                kAXFocusedWindowAttribute as CFString,
                window
            )
            _ = AXUIElementPerformAction(
                window,
                kAXRaiseAction as CFString
            )
        }

        let deadline =
            ProcessInfo.processInfo.systemUptime + 1.2
        while
            (
                NSWorkspace.shared.frontmostApplication?
                    .processIdentifier != ownerProcessID
                || !isWindowOnScreen(windowID: windowID)
            ),
            ProcessInfo.processInfo.systemUptime < deadline
        {
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private static func isWindowOnScreen(
        windowID: CGWindowID
    ) -> Bool {
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionIncludingWindow],
                windowID
            ) as? [[String: Any]],
            let value = windows.first?[
                kCGWindowIsOnscreen as String
            ] as? Bool
        else {
            return false
        }
        return value
    }

    private static func matches(
        element: AXUIElement,
        title: String,
        bounds: CGRect
    ) -> Bool {
        var titleValue: CFTypeRef?
        if
            AXUIElementCopyAttributeValue(
                element,
                kAXTitleAttribute as CFString,
                &titleValue
            ) == .success,
            let candidateTitle = titleValue as? String,
            !title.isEmpty,
            candidateTitle == title
        {
            return true
        }

        guard
            let candidateBounds = accessibilityBounds(
                element: element
            )
        else {
            return false
        }
        return abs(candidateBounds.minX - bounds.minX) < 4
            && abs(candidateBounds.minY - bounds.minY) < 4
            && abs(candidateBounds.width - bounds.width) < 4
            && abs(candidateBounds.height - bounds.height) < 4
    }

    private static func accessibilityBounds(
        element: AXUIElement
    ) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXPositionAttribute as CFString,
                &positionValue
            ) == .success,
            AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &sizeValue
            ) == .success,
            let positionValue,
            let sizeValue,
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let position = positionValue as! AXValue
        let size = sizeValue as! AXValue
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard
            AXValueGetValue(position, .cgPoint, &point),
            AXValueGetValue(size, .cgSize, &dimensions)
        else {
            return nil
        }
        return CGRect(origin: point, size: dimensions)
    }

    private static func outputSize(
        width: CGFloat,
        height: CGFloat,
        maximumWidth: CGFloat,
        maximumHeight: CGFloat
    ) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else {
            return (1, 1)
        }
        let scale = min(
            maximumWidth / width,
            maximumHeight / height
        )
        return (
            max(1, Int((width * scale).rounded())),
            max(1, Int((height * scale).rounded()))
        )
    }

    private static func displayID(for display: SCDisplay) -> String {
        "display-\(display.displayID)"
    }

    private static func windowID(for window: SCWindow) -> String {
        "window-\(window.windowID)"
    }

    private static func isSelectable(
        _ window: SCWindow,
        metadata: WindowMetadata?
    ) -> Bool {
        guard
            window.frame.width >= 160,
            window.frame.height >= 120,
            let application = window.owningApplication,
            application.bundleIdentifier
                != "com.landai.reland.host",
            let metadata,
            metadata.layer == 0,
            metadata.alpha > 0,
            !excludedOwnerNames.contains(metadata.ownerName)
        else {
            return false
        }
        let title = window.title?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? metadata.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return !title.isEmpty
    }

    private static var excludedOwnerNames: Set<String> {
        [
            "AccessibilityVisualsAgent",
            "AutoFill",
            "Control Center",
            "DisplayLink Manager",
            "Dock",
            "Notification Center",
            "Spotlight",
            "TextInputSwitcher",
            "Wallpaper",
            "Window Server",
            "loginwindow",
        ]
    }

    private static func windowMetadata()
        -> [CGWindowID: WindowMetadata]
    {
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionAll],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return [:]
        }
        return Dictionary(
            uniqueKeysWithValues: windows.compactMap { window in
                guard
                    let number = window[
                        kCGWindowNumber as String
                    ] as? NSNumber
                else {
                    return nil
                }
                return (
                    CGWindowID(number.uint32Value),
                    WindowMetadata(
                        layer:
                            window[
                                kCGWindowLayer as String
                            ] as? Int ?? -1,
                        alpha:
                            window[
                                kCGWindowAlpha as String
                            ] as? Double ?? 0,
                        ownerName:
                            window[
                                kCGWindowOwnerName as String
                            ] as? String ?? "",
                        title:
                            window[
                                kCGWindowName as String
                            ] as? String ?? ""
                    )
                )
            }
        )
    }

    private static func windowBounds(
        windowID: CGWindowID
    ) -> CGRect? {
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionIncludingWindow],
                windowID
            ) as? [[String: Any]],
            let bounds = windows.first?[
                kCGWindowBounds as String
            ] as? [String: NSNumber],
            let x = bounds["X"],
            let y = bounds["Y"],
            let width = bounds["Width"],
            let height = bounds["Height"]
        else {
            return nil
        }
        return CGRect(
            x: x.doubleValue,
            y: y.doubleValue,
            width: width.doubleValue,
            height: height.doubleValue
        )
    }

    private static func jpegData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [
                kCGImageDestinationLossyCompressionQuality:
                    0.55,
            ] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}

private enum ScreenCaptureError: LocalizedError {
    case noDisplay
    case targetUnavailable

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            "No display is available to capture."
        case .targetUnavailable:
            "The selected Mac app window is no longer available."
        }
    }
}
