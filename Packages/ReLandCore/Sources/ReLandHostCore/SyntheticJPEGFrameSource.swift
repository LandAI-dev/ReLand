import CoreGraphics
import Foundation
import ImageIO
import ReLandCore
import UniformTypeIdentifiers

public final class SyntheticJPEGFrameSource:
    RemoteCaptureTargetSource,
    @unchecked Sendable
{
    private static let displayTarget = RemoteCaptureTargetInfo(
        id: "display-main",
        kind: .display,
        applicationName: "Mac",
        title: "Entire Display",
        width: 960,
        height: 540
    )
    private static let windowTargets = [
        RemoteCaptureTargetInfo(
            id: "window-notes",
            kind: .window,
            applicationName: "Notes",
            title: "Project Notes",
            width: 720,
            height: 900
        ),
        RemoteCaptureTargetInfo(
            id: "window-dashboard",
            kind: .window,
            applicationName: "Dashboard",
            title: "ReLand Dashboard",
            width: 1_000,
            height: 700
        ),
        RemoteCaptureTargetInfo(
            id: "window-fullscreen",
            kind: .window,
            applicationName: "Google Chrome",
            title: "YouTube — Full Screen",
            width: 1_440,
            height: 900
        ),
    ]

    public var displayInformation: DisplayInformation {
        lock.lock()
        defer { lock.unlock() }
        return currentDisplayInformation
    }

    private let queue = DispatchQueue(
        label: "com.landai.reland.synthetic-frames"
    )
    private let lock = NSLock()
    private var currentDisplayInformation: DisplayInformation
    private var selectedTargetID = "display-main"
    private var timer: DispatchSourceTimer?
    private var frameIndex = 0

    public init(width: Int = 960, height: Int = 540, fps: Int = 10) {
        currentDisplayInformation = DisplayInformation(
            width: width,
            height: height,
            framesPerSecond: fps
        )
    }

    public func start(
        frameHandler: @escaping @Sendable (Data) -> Void,
        errorHandler _: @escaping @Sendable (Error) -> Void
    ) {
        queue.async { [weak self] in
            guard let self, timer == nil else {
                return
            }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now(),
                repeating: 1.0
                    / Double(displayInformation.framesPerSecond),
                leeway: .milliseconds(5)
            )
            timer.setEventHandler { [weak self] in
                guard let self, let frame = makeFrame() else {
                    return
                }
                frameHandler(frame)
            }
            self.timer = timer
            timer.resume()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
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
            lock.lock()
            let selectedTargetID = selectedTargetID
            lock.unlock()
            completion(
                .success(
                    RemoteCaptureTargetListResponse(
                        targets:
                            [Self.displayTarget] + Self.windowTargets,
                        selectedTargetID: selectedTargetID
                    )
                )
            )
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
            guard
                let target = ([Self.displayTarget] + Self.windowTargets)
                    .first(where: { $0.id == id })
            else {
                completion(.failure(.message("Capture target unavailable")))
                return
            }
            lock.lock()
            selectedTargetID = target.id
            currentDisplayInformation = DisplayInformation(
                width: target.width,
                height: target.height,
                framesPerSecond:
                    currentDisplayInformation.framesPerSecond
            )
            let information = currentDisplayInformation
            lock.unlock()
            completion(
                .success(
                    RemoteCaptureTargetSelected(
                        target: target,
                        displayInformation: information
                    )
                )
            )
        }

    public func currentInputBounds() -> CGRect? {
            lock.lock()
            let id = selectedTargetID
            lock.unlock()
            if id == Self.displayTarget.id {
                return CGRect(x: 0, y: 0, width: 960, height: 540)
            }
            guard
                let target = Self.windowTargets.first(where: {
                    $0.id == id
                })
            else {
                return nil
            }
            return CGRect(
                x: 100,
                y: 100,
                width: target.width,
                height: target.height
            )
    }

    public func focusSelectedTarget() {}

    private func makeFrame() -> Data? {
        let information = displayInformation
        let width = information.width
        let height = information.height
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        let phase = CGFloat(frameIndex % 120) / 120
        context.setFillColor(
            red: 0.035 + phase * 0.04,
            green: 0.043 + phase * 0.08,
            blue: 0.063 + phase * 0.10,
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let cardRect = CGRect(
            x: CGFloat(width) * 0.10,
            y: CGFloat(height) * 0.16,
            width: CGFloat(width) * 0.80,
            height: CGFloat(height) * 0.68
        )
        context.setFillColor(
            red: 0.08,
            green: 0.11,
            blue: 0.15,
            alpha: 1
        )
        context.fill(cardRect)

        let markerWidth = CGFloat(width) * 0.12
        let travel = CGFloat(width) * 0.58
        let markerX = CGFloat(width) * 0.15 + travel * phase
        context.setFillColor(
            red: 13 / 255,
            green: 148 / 255,
            blue: 136 / 255,
            alpha: 1
        )
        context.fill(
            CGRect(
                x: markerX,
                y: CGFloat(height) * 0.42,
                width: markerWidth,
                height: markerWidth
            )
        )

        frameIndex += 1
        guard let image = context.makeImage() else {
            return nil
        }
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
                    0.60,
            ] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}
