import Darwin
import Foundation

public enum PrivateNetworkPolicy {
    public static func allows(_ rawAddress: String) -> Bool {
        let address = rawAddress
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        if allowsIPv6(address) {
            return true
        }

        let ipv4 = address.split(separator: ".").compactMap {
            Int(String($0))
        }
        guard ipv4.count == 4, ipv4.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }

        if ipv4[0] == 127 || ipv4[0] == 10 {
            return true
        }
        if ipv4[0] == 169 && ipv4[1] == 254 {
            return true
        }
        if ipv4[0] == 192 && ipv4[1] == 168 {
            return true
        }
        if ipv4[0] == 172 && (16...31).contains(ipv4[1]) {
            return true
        }
        return ipv4[0] == 100 && (64...127).contains(ipv4[1])
    }

    private static func allowsIPv6(_ address: String) -> Bool {
        let addressWithoutZone = String(
            address.split(
                separator: "%",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )[0]
        )
        var parsed = in6_addr()
        let result = addressWithoutZone.withCString {
            inet_pton(AF_INET6, $0, &parsed)
        }
        guard result == 1 else {
            return false
        }

        return withUnsafeBytes(of: &parsed) { bytes in
            let octets = Array(bytes)
            let isLoopback =
                octets.dropLast().allSatisfy { $0 == 0 }
                && octets.last == 1
            let isUniqueLocal = octets[0] & 0xFE == 0xFC
            let isLinkLocal =
                octets[0] == 0xFE
                && octets[1] & 0xC0 == 0x80
            return isLoopback || isUniqueLocal || isLinkLocal
        }
    }
}
