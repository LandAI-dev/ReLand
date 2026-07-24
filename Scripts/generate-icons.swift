#!/usr/bin/env swift

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(
    fileURLWithPath: FileManager.default.currentDirectoryPath
)
let client = root.appendingPathComponent(
    "Apps/ReLandClient/Resources/Assets.xcassets/AppIcon.appiconset"
)
let host = root.appendingPathComponent(
    "Apps/ReLandHost/Resources/Assets.xcassets/AppIcon.appiconset"
)

let clientSizes = [
    20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024,
]
let hostSizes = [16, 32, 64, 128, 256, 512, 1024]

func scaled(_ value: CGFloat, for size: Int) -> CGFloat {
    value * CGFloat(size) / 1_024
}

func render(size: Int, to url: URL) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = size * 4
    var pixels = [UInt8](
        repeating: 0,
        count: bytesPerRow * size
    )
    guard
        let cgContext = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo:
                CGImageAlphaInfo.noneSkipLast.rawValue
        )
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    let context = NSGraphicsContext(
        cgContext: cgContext,
        flipped: false
    )

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer {
        NSGraphicsContext.restoreGraphicsState()
    }

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSGradient(
        starting: NSColor(
            red: 15 / 255,
            green: 23 / 255,
            blue: 42 / 255,
            alpha: 1
        ),
        ending: NSColor(
            red: 7 / 255,
            green: 89 / 255,
            blue: 133 / 255,
            alpha: 1
        )
    )?.draw(in: canvas, angle: -45)

    let portal = NSBezierPath(
        roundedRect: NSRect(
            x: scaled(218, for: size),
            y: scaled(178, for: size),
            width: scaled(588, for: size),
            height: scaled(666, for: size)
        ),
        xRadius: scaled(142, for: size),
        yRadius: scaled(142, for: size)
    )
    NSGradient(
        starting: NSColor(
            red: 94 / 255,
            green: 234 / 255,
            blue: 212 / 255,
            alpha: 1
        ),
        ending: NSColor(
            red: 8 / 255,
            green: 145 / 255,
            blue: 178 / 255,
            alpha: 1
        )
    )?.draw(in: portal, angle: -90)

    NSColor(
        red: 11 / 255,
        green: 19 / 255,
        blue: 36 / 255,
        alpha: 1
    ).setFill()
    NSBezierPath(
        roundedRect: NSRect(
            x: scaled(304, for: size),
            y: scaled(270, for: size),
            width: scaled(416, for: size),
            height: scaled(482, for: size)
        ),
        xRadius: scaled(82, for: size),
        yRadius: scaled(82, for: size)
    ).fill()

    let returnPath = NSBezierPath()
    returnPath.move(
        to: NSPoint(
            x: scaled(780, for: size),
            y: scaled(620, for: size)
        )
    )
    returnPath.curve(
        to: NSPoint(
            x: scaled(438, for: size),
            y: scaled(826, for: size)
        ),
        controlPoint1: NSPoint(
            x: scaled(800, for: size),
            y: scaled(830, for: size)
        ),
        controlPoint2: NSPoint(
            x: scaled(620, for: size),
            y: scaled(914, for: size)
        )
    )
    returnPath.curve(
        to: NSPoint(
            x: scaled(414, for: size),
            y: scaled(552, for: size)
        ),
        controlPoint1: NSPoint(
            x: scaled(302, for: size),
            y: scaled(760, for: size)
        ),
        controlPoint2: NSPoint(
            x: scaled(286, for: size),
            y: scaled(630, for: size)
        )
    )
    returnPath.lineWidth = max(scaled(66, for: size), 1)
    returnPath.lineCapStyle = .round
    NSColor(
        red: 248 / 255,
        green: 250 / 255,
        blue: 252 / 255,
        alpha: 1
    ).setStroke()
    returnPath.stroke()

    let arrow = NSBezierPath()
    arrow.move(
        to: NSPoint(
            x: scaled(394, for: size),
            y: scaled(492, for: size)
        )
    )
    arrow.line(
        to: NSPoint(
            x: scaled(532, for: size),
            y: scaled(526, for: size)
        )
    )
    arrow.line(
        to: NSPoint(
            x: scaled(438, for: size),
            y: scaled(634, for: size)
        )
    )
    arrow.close()
    NSColor(
        red: 248 / 255,
        green: 250 / 255,
        blue: 252 / 255,
        alpha: 1
    ).setFill()
    arrow.fill()

    NSColor(
        red: 94 / 255,
        green: 234 / 255,
        blue: 212 / 255,
        alpha: 0.9
    ).setFill()
    NSBezierPath(
        ovalIn: NSRect(
            x: scaled(641, for: size),
            y: scaled(316, for: size),
            width: scaled(68, for: size),
            height: scaled(68, for: size)
        )
    ).fill()

    guard
        let image = cgContext.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

for (directory, sizes) in [
    (client, clientSizes),
    (host, hostSizes),
] {
    for size in sizes {
        try render(
            size: size,
            to: directory.appendingPathComponent(
                "Icon-\(size).png"
            )
        )
    }
}

print("Generated ReLand icon assets.")
