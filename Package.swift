// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Bema",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Bema",
            path: "Sources/Bema",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BemaTests",
            dependencies: ["Bema"],
            path: "Tests/BemaTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
