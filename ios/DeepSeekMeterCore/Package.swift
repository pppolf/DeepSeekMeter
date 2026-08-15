// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeepSeekMeterCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        // iOS App 通过本地包依赖引用；macOS 包保持单 target 不动（见 MOBILE-PLAN.md）
        .library(name: "DeepSeekMeterCore", targets: ["DeepSeekMeterCore"])
    ],
    targets: [
        // 核心逻辑库：与 Sources/DeepSeekMeter/ 逐文件对应（PlatformService / Models / Formatting），
        // 零第三方依赖；Swift 5 语言模式对齐仓库 macOS 包
        .target(
            name: "DeepSeekMeterCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 轻量自测（不依赖 XCTest，CLT 环境可直接运行，对齐 Scripts/selftest 精神）
        .executableTarget(
            name: "DeepSeekMeterCoreSelftest",
            dependencies: ["DeepSeekMeterCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
