import Darwin
import Foundation
import Testing

@main
struct SwiftTestingHost {
    static func main() {
        var arguments = CommandLine.arguments.makeIterator()
        while let argument = arguments.next() {
            if argument == "--test-bundle-path", let path = arguments.next() {
                guard dlopen(path, RTLD_NOW | RTLD_GLOBAL) != nil else {
                    fputs(String(cString: dlerror()) + "\n", stderr)
                    exit(1)
                }
                break
            }
        }
        Task {
            await Testing.__swiftPMEntryPoint() as Never
        }
        // AppKit can stop the run loop to wake it; keep running until Swift Testing exits.
        RunLoop.main.run()
    }
}
