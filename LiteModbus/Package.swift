// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LiteModbus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LiteModbus",
            path: "Sources/LiteModbus"
        ),
        .testTarget(
            name: "LiteModbusTests",
            dependencies: ["LiteModbus"],
            path: "Tests/LiteModbusTests"
        ),
    ]
)
