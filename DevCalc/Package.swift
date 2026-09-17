// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DevCalc",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DevCalc",
            path: "Sources/DevCalc"
        ),
        .testTarget(
            name: "DevCalcTests",
            dependencies: ["DevCalc"],
            path: "Tests/DevCalcTests"
        ),
    ]
)
