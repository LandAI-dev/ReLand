import Foundation

public struct TerminalContentPolicy: Sendable {
    public static let secureDefault = TerminalContentPolicy(
        allowsClipboardWrites: false
    )

    public let allowsClipboardWrites: Bool
    public let maximumClipboardBytes: Int
    public let allowedExternalSchemes: Set<String>

    public init(
        allowsClipboardWrites: Bool,
        maximumClipboardBytes: Int = 4_096,
        allowedExternalSchemes: Set<String> = ["http", "https"]
    ) {
        self.allowsClipboardWrites = allowsClipboardWrites
        self.maximumClipboardBytes = max(0, maximumClipboardBytes)
        self.allowedExternalSchemes = Set(
            allowedExternalSchemes.map { $0.lowercased() }
        )
    }

    public func clipboardText(from content: Data) -> String? {
        guard
            allowsClipboardWrites,
            content.count <= maximumClipboardBytes
        else {
            return nil
        }
        return String(data: content, encoding: .utf8)
    }

    public func externalURL(from value: String) -> URL? {
        guard
            let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            allowedExternalSchemes.contains(scheme),
            url.host != nil
        else {
            return nil
        }
        return url
    }
}
