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
        .library(name: "KeyboardKit", targets: ["KeyboardKit"]),
        .executable(name: "zisla", targets: ["Zisla"]),
        .executable(name: "zislactl", targets: ["zislactl"]),
    ],
    dependencies: [
        .package(path: "Vendor/SkyLightWindow"),
        .package(url: "https://github.com/awxkee/zstd.swift", exact: "1.0.2"),
    ],
    targets: [
        .target(
            name: "ZislaCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "ZislaNVMe",
            path: "Sources/ZislaNVMe",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .binaryTarget(
            name: "Sparkle",
            path: "Vendor/Sparkle.xcframework"
        ),
        .target(
            name: "ZislaKit",
            dependencies: [
                "ZislaCore",
                "ZislaNVMe",
                .product(name: "zstd", package: "zstd.swift"),
            ],
            linkerSettings: [
                .linkedFramework("WeatherKit"),
                .linkedFramework("Network"),
                .linkedFramework("PDFKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("CoreText"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreBluetooth"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "KeyboardKit",
            dependencies: ["ZislaCore", "Sparkle"],
            resources: [
                .copy("../../Resources/Keyboard"),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "Zisla",
            dependencies: [
                "ZislaCore",
                "ZislaKit",
                "KeyboardKit",
                "Sparkle",
                .product(name: "SkyLightWindow", package: "SkyLightWindow"),
            ],
            resources: [
                // Bundle the built-in pixel pet (pet.json + sprite.png) into the app.
                // Paths are relative to this target's source directory `mac/Sources/Zisla`, so go up two levels to reach `mac/Resources/Pets`.
                .copy("../../Resources/Pets"),
                .copy("../../Resources/QuickNotes"),
                .copy("../../Resources/BrandIcons"),
                .copy("../../Resources/ThirdPartyLicenses"),
                .process("../../Resources/Localization"),
            ],
            linkerSettings: [
                .linkedFramework("Speech"),
                .linkedFramework("WebKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
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
        .testTarget(
            name: "ZislaTests",
            dependencies: ["Zisla", "ZislaCore", "KeyboardKit", "Sparkle"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../../..",
                ]),
            ]
        ),
    ]
)
