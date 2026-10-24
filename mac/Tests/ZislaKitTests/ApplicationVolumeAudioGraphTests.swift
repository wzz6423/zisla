import CoreAudio
import Darwin
import Foundation
import Testing

@testable import ZislaKit

struct ApplicationVolumeAudioGraphTests {
    @Test
    func liveGainAndMutePreserveTapProgress() throws {
        let hardware = ApplicationVolumeHardwareStub()
        let graph = try Self.graph(hardware)
        defer { graph.stop() }
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.25, 1, -0.5]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9, 9, 9]])
        hardware.emit(input: input, output: output)
        #expect(output.samples(at: 0) == [0.25, -0.125, 0.5, -0.25])

        graph.gain = 0.25
        hardware.emit(input: input, output: output)
        #expect(output.samples(at: 0) == [0.125, -0.0625, 0.25, -0.125])
        graph.gain = 0
        hardware.emit(input: input, output: output)
        #expect(output.samples(at: 0) == [0, 0, 0, 0])
        #expect(graph.renderProgress == 3, "用户静音仍需表明 tap 持续可读，防止看门狗错误恢复原音量")
        #expect(input.samples(at: 0) == [0.5, -0.25, 1, -0.5])
        #expect(output.hasIntactCanaries)
    }

    @Test
    func stoppedGraphSilencesRetainedCallbackWithoutReportingProgress() throws {
        let hardware = ApplicationVolumeHardwareStub()
        let graph = try Self.graph(hardware)
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        hardware.emit(input: input, output: output)
        #expect(output.samples(at: 0) == [0.25, -0.25])
        let progress = graph.renderProgress

        graph.stop()
        hardware.emit(input: input, output: output)

        #expect(output.samples(at: 0) == [0, 0], "停止后保留的旧回调不能重放音频")
        #expect(graph.renderProgress == progress, "停止后旧回调不能继续报告进展")
        #expect(hardware.liveTaps.isEmpty && hardware.liveAggregates.isEmpty && hardware.liveIO.isEmpty)
    }

    @Test
    func planarFormatRejectsInterleavedCallbackLayout() throws {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.formats = [applicationVolumeFloatFormat(channels: 2, planar: true)]
        let graph = try Self.graph(hardware)
        defer { graph.stop() }
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])

        hardware.emit(input: input, output: output)

        #expect(output.samples(at: 0) == [0, 0], "回调布局必须匹配已验证的 planar 输出格式")
        #expect(graph.renderProgress == 0)
        #expect(output.hasIntactCanaries)
    }

    @Test
    func planarStereoFormatRendersIntoSeparateChannelBuffers() throws {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.formats = [applicationVolumeFloatFormat(channels: 2, planar: true)]
        let graph = try Self.graph(hardware)
        defer { graph.stop() }
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5, 1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [1, 1], samples: [[9, 9], [9, 9]])

        hardware.emit(input: input, output: output)

        #expect(output.samples(at: 0) == [0.25, 0.5])
        #expect(output.samples(at: 1) == [-0.25, -0.5])
        #expect(graph.renderProgress == 1)
        #expect(output.hasIntactCanaries)
    }

    @Test
    func compensationIsAppliedAndRequeriedForARebuiltGraph() throws {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.compensation = 4
        var graph: ApplicationVolumeAudioGraph? = try Self.graph(hardware)
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.125, -0.125]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        hardware.emit(input: input, output: output)
        #expect(output.samples(at: 0) == [0.25, -0.25])
        graph?.stop()
        graph = nil
        hardware.compensation = 2
        hardware.output = ApplicationVolumeOutput(id: 51, uid: "another-test-output")
        graph = try Self.graph(hardware)
        defer { graph?.stop() }

        hardware.emit(input: input, output: output, at: 1)

        #expect(output.samples(at: 0) == [0.125, -0.125])
        #expect(graph?.output == hardware.output)
    }

    @Test
    func missingTapNeverReplaysMatchingPhysicalInputOrReportsProgress() throws {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.configuredInputChannels = [2, 2]
        let graph = try Self.graph(hardware)
        defer { graph.stop() }
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        let omittedTap = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.75, -0.75]])
        hardware.emit(input: omittedTap, output: output)
        #expect(output.samples(at: 0) == [0, 0])
        #expect(graph.renderProgress == 0)
        let disabledTap = ApplicationVolumeBufferFixture(
            channels: [2, 2], samples: [[0.75, -0.75], [0.5, -0.5]], absentData: [1]
        )
        hardware.emit(input: disabledTap, output: output)
        #expect(output.samples(at: 0) == [0, 0])
        #expect(graph.renderProgress == 0)
        let restoredTap = ApplicationVolumeBufferFixture(channels: [2, 2], samples: [[0.75, -0.75], [0.5, -0.5]])
        hardware.emit(input: restoredTap, output: output)
        #expect(output.samples(at: 0) == [0.25, -0.25])
        #expect(graph.renderProgress == 1)
        #expect(output.hasIntactCanaries)
    }

    @Test(arguments: [
        ApplicationVolumeHardwareStub.Stage.compensation, .tap, .tapFormat, .aggregate,
        .outputFormats, .inputChannels, .stereoChannels, .io, .start,
    ])
    func creationFailuresReleaseEveryAcquiredResource(stage: ApplicationVolumeHardwareStub.Stage) {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.failAt = stage
        #expect(throws: hardware.failure) { _ = try Self.graph(hardware) }

        #expect(hardware.liveTaps.isEmpty, "\(stage) 失败后不得保留已创建的 tap")
        #expect(hardware.liveAggregates.isEmpty, "\(stage) 失败后不得保留聚合设备")
        #expect(hardware.liveIO.isEmpty, "\(stage) 失败后不得保留 IO 回调")
        let created = hardware.events.filter { $0.hasPrefix("create") }
        let destroyed = hardware.events.filter { $0.hasPrefix("destroy") }
        let expectedCleanup = created.reversed().map { $0.replacingOccurrences(of: "create", with: "destroy") }
        #expect(destroyed == expectedCleanup, "失败应按 IO、聚合设备、tap 的逆序释放")
    }

    @Test
    func permissionFailureNeverStartsOrRetainsAudioResources() {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.failAt = .tap
        hardware.failure = .permissionDenied

        #expect(throws: ApplicationVolumeFailure.permissionDenied) { _ = try Self.graph(hardware) }

        #expect(hardware.events.isEmpty)
        #expect(hardware.liveTaps.isEmpty && hardware.liveAggregates.isEmpty && hardware.liveIO.isEmpty)
    }

    @Test
    func tapRequestIsPrivateAndRestoresOriginalPlaybackWhenNotRead() throws {
        let hardware = ApplicationVolumeHardwareStub()
        let graph = try Self.graph(hardware)
        defer { graph.stop() }
        let description = try #require(hardware.tapDescriptions.first)

        #expect(description.processes == [101])
        #expect(description.isPrivate)
        #expect(!description.isExclusive)
        #expect(description.muteBehavior == .mutedWhenTapped)
    }

    @Test
    func stopIsIdempotentAndStopsReadingBeforeDestruction() throws {
        let hardware = ApplicationVolumeHardwareStub()
        var graph: ApplicationVolumeAudioGraph? = try Self.graph(hardware)

        graph?.stopReading()
        graph?.stopReading()
        #expect(!hardware.liveTaps.isEmpty && !hardware.liveAggregates.isEmpty && !hardware.liveIO.isEmpty)
        graph?.stop()
        let events = hardware.events
        graph?.stop()
        graph = nil

        #expect(hardware.events == events, "重复 stop 和 deinit 不能再次销毁同一资源")
        #expect(events.suffix(4) == ["stopIO:102", "destroyIO:103", "destroyAggregate:102", "destroyTap:101"])
        #expect(hardware.liveTaps.isEmpty && hardware.liveAggregates.isEmpty && hardware.liveIO.isEmpty)
    }

    @Test
    func deinitializationReleasesResourcesAndDisablesRetainedCallback() throws {
        let hardware = ApplicationVolumeHardwareStub()
        var graph: ApplicationVolumeAudioGraph? = try Self.graph(hardware)
        #expect(graph != nil)

        graph = nil
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        hardware.emit(input: input, output: output)

        #expect(output.samples(at: 0) == [0, 0])
        #expect(hardware.liveTaps.isEmpty && hardware.liveAggregates.isEmpty && hardware.liveIO.isEmpty)
    }

    @Test
    func stopReadingDisablesRetainedCallbackBeforeDeferredDisposal() throws {
        let hardware = ApplicationVolumeHardwareStub()
        let disposal = ApplicationVolumeDisposalStub()
        let graph = try ApplicationVolumeAudioGraph(
            processObjects: [101], output: hardware.output, gain: 0.5, hardware: hardware,
            dispose: { disposal.enqueue($0) }
        )
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        hardware.emit(input: input, output: output)
        let progress = graph.renderProgress

        graph.stopReading()
        hardware.emit(input: input, output: output)
        #expect(output.samples(at: 0) == [0, 0])
        #expect(graph.renderProgress == progress)
        graph.stop()
        graph.stop()
        #expect(disposal.pendingCount == 1)
        #expect(!hardware.liveTaps.isEmpty && !hardware.liveAggregates.isEmpty && !hardware.liveIO.isEmpty)
        hardware.emit(input: input, output: output)
        #expect(output.samples(at: 0) == [0, 0])
        #expect(graph.renderProgress == progress)
        disposal.flush()
        #expect(hardware.liveTaps.isEmpty && hardware.liveAggregates.isEmpty && hardware.liveIO.isEmpty)
        #expect(disposal.pendingCount == 0)
    }

    @Test
    func failedStartDisablesRetainedCallbackWhileItsResourcesAreDisposed() {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.failAt = .start
        #expect(throws: hardware.failure) { _ = try Self.graph(hardware) }
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])

        hardware.emit(input: input, output: output)

        #expect(output.samples(at: 0) == [0, 0])
        #expect(hardware.liveTaps.isEmpty && hardware.liveAggregates.isEmpty && hardware.liveIO.isEmpty)
    }

    @Test(arguments: InvalidFormat.allCases)
    func unsupportedFormatsReleaseTheTapAndAggregate(scenario: InvalidFormat) {
        let hardware = ApplicationVolumeHardwareStub()
        switch scenario {
        case .planarTap: hardware.format = applicationVolumeFloatFormat(channels: 2, planar: true)
        case .integerTap: hardware.format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        case .emptyOutput: hardware.formats = []
        case .integerOutput: hardware.formats[0].mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        case .differentSampleRate: hardware.formats[0].mSampleRate = 44_100
        case .missingTapStream: hardware.configuredInputChannels = []
        case .wrongTapChannels: hardware.configuredInputChannels = [1]
        case .negativeStereoChannel: hardware.preferredStereoChannels = .init(left: -1, right: 1)
        case .outOfRangeStereoChannel: hardware.preferredStereoChannels = .init(left: 0, right: 2)
        case .duplicateStereoChannels: hardware.preferredStereoChannels = .init(left: 0, right: 0)
        }

        #expect(throws: ApplicationVolumeFailure.unsupportedFormat) { _ = try Self.graph(hardware) }

        #expect(hardware.callbacks.isEmpty)
        #expect(hardware.liveTaps.isEmpty && hardware.liveAggregates.isEmpty && hardware.liveIO.isEmpty)
        let created = hardware.events.filter { $0.hasPrefix("create") }
        let expectedCleanup = created.reversed().map { $0.replacingOccurrences(of: "create", with: "destroy") }
        #expect(hardware.events.filter { $0.hasPrefix("destroy") } == expectedCleanup)
    }

    @Test
    func malformedFloatDescriptionsAreRejectedWithoutChannelOverflow() {
        #expect(ApplicationVolumeAudioGraph.isNativeFloat(applicationVolumeFloatFormat(channels: 1)))
        #expect(ApplicationVolumeAudioGraph.isNativeFloat(applicationVolumeFloatFormat(channels: 6)))
        #expect(ApplicationVolumeAudioGraph.isNativeFloat(applicationVolumeFloatFormat(channels: 2, planar: true)))
        var format = applicationVolumeFloatFormat(channels: 2)
        format.mFormatID = kAudioFormatAC3
        #expect(!ApplicationVolumeAudioGraph.isNativeFloat(format))
        format = applicationVolumeFloatFormat(channels: 2)
        format.mFormatFlags |= kAudioFormatFlagIsBigEndian
        #expect(!ApplicationVolumeAudioGraph.isNativeFloat(format))
        format = applicationVolumeFloatFormat(channels: 2)
        format.mBitsPerChannel = 64
        #expect(!ApplicationVolumeAudioGraph.isNativeFloat(format))
        format = applicationVolumeFloatFormat(channels: 0)
        #expect(!ApplicationVolumeAudioGraph.isNativeFloat(format))
        format = applicationVolumeFloatFormat(channels: UInt32.max)
        #expect(!ApplicationVolumeAudioGraph.isNativeFloat(format), "外部异常声道数必须被拒绝，不能使字节乘法溢出")
        format = applicationVolumeFloatFormat(channels: 2)
        format.mBytesPerFrame = 4
        #expect(!ApplicationVolumeAudioGraph.isNativeFloat(format))
        for rate in [Double.zero, -1, .infinity, .nan] {
            #expect(!ApplicationVolumeAudioGraph.isNativeFloat(applicationVolumeFloatFormat(channels: 2, sampleRate: rate)))
        }
    }

    @Test(arguments: [[Int](), [1], [2, 1], [1, 2]])
    func callbackWithAnotherOutputLayoutIsSilenced(channels: [Int]) throws {
        let hardware = ApplicationVolumeHardwareStub()
        let graph = try Self.graph(hardware)
        defer { graph.stop() }
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5]])
        let output = ApplicationVolumeBufferFixture(
            channels: channels, samples: channels.map { Array(repeating: 9, count: $0) }
        )

        hardware.emit(input: input, output: output)

        #expect(channels.indices.allSatisfy { output.bytes(at: $0).allSatisfy { $0 == 0 } })
        #expect(graph.renderProgress == 0)
        #expect(output.hasIntactCanaries)
    }

    @Test
    func oversizedPlanarChannelCountCannotExpandIntoUnboundedBuffers() throws {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.formats = [applicationVolumeFloatFormat(channels: UInt32.max, planar: true)]
        let graph = try Self.graph(hardware)
        defer { graph.stop() }
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])

        hardware.emit(input: input, output: output)

        #expect(output.samples(at: 0) == [0, 0])
        #expect(graph.renderProgress == 0)
        #expect(output.hasIntactCanaries)
    }

    @Test
    func monoAndMultichannelOutputFormatsMatchTheirCallbackLayout() throws {
        let hardware = ApplicationVolumeHardwareStub()
        hardware.formats = [applicationVolumeFloatFormat(channels: 1)]
        hardware.preferredStereoChannels = .init(left: 0, right: 0)
        var graph: ApplicationVolumeAudioGraph? = try Self.graph(hardware)
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.75, 0.25]])
        let mono = ApplicationVolumeBufferFixture(channels: [1], samples: [[9]])
        hardware.emit(input: input, output: mono)
        #expect(mono.samples(at: 0) == [0.25])
        graph?.stop()
        hardware.formats = [applicationVolumeFloatFormat(channels: 1), applicationVolumeFloatFormat(channels: 3)]
        hardware.preferredStereoChannels = .init(left: 1, right: 3)
        graph = try Self.graph(hardware)
        defer { graph?.stop() }
        let multi = ApplicationVolumeBufferFixture(channels: [1, 3], samples: [[9], [9, 9, 9]])

        hardware.emit(input: input, output: multi, at: 1)

        #expect(multi.samples(at: 0) == [0])
        #expect(multi.samples(at: 1) == [0.375, 0, 0.125])
        #expect(graph?.renderProgress == 1)
        #expect(mono.hasIntactCanaries && multi.hasIntactCanaries)
    }

    @Test(arguments: [
        ([Int](), Float(1)), ([1], Float(1)), ([2], Float(1)),
        ([6], Float(3)), ([8], Float(4)), ([2, 8], Float(1)), ([8, 6], Float(3)),
    ])
    func stereoMixdownCompensationIsBoundedByItsNarrowestSourceStream(channels: [Int], expected: Float) {
        #expect(CoreAudioVolumeHardware.tapLevelCompensation(streamChannels: channels) == expected)
    }

    enum InvalidFormat: CaseIterable, Sendable {
        case planarTap, integerTap, emptyOutput, integerOutput, differentSampleRate
        case missingTapStream, wrongTapChannels, negativeStereoChannel, outOfRangeStereoChannel, duplicateStereoChannels
    }

    private static func graph(_ hardware: ApplicationVolumeHardwareStub) throws -> ApplicationVolumeAudioGraph {
        try ApplicationVolumeAudioGraph(
            processObjects: [101], output: hardware.output, gain: 0.5, hardware: hardware, dispose: { $0() }
        )
    }
}

struct ApplicationVolumeRendererTests {
    @Test(arguments: [Float(1), 0.5, 0])
    func stereoInterleavedGainAndMuteAreSampleAccurate(gain: Float) {
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5, 1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9, 9, 9]])

        let frames = render(input, output, gain: gain)

        #expect(frames == 2)
        #expect(output.samples(at: 0) == [0.5 * gain, -0.5 * gain, gain, -gain])
        #expect(input.samples(at: 0) == [0.5, -0.5, 1, -1])
        #expect(input.hasIntactCanaries && output.hasIntactCanaries)
    }

    @Test
    func monoTapIsDuplicatedAndStereoTapIsAveragedForMonoOutput() {
        let monoInput = ApplicationVolumeBufferFixture(channels: [1], samples: [[0.5, -0.5]])
        let stereoOutput = ApplicationVolumeBufferFixture(channels: [1, 1], samples: [[9, 9], [9, 9]])
        #expect(render(monoInput, stereoOutput, tapChannels: 1) == 2)
        #expect(stereoOutput.samples(at: 0) == [0.25, -0.25])
        #expect(stereoOutput.samples(at: 1) == [0.25, -0.25])
        let stereoInput = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.75, 0.25, -0.5, 0.5]])
        let monoOutput = ApplicationVolumeBufferFixture(channels: [1], samples: [[9, 9]])
        #expect(render(stereoInput, monoOutput, stereo: .init(left: 0, right: 0)) == 2)
        #expect(monoOutput.samples(at: 0) == [0.25, 0])
        #expect(stereoOutput.hasIntactCanaries && monoOutput.hasIntactCanaries)
    }

    @Test
    func stereoRoutesToPreferredChannelsOfAnInterleavedMultichannelOutput() {
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5, 1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [6], samples: [Array(repeating: 9, count: 12)])

        #expect(render(input, output, stereo: .init(left: 2, right: 4)) == 2)

        #expect(output.samples(at: 0) == [0, 0, 0.25, 0, -0.25, 0, 0, 0, 0.5, 0, -0.5, 0])
        #expect(output.hasIntactCanaries)
    }

    @Test
    func preferredStereoChannelsCrossPlanarAndInterleavedOutputBuffers() {
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5, 1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [1, 2, 1], samples: [[9, 9], [9, 9, 9, 9], [9, 9]])

        #expect(render(input, output, stereo: .init(left: 1, right: 3)) == 2)

        #expect(output.samples(at: 0) == [0, 0])
        #expect(output.samples(at: 1) == [0.25, 0, 0.5, 0])
        #expect(output.samples(at: 2) == [-0.25, -0.5])
        #expect(output.hasIntactCanaries)
    }

    @Test
    func absentOrMismatchedTapCannotFallBackToPhysicalAudio() {
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        let physicalOnly = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.75, -0.75]])
        #expect(render(physicalOnly, output, tapBufferIndex: 1) == 0)
        #expect(output.samples(at: 0) == [0, 0])
        let disabled = ApplicationVolumeBufferFixture(
            channels: [2, 2], samples: [[0.75, -0.75], [0.5, -0.5]], absentData: [1]
        )
        #expect(render(disabled, output, tapBufferIndex: 1) == 0)
        #expect(output.samples(at: 0) == [0, 0])
        let extraStream = ApplicationVolumeBufferFixture(
            channels: [2, 2, 2], samples: [[0.75, -0.75], [0.5, -0.5], [1, -1]]
        )
        #expect(render(extraStream, output, tapBufferIndex: 1) == 0)
        #expect(output.samples(at: 0) == [0, 0])
        let wrongChannels = ApplicationVolumeBufferFixture(channels: [2, 1], samples: [[0.75, -0.75], [0.5]])
        #expect(render(wrongChannels, output, tapBufferIndex: 1) == 0)
        #expect(output.samples(at: 0) == [0, 0])
        #expect(output.hasIntactCanaries)
    }

    @Test
    func onlyCompleteFramesAreCopiedAndEveryRemainingByteIsZeroed() {
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5, 1]], byteSizes: [11])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9, 9, 9]], byteSizes: [17])

        #expect(render(input, output) == 1)

        #expect(output.samples(at: 0) == [0.25, -0.25, 0, 0])
        #expect(output.bytes(at: 0).suffix(9).allSatisfy { $0 == 0 })
        #expect(input.hasIntactCanaries && output.hasIntactCanaries)
    }

    @Test(arguments: 0...7)
    func incompleteStereoInputFramesProduceSilence(byteCount: Int) {
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5]], byteSizes: [byteCount])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])

        #expect(render(input, output) == 0)

        #expect(output.bytes(at: 0).allSatisfy { $0 == 0 })
        #expect(input.hasIntactCanaries && output.hasIntactCanaries)
    }

    @Test
    func shorterAndDisabledOutputBuffersRemainWithinTheirCapacity() {
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5, 1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [1, 1], samples: [[9], [9, 9]], byteSizes: [5, 8])
        #expect(render(input, output) == 2)
        #expect(output.samples(at: 0) == [0.25])
        #expect(output.bytes(at: 0).last == 0)
        #expect(output.samples(at: 1) == [-0.25, -0.5])
        #expect(output.hasIntactCanaries)
        let disabled = ApplicationVolumeBufferFixture(channels: [1, 1], samples: [[9, 9], [9, 9]], absentData: [0])
        #expect(render(input, disabled) == 2)
        #expect(disabled.samples(at: 1) == [-0.25, -0.5])
        #expect(disabled.hasIntactCanaries)
    }

    @Test
    func emptyInputAndOutputListsProduceNoProgress() {
        let empty = ApplicationVolumeBufferFixture(channels: [], samples: [])
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        #expect(render(empty, output) == 0)
        #expect(output.samples(at: 0) == [0, 0])
        #expect(render(input, empty) == 0)
        #expect(output.hasIntactCanaries)
    }

    @Test
    func inactiveRendererZerosOutputWithoutConsumingInput() {
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.5, -0.5]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])

        let frames = ApplicationVolumeRenderer.render(
            input: UnsafePointer(input.list), output: output.list, tapBufferIndex: 0, tapChannels: 2,
            stereoChannels: .init(left: 0, right: 1), gain: 1,
            outputFormats: [applicationVolumeFloatFormat(channels: 2)], isActive: false
        )

        #expect(frames == 0)
        #expect(output.samples(at: 0) == [0, 0])
        #expect(input.samples(at: 0) == [0.5, -0.5])
        #expect(input.hasIntactCanaries && output.hasIntactCanaries)
    }

    private func render(
        _ input: ApplicationVolumeBufferFixture, _ output: ApplicationVolumeBufferFixture,
        tapBufferIndex: Int = 0, tapChannels: Int = 2,
        stereo: ApplicationVolumeStereoChannels = .init(left: 0, right: 1), gain: Float = 0.5
    ) -> Int {
        ApplicationVolumeRenderer.render(
            input: UnsafePointer(input.list), output: output.list, tapBufferIndex: tapBufferIndex,
            tapChannels: tapChannels, stereoChannels: stereo, gain: gain,
            outputFormats: UnsafeMutableAudioBufferListPointer(output.list).map {
                applicationVolumeFloatFormat(channels: $0.mNumberChannels)
            },
            isActive: true
        )
    }
}

func applicationVolumeFloatFormat(channels: UInt32, planar: Bool = false, sampleRate: Double = 48_000)
    -> AudioStreamBasicDescription {
    let bytesPerFrame = planar ? 4 : channels.multipliedReportingOverflow(by: 4).partialValue
    return AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
            | (planar ? kAudioFormatFlagIsNonInterleaved : 0),
        mBytesPerPacket: bytesPerFrame,
        mFramesPerPacket: 1,
        mBytesPerFrame: bytesPerFrame,
        mChannelsPerFrame: channels,
        mBitsPerChannel: 32,
        mReserved: 0
    )
}

final class ApplicationVolumeHardwareStub: ApplicationVolumeAudioHardware, @unchecked Sendable {
    enum Stage: CaseIterable, Sendable {
        case defaultOutput, processObjects, compensation, tap, tapFormat, aggregate
        case outputFormats, inputChannels, stereoChannels, io, start
    }

    var output = ApplicationVolumeOutput(id: 50, uid: "test-output")
    var objectsByPID: [pid_t: AudioObjectID] = [:]
    var compensation: Float = 1
    var format = applicationVolumeFloatFormat(channels: 2)
    var formats = [applicationVolumeFloatFormat(channels: 2)]
    var configuredInputChannels = [2]
    var preferredStereoChannels = ApplicationVolumeStereoChannels(left: 0, right: 1)
    var failAt: Stage?
    var failure: ApplicationVolumeFailure = .hardware(-9)
    var failTapForProcesses: Set<[AudioObjectID]> = []

    private let lock = NSLock()
    private var nextID: AudioObjectID = 100
    private var recordedEvents: [String] = []
    private var descriptions: [CATapDescription] = []
    private var recordedCallbacks: [AudioDeviceIOBlock] = []
    private var taps: Set<AudioObjectID> = []
    private var aggregates: Set<AudioObjectID> = []
    private var io: Set<AudioObjectID> = []

    var events: [String] { lock.withLock { recordedEvents } }
    var tapDescriptions: [CATapDescription] { lock.withLock { descriptions } }
    var callbacks: [AudioDeviceIOBlock] { lock.withLock { recordedCallbacks } }
    var liveTaps: Set<AudioObjectID> { lock.withLock { taps } }
    var liveAggregates: Set<AudioObjectID> { lock.withLock { aggregates } }
    var liveIO: Set<AudioObjectID> { lock.withLock { io } }

    func defaultOutput() throws -> ApplicationVolumeOutput {
        try fail(.defaultOutput)
        return output
    }

    func processObjects(for identifiers: [pid_t]) throws -> [AudioObjectID] {
        try fail(.processObjects)
        return Array(Set(identifiers.map { objectsByPID[$0] ?? AudioObjectID($0) })).sorted()
    }

    func tapLevelCompensation(for processObjects: [AudioObjectID]) throws -> Float {
        try fail(.compensation)
        return compensation
    }

    func createTap(_ description: CATapDescription) throws -> AudioObjectID {
        lock.withLock { descriptions.append(description) }
        try fail(.tap)
        if failTapForProcesses.contains(description.processes) { throw failure }
        return lock.withLock {
            nextID += 1
            taps.insert(nextID)
            recordedEvents.append("createTap:\(nextID)")
            return nextID
        }
    }

    func tapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        try fail(.tapFormat)
        return format
    }

    func createAggregate(_ description: [String: Any]) throws -> AudioObjectID {
        try fail(.aggregate)
        return lock.withLock {
            nextID += 1
            aggregates.insert(nextID)
            recordedEvents.append("createAggregate:\(nextID)")
            return nextID
        }
    }

    func outputFormats(_ device: AudioObjectID) throws -> [AudioStreamBasicDescription] {
        try fail(.outputFormats)
        return formats
    }

    func inputChannels(_ device: AudioObjectID) throws -> [Int] {
        try fail(.inputChannels)
        return configuredInputChannels
    }

    func stereoChannels(_ device: AudioObjectID) throws -> ApplicationVolumeStereoChannels {
        try fail(.stereoChannels)
        return preferredStereoChannels
    }

    func createIO(_ device: AudioObjectID, callback: @escaping AudioDeviceIOBlock) throws -> AudioDeviceIOProcID {
        try fail(.io)
        return lock.withLock {
            nextID += 1
            io.insert(nextID)
            recordedCallbacks.append(callback)
            recordedEvents.append("createIO:\(nextID)")
            return unsafeBitCast(UInt(nextID), to: AudioDeviceIOProcID.self)
        }
    }

    func startIO(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID) throws {
        try fail(.start)
        lock.withLock { recordedEvents.append("startIO:\(device)") }
    }

    func stopIO(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID) {
        lock.withLock { recordedEvents.append("stopIO:\(device)") }
    }

    func destroyIO(_ device: AudioObjectID, _ proc: AudioDeviceIOProcID) {
        let identifier = AudioObjectID(unsafeBitCast(proc, to: UInt.self))
        lock.withLock {
            io.remove(identifier)
            recordedEvents.append("destroyIO:\(identifier)")
        }
    }

    func destroyAggregate(_ device: AudioObjectID) {
        lock.withLock {
            aggregates.remove(device)
            recordedEvents.append("destroyAggregate:\(device)")
        }
    }

    func destroyTap(_ tap: AudioObjectID) {
        lock.withLock {
            taps.remove(tap)
            recordedEvents.append("destroyTap:\(tap)")
        }
    }

    func emit(input: ApplicationVolumeBufferFixture, output: ApplicationVolumeBufferFixture, at index: Int = 0) {
        let callback = callbacks[index]
        var timestamp = AudioTimeStamp()
        withUnsafePointer(to: &timestamp) { time in
            callback(time, UnsafePointer(input.list), time, output.list, time)
        }
    }

    private func fail(_ stage: Stage) throws {
        if failAt == stage { throw failure }
    }
}

final class ApplicationVolumeBufferFixture {
    let list: UnsafeMutablePointer<AudioBufferList>
    private let storage: UnsafeMutableRawPointer
    private var data: [UnsafeMutableRawPointer?] = []
    private var byteCounts: [Int] = []
    private var trailingBytes: [[UInt8]] = []

    init(channels: [Int], samples: [[Float]], byteSizes: [Int]? = nil, absentData: Set<Int> = []) {
        precondition(channels.count == samples.count && (byteSizes == nil || byteSizes?.count == channels.count))
        let byteCount = MemoryLayout<AudioBufferList>.size
            + max(0, channels.count - 1) * MemoryLayout<AudioBuffer>.stride
        storage = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<AudioBufferList>.alignment)
        list = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        list.initialize(to: AudioBufferList(mNumberBuffers: UInt32(channels.count), mBuffers: AudioBuffer()))
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        for index in channels.indices {
            let size = byteSizes?[index] ?? samples[index].count * MemoryLayout<Float>.size
            let capacity = max(size, samples[index].count * MemoryLayout<Float>.size) + 16
            let pointer: UnsafeMutableRawPointer?
            if absentData.contains(index) {
                pointer = nil
                trailingBytes.append([])
            } else {
                let allocation = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: MemoryLayout<Float>.alignment)
                memset(allocation, 0xa5, capacity)
                for (sampleIndex, sample) in samples[index].enumerated() {
                    allocation.storeBytes(of: sample, toByteOffset: sampleIndex * MemoryLayout<Float>.size, as: Float.self)
                }
                pointer = allocation
                trailingBytes.append(Array(UnsafeRawBufferPointer(start: allocation.advanced(by: size), count: capacity - size)))
            }
            data.append(pointer)
            byteCounts.append(size)
            buffers[index] = AudioBuffer(mNumberChannels: UInt32(channels[index]), mDataByteSize: UInt32(size), mData: pointer)
        }
    }

    deinit {
        for pointer in data { pointer?.deallocate() }
        list.deinitialize(count: 1)
        storage.deallocate()
    }

    func samples(at index: Int) -> [Float] {
        guard let pointer = data[index] else { return [] }
        return (0..<(byteCounts[index] / MemoryLayout<Float>.size)).map {
            pointer.load(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self)
        }
    }

    func bytes(at index: Int) -> [UInt8] {
        guard let pointer = data[index] else { return [] }
        return Array(UnsafeRawBufferPointer(start: pointer, count: byteCounts[index]))
    }

    var hasIntactCanaries: Bool {
        data.indices.allSatisfy { index in
            guard let pointer = data[index] else { return true }
            let trailing = UnsafeRawBufferPointer(
                start: pointer.advanced(by: byteCounts[index]), count: trailingBytes[index].count
            )
            return Array(trailing) == trailingBytes[index]
        }
    }
}

private final class ApplicationVolumeDisposalStub: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@Sendable () -> Void] = []

    var pendingCount: Int { lock.withLock { pending.count } }

    func enqueue(_ work: @escaping @Sendable () -> Void) { lock.withLock { pending.append(work) } }

    func flush() {
        let work = lock.withLock {
            let work = pending
            pending.removeAll()
            return work
        }
        for disposal in work { disposal() }
    }
}
