import Foundation
import ReLandCore

struct RemoteFilePreview: Identifiable {
    let entry: RemoteFileEntry
    let fileURL: URL

    var id: String {
        entry.id
    }
}
