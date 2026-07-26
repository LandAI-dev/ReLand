import Foundation

public enum ReLandConstants {
    public static let serviceType = "_reland._tcp"
    public static let defaultPort: UInt16 = 45_454
    public static let maximumPacketSize = 8 * 1_024 * 1_024
    public static let artifactChunkSize = 256 * 1_024
    public static let maximumArtifactSize: Int64 =
        512 * 1_024 * 1_024
    public static let maximumTerminalNameLength = 64
    public static let minimumTerminalCreationCorrelationProtocolVersion:
        UInt16 = 8
    public static let minimumTerminalRenameProtocolVersion: UInt16 = 8
    public static let minimumSupportedProtocolVersion: UInt16 = 7
    public static let maximumSupportedProtocolVersion: UInt16 = 8
    public static let protocolVersion: UInt16 = 8
}
