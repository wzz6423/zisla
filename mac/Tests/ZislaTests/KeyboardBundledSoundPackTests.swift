import AVFAudio
import Foundation
import Testing

@testable import KeyboardKit

struct KeyboardBundledSoundPackTests {
    @Test(arguments: ["WhiteFox Hako Violet", "Apple M0118 ALPS SKCM Orange", "BCP (Suit80)"])
    func bundledRecordingLoadsAndResolvesEveryAssignableKey(name: String) async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla.SoundPacks.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let library = SoundPackLibrary(rootURL: temporary)
        let descriptors = try await library.descriptors()
        let descriptor = try #require(descriptors.first { $0.name == name })
        #expect(descriptors.filter { $0.name == name }.count == 1)
        #expect(descriptor.isReadOnly)
        let document = try await library.loadPack(for: descriptor)
        let resolver = SoundPackResolver(manifest: document.manifest)
        for key in KeyboardLayoutCatalog.ansiTKL.keys where key.isAssignable {
            let press = try #require(resolver.audioAsset(for: key.keyCode, phase: .press))
            let release = try #require(resolver.audioAsset(for: key.keyCode, phase: .release))
            #expect(press.id != release.id, "\(name): \(key.id) must preserve separate press and release recordings")
        }
        for keyCode: UInt16 in [76, 117, UInt16.max] {
            #expect(resolver.audioAsset(for: keyCode, phase: .press) != nil)
            #expect(resolver.audioAsset(for: keyCode, phase: .release) != nil)
        }

        for assetID in document.manifest.referencedAssetIDs {
            let url = try document.assetURL(for: assetID)
            let file = try AVAudioFile(forReading: url)
            #expect(file.processingFormat.sampleRate == 48_000)
            #expect(file.processingFormat.channelCount == 1)
            let buffer = try #require(AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ))
            try file.read(into: buffer)
            let channel = try #require(buffer.floatChannelData?[0])
            let frames = Int(buffer.frameLength)
            #expect(frames > 0)
            var energy: Double = 0
            var peak: Float = 0
            for index in 0..<frames {
                let sample = channel[index]
                #expect(sample.isFinite)
                energy += Double(sample * sample)
                peak = max(peak, abs(sample))
            }
            #expect(energy / Double(max(frames, 1)) > 0.000001, "\(name): \(url.lastPathComponent) is silent")
            #expect(peak < 0.99, "\(name): \(url.lastPathComponent) clips")
        }
    }
}
