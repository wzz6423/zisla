// swift-tools-version:6.0
import Foundation
import PackageDescription

// Xcode 27's SwiftPM links executables with the deployment target recorded as the SDK version
// ("sdk 14.0" in LC_BUILD_VERSION), which makes macOS 26+ run the app in legacy window-chrome
// compatibility mode instead of native Liquid Glass controls. Ask the toolchain for the real
// SDK version so the app link can pin the correct platform versions.
let linkedSDKVersion: String = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["--sdk", "macosx", "--show-sdk-version"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
    } catch {
        fatalError("failed to launch xcrun to resolve the macOS SDK version: \(error)")
    }
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard process.terminationStatus == 0, !output.isEmpty else {
        fatalError("cannot resolve the macOS SDK version via xcrun; the app would link with legacy window chrome")
    }
    return output
}()

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
        .package(path: "Vendor/zstd.swift"),
    ],
    targets: [
        .target(
            name: "ZislaCore",
            resources: [
                // Localization lives here so every target (ZislaKit, KeyboardKit, Zisla) shares one table.
                .process("../../Resources/Localization"),
            ],
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
            dependencies: ["ZislaCore", "ZislaKit"],
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
            ],
            linkerSettings: [
                .linkedFramework("Speech"),
                .linkedFramework("WebKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("QuartzCore"),
                // Keep the deployment target in sync with the platforms block above.
                .unsafeFlags([
                    "-Xlinker", "-platform_version",
                    "-Xlinker", "macos",
                    "-Xlinker", "14.0",
                    "-Xlinker", linkedSDKVersion,
                ]),
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
