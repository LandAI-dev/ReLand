import Foundation
import XCTest
@testable import ReLandCore

final class PersistenceStoreTests: XCTestCase {
    func testUserDefaultsSettingsStoreSupportsTypedValues() throws {
        let suiteName = "ReLandSettings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = UserDefaultsSettingsStore(defaults: defaults)

        store.set(Data("data".utf8), forKey: "data")
        store.set("value", forKey: "string")
        store.set(true, forKey: "bool")
        store.set(2.5, forKey: "double")

        XCTAssertEqual(store.data(forKey: "data"), Data("data".utf8))
        XCTAssertEqual(store.string(forKey: "string"), "value")
        XCTAssertTrue(store.bool(forKey: "bool"))
        XCTAssertEqual(store.double(forKey: "double"), 2.5)

        store.removeObject(forKey: "string")
        XCTAssertNil(store.string(forKey: "string"))
    }

    func testKeychainStoreConformsToCredentialAbstraction() {
        func acceptsCredentialStore(
            _: any CredentialStoring
        ) {}

        acceptsCredentialStore(
            KeychainSecretStore(
                service: "com.landai.reland.tests"
            )
        )
    }
}
