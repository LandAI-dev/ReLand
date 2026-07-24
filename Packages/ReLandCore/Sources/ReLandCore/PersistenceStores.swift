import Foundation

public protocol SettingsStoring {
    func data(forKey key: String) -> Data?
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func double(forKey key: String) -> Double
    func set(_ value: Data?, forKey key: String)
    func set(_ value: String?, forKey key: String)
    func set(_ value: Bool, forKey key: String)
    func set(_ value: Double, forKey key: String)
    func removeObject(forKey key: String)
}

public struct UserDefaultsSettingsStore: SettingsStoring {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func bool(forKey key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    public func double(forKey key: String) -> Double {
        defaults.double(forKey: key)
    }

    public func set(_ value: Data?, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func set(_ value: String?, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func set(_ value: Double, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

public protocol CredentialStoring {
    func data(for account: String) throws -> Data?
    func set(_ data: Data, for account: String) throws
    func remove(account: String) throws
}

extension KeychainSecretStore: CredentialStoring {}
