import Foundation

public enum WireMessageKind: UInt8, Codable, Sendable {
    case challenge = 1
    case authenticate = 2
    case pairRequest = 3
    case pairAccepted = 4
    case sessionReady = 5
    case displayInfo = 6
    case videoFrame = 7
    case input = 8
    case inputAcknowledgement = 9
    case ping = 10
    case pong = 11
    case error = 12
    case terminalListRequest = 13
    case terminalListResponse = 14
    case terminalCreateRequest = 15
    case terminalAttachRequest = 16
    case terminalAttached = 17
    case terminalOutput = 18
    case terminalInput = 19
    case terminalResize = 20
    case terminalDetach = 21
    case terminalDetached = 22
    case terminalOpenOnMac = 23
    case terminalKill = 24
    case terminalArtifactListRequest = 25
    case terminalArtifactListResponse = 26
    case terminalArtifactReadRequest = 27
    case terminalArtifactChunk = 28
    case fileListRequest = 29
    case fileListResponse = 30
    case fileReadRequest = 31
    case fileChunk = 32
    case captureTargetListRequest = 33
    case captureTargetListResponse = 34
    case captureTargetSelectRequest = 35
    case captureTargetSelected = 36
    case hostStatusRequest = 37
    case hostStatusResponse = 38
}

public struct WirePacket: Equatable, Sendable {
    public let kind: WireMessageKind
    public let payload: Data

    public init(kind: WireMessageKind, payload: Data = Data()) {
        self.kind = kind
        self.payload = payload
    }
}

public enum WireProtocolError: Error, Equatable {
    case invalidLength
    case packetTooLarge
    case unknownMessageKind(UInt8)
}

public enum WirePacketCodec {
    public static func encode(_ packet: WirePacket) throws -> Data {
        let bodyLength = 1 + packet.payload.count
        guard bodyLength <= ReLandConstants.maximumPacketSize else {
            throw WireProtocolError.packetTooLarge
        }

        var result = Data()
        result.reserveCapacity(4 + bodyLength)
        result.appendUInt32(UInt32(bodyLength))
        result.append(packet.kind.rawValue)
        result.append(packet.payload)
        return result
    }
}

public final class WirePacketStreamDecoder: @unchecked Sendable {
    private var buffer = Data()

    public init() {}

    public func append(_ data: Data) throws -> [WirePacket] {
        buffer.append(data)
        var packets: [WirePacket] = []

        while buffer.count >= 5 {
            guard let bodyLengthValue = buffer.uint32(at: 0) else {
                throw WireProtocolError.invalidLength
            }
            let bodyLength = Int(bodyLengthValue)
            guard bodyLength >= 1 else {
                throw WireProtocolError.invalidLength
            }
            guard bodyLength <= ReLandConstants.maximumPacketSize else {
                throw WireProtocolError.packetTooLarge
            }
            guard buffer.count >= 4 + bodyLength else {
                break
            }

            let kindValue = buffer[4]
            guard let kind = WireMessageKind(rawValue: kindValue) else {
                if kindValue >= 128 {
                    buffer.removeSubrange(0..<(4 + bodyLength))
                    continue
                }
                throw WireProtocolError.unknownMessageKind(kindValue)
            }

            let payloadRange = 5..<(4 + bodyLength)
            packets.append(
                WirePacket(
                    kind: kind,
                    payload: Data(buffer[payloadRange])
                )
            )
            buffer.removeSubrange(0..<(4 + bodyLength))
        }

        return packets
    }

    public func reset() {
        buffer.removeAll(keepingCapacity: false)
    }
}

public enum WireJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    public static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
