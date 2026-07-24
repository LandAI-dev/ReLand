import Foundation
import ReLandCore
import ReLandHostCore

struct HostSharedFolder: Identifiable, Equatable {
    let id: UUID
    let name: String
    let path: String
}

@MainActor
final class HostFileAccessStore {
    private struct Record: Codable {
        let id: UUID
        let bookmark: Data
    }

    private static let defaultsKey =
        "reland.shared-folder-bookmarks"

    private let settings: any SettingsStoring
    private var records: [Record] = []
    private var resolvedURLs: [UUID: URL] = [:]
    private var securityScopedIDs: Set<UUID> = []

    init(
        settings: any SettingsStoring =
            UserDefaultsSettingsStore()
    ) {
        self.settings = settings
        load()
    }

    var folders: [HostSharedFolder] {
        resolvedURLs.map { id, url in
            HostSharedFolder(
                id: id,
                name: url.lastPathComponent,
                path: url.path
            )
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name)
                == .orderedAscending
        }
    }

    func addFolder(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        guard
            !resolvedURLs.values.contains(standardized)
        else {
            return
        }
        let record = Record(
            id: UUID(),
            bookmark: try standardized.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        )
        records.append(record)
        try resolve(record)
        try persist()
    }

    func removeFolder(id: UUID) throws {
        if
            securityScopedIDs.remove(id) != nil,
            let url = resolvedURLs[id]
        {
            url.stopAccessingSecurityScopedResource()
        }
        resolvedURLs.removeValue(forKey: id)
        records.removeAll { $0.id == id }
        try persist()
    }

    func remoteRoots() -> [RemoteFileRoot] {
        resolvedURLs.map { id, url in
            RemoteFileRoot(
                id: "shared-\(id.uuidString.lowercased())",
                name: url.lastPathComponent,
                url: url
            )
        }
    }

    private func load() {
        guard
            let data = settings.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode(
                [Record].self,
                from: data
            )
        else {
            return
        }
        records = decoded
        var validRecords: [Record] = []
        for record in records {
            do {
                try resolve(record)
                validRecords.append(record)
            } catch {
                continue
            }
        }
        records = validRecords
        try? persist()
    }

    private func resolve(_ record: Record) throws {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: record.bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        let standardized = url.standardizedFileURL
        resolvedURLs[record.id] = standardized
        if standardized.startAccessingSecurityScopedResource() {
            securityScopedIDs.insert(record.id)
        }
        if isStale {
            let updated = Record(
                id: record.id,
                bookmark: try standardized.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            )
            if let index = records.firstIndex(where: {
                $0.id == record.id
            }) {
                records[index] = updated
            }
        }
    }

    private func persist() throws {
        settings.set(
            try JSONEncoder().encode(records),
            forKey: Self.defaultsKey
        )
    }
}
