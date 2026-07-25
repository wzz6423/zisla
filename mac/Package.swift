// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "zisla",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ZislaCore", targets: ["ZislaCore"]),
        .library(name: "ZislaKit", targets: ["ZislaKit"]),
        .executable(name: "zisla", targets: ["Zisla"]),
        .executable(name: "zislactl", targets: ["zislactl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/SkyLightWindow.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ZislaCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "ZislaKit",
            dependencies: ["ZislaCore"],
            linkerSettings: [
                .linkedFramework("WeatherKit"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "Zisla",
            dependencies: [
                "ZislaCore",
                "ZislaKit",
                "Sparkle",
                .product(name: "SkyLightWindow", package: "SkyLightWindow"),
            ],
            resources: [
                // 把内置像素宠物（pet.json + sprite.png）编入 App 包。
                // 路径相对本 target 源码目录 `mac/Sources/Zisla`，故回退两级到 `mac/Resources/Pets`。
                .copy("../../Resources/Pets"),
                .copy("../../Resources/BrandIcons"),
            ],
            linkerSettings: [
                .linkedFramework("Speech"),
                .linkedFramework("WebKit"),
            ]
        ),
        .executableTarget(
            name: "zislactl",
            dependencies: ["ZislaCore"]
        ),
        .testTarget(
            name: "ZislaCoreTests",
            dependencies: ["ZislaCore"]
        ),
        .testTarget(
            name: "ZislaKitTests",
            dependencies: ["ZislaCore", "ZislaKit"]
        ),
        .binaryTarget(
            name: "Sparkle",
            path: "Vendor/Sparkle.xcframework"
        ),
    ]
)
