import Foundation
import PackagePlugin

@main
struct RecordingPortraitKernels: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let source = context.package.directoryURL.appendingPathComponent("Resources/RecordingPortraitKernels.metal")
        let library = context.pluginWorkDirectoryURL.appendingPathComponent("RecordingPortraitKernels.metallib")
        return [.buildCommand(displayName: "Compile recording portrait kernels", executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["--sdk", "macosx", "metal", "-fcikernel", "-mmacosx-version-min=14.0",
                source.path, "-o", library.path], inputFiles: [source], outputFiles: [library])]
    }
}
