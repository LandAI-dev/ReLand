import Foundation
import Network

public final class FramedConnection: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case setup
        case preparing
        case ready
        case waiting(String)
        case failed(String)
        case cancelled
    }

    public var onStateChange: (@Sendable (State) -> Void)?
    public var onPacket: (@Sendable (WirePacket) -> Void)?

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let decoder = WirePacketStreamDecoder()
    private let sendLock = NSLock()
    private var isCancelled = false

    public init(
        connection: NWConnection,
        queue: DispatchQueue = DispatchQueue(
            label: "com.landai.reland.connection"
        )
    ) {
        self.connection = connection
        self.queue = queue
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else {
                return
            }
            switch state {
            case .setup:
                onStateChange?(.setup)
            case .preparing:
                onStateChange?(.preparing)
            case .ready:
                onStateChange?(.ready)
                receiveNextChunk()
            case let .waiting(error):
                onStateChange?(.waiting(error.localizedDescription))
            case let .failed(error):
                onStateChange?(.failed(error.localizedDescription))
            case .cancelled:
                onStateChange?(.cancelled)
            @unknown default:
                onStateChange?(.failed("Unknown connection state"))
            }
        }
        connection.start(queue: queue)
    }

    public func send(
        _ packet: WirePacket,
        completion: (@Sendable (Error?) -> Void)? = nil
    ) {
        do {
            let data = try WirePacketCodec.encode(packet)
            sendLock.lock()
            let cancelled = isCancelled
            sendLock.unlock()
            guard !cancelled else {
                completion?(NWError.posix(.ECANCELED))
                return
            }
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    completion?(error)
                }
            )
        } catch {
            completion?(error)
        }
    }

    public func cancel() {
        sendLock.lock()
        isCancelled = true
        sendLock.unlock()
        connection.cancel()
    }

    private func receiveNextChunk() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1_024
        ) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            if let data, !data.isEmpty {
                do {
                    for packet in try decoder.append(data) {
                        onPacket?(packet)
                    }
                } catch {
                    onStateChange?(.failed(error.localizedDescription))
                    cancel()
                    return
                }
            }

            if let error {
                onStateChange?(.failed(error.localizedDescription))
                return
            }

            if isComplete {
                onStateChange?(.cancelled)
                return
            }

            receiveNextChunk()
        }
    }
}

