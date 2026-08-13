import CoreGraphics
import Testing
@testable import Zisla

struct ThinkingOrbGeometryTests {
    @Test
    func smallPresetMatchesOfficialFrameDensity() {
        let expectedCounts: [ThinkingOrbState: (dots: Int, lines: Int)] = [
            .working: (39, 0),
            .searching: (54, 0),
            .solving: (30, 0),
            .listening: (42, 0),
            .connecting: (9, 0),
            .weaving: (35, 0),
            .composing: (208, 0),
            .breathing: (120, 0),
            .shaping: (18, 0),
        ]

        #expect(ThinkingOrbState.taskStates.count == 9)
        for state in ThinkingOrbState.taskStates {
            let frame = ThinkingOrbRenderer.frame(state: state, size: 20, time: 0)
            #expect(frame.dots.count == expectedCounts[state]?.dots)
            #expect(frame.lines.count == expectedCounts[state]?.lines)
        }
    }

    @Test
    func smallPresetStaysCenteredAndUnclipped() {
        for state in ThinkingOrbState.taskStates {
            for time in [0.0, 0.5, 1.0, 2.0] {
                let frame = ThinkingOrbRenderer.frame(state: state, size: 20, time: time)
                let bounds = frame.renderedBounds

                #expect(bounds.minX >= 0)
                #expect(bounds.minY >= 0)
                #expect(bounds.maxX <= 20)
                #expect(bounds.maxY <= 20)
                #expect(abs(bounds.midX - 10) < 1.25)
                #expect(abs(bounds.midY - 10) < 1.25)
                #expect(bounds.width / bounds.height >= 0.90)
                #expect(bounds.width / bounds.height <= 1.45)
            }
        }
    }

    @Test
    func smallPresetMatchesOfficialAspectRatios() {
        let expected: [ThinkingOrbState: [Double]] = [
            .working: [1.122, 1.227, 1.274, 1.421],
            .searching: [1.012, 0.999, 1.008, 1.007],
            .solving: [1.060, 1.032, 1.009, 1.026],
            .listening: [0.997, 0.955, 1.004, 1.003],
            .connecting: [1.219, 1.080, 1.064, 0.959],
            .weaving: [1.033, 1.034, 1.004, 0.994],
            .composing: [1.129, 1.130, 1.146, 1.166],
            .breathing: [1.014, 0.988, 0.975, 1.030],
            .shaping: [0.986, 0.986, 1.077, 1.056],
        ]
        let times = [0.0, 0.5, 1.0, 2.0]

        for state in ThinkingOrbState.taskStates {
            for (index, time) in times.enumerated() {
                let bounds = ThinkingOrbRenderer.frame(state: state, size: 20, time: time).renderedBounds
                let ratio = bounds.width / bounds.height
                #expect(abs(ratio - (expected[state]?[index] ?? 0)) < 0.002)
            }
        }
    }

    @Test
    func smallPresetMatchesOfficialGeometrySignatures() {
        let expected: [ThinkingOrbState: Double] = [
            .working: 25_677.561_615_676,
            .searching: 46_576.996_510_874,
            .solving: 15_440.862_956_790,
            .listening: 30_527.108_710_205,
            .connecting: 1_544.378_383_459,
            .weaving: 20_667.220_812_124,
            .composing: 655_624.847_225_744,
            .breathing: 239_316.518_172_767,
            .shaping: 5_552.322_643_462,
        ]

        for state in ThinkingOrbState.taskStates {
            let frame = ThinkingOrbRenderer.frame(state: state, size: 20, time: 0.5)
            let dotSignature = frame.dots.enumerated().reduce(0.0) { result, element in
                let (index, dot) = element
                return result + Double(index + 1) * (
                    dot.x
                        + dot.y * 1.7
                        + dot.z * 0.13
                        + dot.radius * 2.3
                        + dot.white * 3.1
                        + dot.alpha * 4.7
                )
            }
            let lineSignature = frame.lines.enumerated().reduce(0.0) { result, element in
                let (index, line) = element
                return result + Double(index + 1) * (
                    line.x1
                        + line.y1 * 1.7
                        + line.x2 * 0.13
                        + line.y2 * 2.3
                        + line.white * 3.1
                        + line.alpha * 4.7
                        + line.width * 0.37
                )
            }

            #expect(abs(dotSignature + lineSignature - (expected[state] ?? 0)) < 0.000_001)
        }
    }

    @Test
    func connectingPresetMatchesOfficialLineGeometry() {
        let frame = ThinkingOrbRenderer.frame(state: .connecting, size: 20, time: 5.65)
        let signature = frame.lines.enumerated().reduce(0.0) { result, element in
            let (index, line) = element
            return result + Double(index + 1) * (
                line.x1
                    + line.y1 * 1.7
                    + line.x2 * 0.13
                    + line.y2 * 2.3
                    + line.white * 3.1
                    + line.alpha * 4.7
                    + line.width * 0.37
            )
        }

        #expect(frame.lines.count == 1)
        #expect(abs(signature - 35.153_477_794_407) < 0.000_001)
    }
}
