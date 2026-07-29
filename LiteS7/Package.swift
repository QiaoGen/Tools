// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LiteS7",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LiteS7", targets: ["LiteS7"])
    ],
    targets: [
        .executableTarget(
            name: "LiteS7",
            path: "Sources/LiteS7"
        ),
        .testTarget(
            name: "LiteS7Tests",
            dependencies: ["LiteS7"],
            path: "Tests/LiteS7Tests"
        )
    ]
)
