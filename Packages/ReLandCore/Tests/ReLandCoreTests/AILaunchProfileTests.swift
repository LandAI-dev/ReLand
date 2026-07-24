import Foundation
import Testing
@testable import ReLandCore

struct AILaunchProfileTests {
    @Test
    func namedProfileRoundTrips() throws {
        let profile = AILaunchProfile(
            id: UUID(
                uuidString:
                    "11111111-2222-3333-4444-555555555555"
            )!,
            name: "Trusted Copilot",
            tool: .copilot,
            additionalArguments: "--model test",
            bypassPermissions: true
        )

        let decoded = try JSONDecoder().decode(
            AILaunchProfile.self,
            from: JSONEncoder().encode(profile)
        )

        #expect(decoded == profile)
        #expect(decoded.isRisky)
    }
}
