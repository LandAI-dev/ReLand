import Foundation
import ReLandCore

struct TerminalArtifactPreview: Identifiable {
    let info: TerminalArtifactInfo
    let fileURL: URL

    var id: String {
        info.id
    }
}
