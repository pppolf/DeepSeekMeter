// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeepSeekMeter",
    platforms: [.macOS(.v14)],
    targets: [
        // 菜单栏 App（单 target）
        .executableTarget(
            name: "DeepSeekMeter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
