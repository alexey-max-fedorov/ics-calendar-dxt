// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ICalBridge",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "ICalBridge",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/ICalBridge"
        ),
        .testTarget(
            name: "ICalBridgeTests",
            dependencies: ["ICalBridge"],
            path: "Tests/ICalBridgeTests"
        )
    ]
)
