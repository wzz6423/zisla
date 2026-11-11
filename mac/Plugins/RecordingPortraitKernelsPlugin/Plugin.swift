import Foundation
import PackagePlugin

@main
struct RecordingPortraitKernelsPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let source = context.package.directoryURL.appendingPathComponent("Resources/ScreenRecording/RecordingPortrait.metal")
        let output = context.pluginWorkDirectoryURL.appendingPathComponent("RecordingPortrait.metallib")
        return [.buildCommand(displayName: "Compile portrait Metal kernels",
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["--sdk", "macosx", "metal", "-fcikernel", "-mmacosx-version-min=14.0", source.path, "-o", output.path],
            inputFiles: [source], outputFiles: [output])]
    }
}
