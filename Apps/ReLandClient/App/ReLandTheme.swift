import SwiftUI
import UIKit

enum ReLandTheme {
    static let accent = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(
                    red: 67 / 255,
                    green: 226 / 255,
                    blue: 207 / 255,
                    alpha: 1
                )
                : UIColor(
                    red: 0 / 255,
                    green: 103 / 255,
                    blue: 92 / 255,
                    alpha: 1
                )
        }
    )
    static let controlBackground = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(
                    red: 24 / 255,
                    green: 55 / 255,
                    blue: 52 / 255,
                    alpha: 1
                )
                : UIColor(
                    red: 224 / 255,
                    green: 242 / 255,
                    blue: 239 / 255,
                    alpha: 1
                )
        }
    )
    static let chromeBackground = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(
                    red: 17 / 255,
                    green: 24 / 255,
                    blue: 39 / 255,
                    alpha: 1
                )
                : UIColor(
                    red: 248 / 255,
                    green: 250 / 255,
                    blue: 252 / 255,
                    alpha: 1
                )
        }
    )
    static let strongText = Color(
        uiColor: .label
    )
    static let canvas = Color(
        uiColor: .systemGroupedBackground
    )
    static let surface = Color(
        uiColor: .secondarySystemGroupedBackground
    )
    static let mutedText = Color(
        uiColor: .secondaryLabel
    )
    static let terminalOverlay = Color.black.opacity(0.88)
    static let remoteCanvas = Color(
        red: 9 / 255,
        green: 11 / 255,
        blue: 16 / 255
    )
}
