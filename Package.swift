// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Bema",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Automatic updates. The framework is copied into Bema.app/Contents/Frameworks by the build scripts.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Bema",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Bema",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "BemaTests",
            dependencies: ["Bema"],
            path: "Tests/BemaTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
