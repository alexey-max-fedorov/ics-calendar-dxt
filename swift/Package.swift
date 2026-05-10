// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ICSBridge",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "ICSBridge",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/ICSBridge",
            exclude: ["Info.plist", "BundleInfo.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/ICSBridge/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "ICSBridgeTests",
            dependencies: ["ICSBridge"],
            path: "Tests/ICSBridgeTests"
        )
    ]
)
