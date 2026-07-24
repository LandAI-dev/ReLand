// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ReLandCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "ReLandCore", targets: ["ReLandCore"]),
        .library(name: "ReLandHostCore", targets: ["ReLandHostCore"]),
    ],
    dependencies: [
        .package(
            path: "../../Vendor/SwiftTerm"
        ),
    ],
    targets: [
        .target(name: "ReLandCore"),
        .target(
            name: "ReLandHostCore",
            dependencies: [
                "ReLandCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .testTarget(
            name: "ReLandCoreTests",
            dependencies: [
                "ReLandCore",
                "ReLandHostCore",
            ]
        ),
    ]
)
