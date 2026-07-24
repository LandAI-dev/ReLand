import Foundation
import Testing
@testable import ReLandCore

struct SecurityTests {
    @Test
    func usesReLandBonjourService() {
        #expect(ReLandConstants.serviceType == "_reland._tcp")
    }

    @Test
    func pairingPayloadRoundTripsBeforeExpiry() throws {
        let credential = try PSKCredential.generate(
            name: "Pairing",
            isPairingCredential: true
        )
        let expiresAt = Date(timeIntervalSince1970: 2_000_000_000)
        let descriptor = PairingDescriptor(
            hostID: "host-1",
            hostName: "Percy's MacBook",
            address: "100.100.10.20",
            port: 45_454,
            credential: credential,
            expiresAt: expiresAt
        )

        let payload = try descriptor.encodedPayload()
        let decoded = try PairingDescriptor(
            payload: payload,
            now: expiresAt.addingTimeInterval(-1)
        )

        #expect(payload.hasPrefix("reland-pair:v2:"))
        #expect(!payload.contains("key="))
        #expect(decoded == descriptor)
    }

    @Test
    func pairingPayloadRejectsExpiredCode() throws {
        let expiresAt = Date(timeIntervalSince1970: 2_000_000_000)
        let descriptor = PairingDescriptor(
            hostID: "host-1",
            hostName: "Mac",
            address: "192.168.1.20",
            port: 45_454,
            credential: try PSKCredential.generate(
                name: "Pairing",
                isPairingCredential: true
            ),
            expiresAt: expiresAt
        )

        let payload = try descriptor.encodedPayload()

        #expect(throws: ReLandSecurityError.expiredPairingCode) {
            _ = try PairingDescriptor(
                payload: payload,
                now: expiresAt
            )
        }
    }

    @Test
    func pairingPayloadRejectsLegacyURL() {
        let legacy =
            "reland://pair?address=192.168.1.20&key=secret"

        #expect(throws: ReLandSecurityError.invalidPairingPayload) {
            _ = try PairingDescriptor(payload: legacy)
        }
    }

    @Test
    func pairingPayloadRejectsPublicAddress() throws {
        let expiresAt = Date(timeIntervalSince1970: 2_000_000_000)
        let descriptor = PairingDescriptor(
            hostID: "host-1",
            hostName: "Mac",
            address: "203.0.113.10",
            port: 45_454,
            credential: try PSKCredential.generate(
                name: "Pairing",
                isPairingCredential: true
            ),
            expiresAt: expiresAt
        )

        let payload = try descriptor.encodedPayload()

        #expect(throws: ReLandSecurityError.untrustedNetworkAddress) {
            _ = try PairingDescriptor(
                payload: payload,
                now: expiresAt.addingTimeInterval(-1)
            )
        }
    }

    @Test
    func authenticationRejectsWrongChallenge() throws {
        let credential = try PSKCredential.generate(name: "Phone")
        let challenge = try Data.secureRandom(count: 32)
        let otherChallenge = try Data.secureRandom(count: 32)
        let code = credential.authenticationCode(for: challenge)

        #expect(credential.validates(code: code, challenge: challenge))
        #expect(!credential.validates(code: code, challenge: otherChallenge))
    }

    @Test
    func privateNetworkPolicyRejectsPublicAddresses() {
        #expect(PrivateNetworkPolicy.allows("127.0.0.1"))
        #expect(PrivateNetworkPolicy.allows("10.1.2.3"))
        #expect(PrivateNetworkPolicy.allows("172.16.4.5"))
        #expect(PrivateNetworkPolicy.allows("192.168.10.20"))
        #expect(PrivateNetworkPolicy.allows("100.100.10.20"))
        #expect(PrivateNetworkPolicy.allows("169.254.10.20"))
        #expect(PrivateNetworkPolicy.allows("fd7a:115c:a1e0::1"))
        #expect(PrivateNetworkPolicy.allows("fe80::1"))
        #expect(!PrivateNetworkPolicy.allows("8.8.8.8"))
        #expect(!PrivateNetworkPolicy.allows("0.0.0.0"))
        #expect(!PrivateNetworkPolicy.allows("203.0.113.10"))
        #expect(!PrivateNetworkPolicy.allows("fd-evil.example.com"))
        #expect(!PrivateNetworkPolicy.allows("fc.example.com"))
        #expect(!PrivateNetworkPolicy.allows("fd-not-an-ipv6-address"))
        #expect(!PrivateNetworkPolicy.allows("remote.example.com"))
    }

    @Test
    func secureTerminalPolicyBlocksClipboardByDefault() {
        let policy = TerminalContentPolicy.secureDefault

        #expect(policy.clipboardText(from: Data("secret".utf8)) == nil)
    }

    @Test
    func terminalClipboardOptInEnforcesEncodingAndSize() {
        let policy = TerminalContentPolicy(
            allowsClipboardWrites: true,
            maximumClipboardBytes: 4
        )

        #expect(
            policy.clipboardText(from: Data("test".utf8))
                == "test"
        )
        #expect(
            policy.clipboardText(from: Data("large".utf8))
                == nil
        )
        #expect(
            policy.clipboardText(from: Data([0xFF]))
                == nil
        )
    }

    @Test
    func terminalLinksAllowOnlyWebSchemes() {
        let policy = TerminalContentPolicy.secureDefault

        #expect(
            policy.externalURL(from: "https://example.com")?.scheme
                == "https"
        )
        #expect(
            policy.externalURL(from: "http://example.com")?.scheme
                == "http"
        )
        #expect(policy.externalURL(from: "file:///etc/passwd") == nil)
        #expect(policy.externalURL(from: "javascript:alert(1)") == nil)
        #expect(policy.externalURL(from: "data:text/plain,secret") == nil)
        #expect(policy.externalURL(from: "reland://pair") == nil)
    }
}
