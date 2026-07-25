import Foundation
import Testing

@testable import ZislaKit

struct AudioSpectrumServiceTests {
    @Test
    func silenceProducesNoFrequencyEnergy() {
        let analyzer = AudioFrequencyAnalyzer()

        let levels = analyzer.process(
            samples: Array(repeating: 0, count: analyzer.fftSize),
            sampleRate: 48_000
        )

        #expect(levels.count == AudioFrequencyAnalyzer.bandCount)
        #expect(levels.allSatisfy { $0 == 0 })
    }

    @Test
    func bassTonePrimarilyDrivesLowFrequencyBands() throws {
        let analyzer = AudioFrequencyAnalyzer()
        let sampleRate = 48_000.0
        let samples = (0..<analyzer.fftSize).map { index in
            Float(sin(2 * Double.pi * 100 * Double(index) / sampleRate) * 0.7)
        }

        let levels = analyzer.process(samples: samples, sampleRate: sampleRate)
        let lowPeak = try #require(levels.prefix(3).max())
        let highPeak = try #require(levels.suffix(2).max())

        #expect(lowPeak > 0.5)
        #expect(lowPeak > highPeak + 0.25)
    }
}
