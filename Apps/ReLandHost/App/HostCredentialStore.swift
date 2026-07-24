import Foundation
import ReLandCore

struct HostTrustedDevice: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let pairedAt: Date
}

struct HostCredentialStore {
    private static let hostIDKey = "reland.host-id"
    private static let devicesKey = "reland.trusted-devices"

    private let settings: any SettingsStoring
    private let credentials: any CredentialStoring

    init(
        settings: any SettingsStoring =
            UserDefaultsSettingsStore(),
        credentials: any CredentialStoring =
            KeychainSecretStore(
                service:
                    "com.landai.reland.host-device-credentials"
            )
    ) {
        self.settings = settings
        self.credentials = credentials
    }

    func loadOrCreateHostID() -> String {
        if let value = settings.string(forKey: Self.hostIDKey) {
            return value
        }
        let value = UUID().uuidString.lowercased()
        settings.set(value, forKey: Self.hostIDKey)
        return value
    }

    func loadDevices() -> [HostTrustedDevice] {
        guard let data = settings.data(forKey: Self.devicesKey) else {
            return []
        }
        return (
            try? JSONDecoder().decode(
                [HostTrustedDevice].self,
                from: data
            )
        ) ?? []
    }

    func loadCredentials() -> [PSKCredential] {
        loadDevices().compactMap { device in
            guard
                let key = try? credentials.data(for: device.id)
            else {
                return nil
            }
            return try? PSKCredential(
                id: device.id,
                key: key,
                name: device.name
            )
        }
    }

    func save(_ credential: PSKCredential) throws {
        try credentials.set(credential.key, for: credential.id)
        var devices = loadDevices()
        devices.removeAll { $0.id == credential.id }
        devices.append(
            HostTrustedDevice(
                id: credential.id,
                name: credential.name,
                pairedAt: Date()
            )
        )
        try save(devices)
    }

    func remove(_ device: HostTrustedDevice) throws {
        try credentials.remove(account: device.id)
        try save(loadDevices().filter { $0.id != device.id })
    }

    private func save(_ devices: [HostTrustedDevice]) throws {
        settings.set(
            try JSONEncoder().encode(devices),
            forKey: Self.devicesKey
        )
    }
}
