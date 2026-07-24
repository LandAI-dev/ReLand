import Darwin
import Foundation

enum NetworkAddressResolver {
    static func preferredAddress() -> String {
        let addresses = ipv4Addresses()
        if let tailscale = addresses.first(where: isTailscaleAddress) {
            return tailscale
        }
        if let privateAddress = addresses.first(where: isPrivateAddress) {
            return privateAddress
        }
        return ProcessInfo.processInfo.hostName
    }

    private static func ipv4Addresses() -> [String] {
        var interfacePointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfacePointer) == 0 else {
            return []
        }
        defer { freeifaddrs(interfacePointer) }

        var results: [String] = []
        var cursor = interfacePointer
        while let interface = cursor?.pointee {
            defer { cursor = interface.ifa_next }
            guard
                let address = interface.ifa_addr,
                address.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard name != "lo0" else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if status == 0 {
                let bytes = host.prefix { $0 != 0 }.map {
                    UInt8(bitPattern: $0)
                }
                results.append(String(decoding: bytes, as: UTF8.self))
            }
        }
        return results
    }

    private static func isTailscaleAddress(_ value: String) -> Bool {
        let parts = value.split(separator: ".").compactMap {
            Int($0)
        }
        guard parts.count == 4 else {
            return false
        }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }

    private static func isPrivateAddress(_ value: String) -> Bool {
        let parts = value.split(separator: ".").compactMap {
            Int($0)
        }
        guard parts.count == 4 else {
            return false
        }
        if parts[0] == 10 || parts[0] == 192 && parts[1] == 168 {
            return true
        }
        return parts[0] == 172 && (16...31).contains(parts[1])
    }
}
