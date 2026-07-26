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
        .package(path: "Vendor/SkyLightWindow"),
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
                .linkedFramework("Security"),
                .linkedFramework("Network"),
                .linkedFramework("PDFKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("CoreText"),
                .linkedFramework("AVFoundation"),
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
                // Bundle the built-in pixel pet (pet.json + sprite.png) into the app.
                // Paths are relative to this target's source directory `mac/Sources/Zisla`, so go up two levels to reach `mac/Resources/Pets`.
                .copy("../../Resources/Pets"),
                .copy("../../Resources/QuickNotes"),
                .copy("../../Resources/BrandIcons"),
            ],
            linkerSettings: [
                .linkedFramework("Speech"),
                .linkedFramework("WebKit"),
                .linkedFramework("AVFoundation"),
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
