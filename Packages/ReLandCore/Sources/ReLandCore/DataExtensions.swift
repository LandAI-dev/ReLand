import Foundation
import Security

public extension Data {
    static func secureRandom(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw ReLandSecurityError.randomGenerationFailed(status)
        }
        return Data(bytes)
    }

    var base64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLString: String) {
        var value = base64URLString
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder != 0 {
            value.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: value)
    }
}

extension Data {
    mutating func appendUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    func uint32(at offset: Int) -> UInt32? {
        guard count >= offset + MemoryLayout<UInt32>.size else {
            return nil
        }
        return withUnsafeBytes { bytes in
            let value = bytes.loadUnaligned(
                fromByteOffset: offset,
                as: UInt32.self
            )
            return UInt32(bigEndian: value)
        }
    }
}

