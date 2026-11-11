import Foundation
import PackagePlugin

@main
struct PortraitMetalPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let source = context.package.directoryURL.appendingPathComponent("Resources/RecordingPortraitEffects.metal")
        let output = context.pluginWorkDirectoryURL.appendingPathComponent("RecordingPortraitEffects.metallib")
        return [.buildCommand(
            displayName: "Compile recording portrait Metal kernels",
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["--sdk", "macosx", "metal", "-fcikernel", "-std=macos-metal2.0", "-mmacosx-version-min=14.0", source.path, "-o", output.path],
            inputFiles: [source],
            outputFiles: [output]
        )]
    }
}
