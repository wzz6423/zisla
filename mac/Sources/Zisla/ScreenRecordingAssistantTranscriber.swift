import Foundation
import Speech
import ZislaCore

enum ScreenRecordingTranscriptionError: LocalizedError, Equatable {
    case invalidMedia
    case permissionDenied
    case onDeviceUnavailable
    case alreadyRunning
    case noSpeech
    case invalidTranscript
    case timedOut
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidMedia: AppLocalization.text("字幕转写需要可读取的本地音频或视频文件")
        case .permissionDenied:
            AppLocalization.text("未获得语音识别权限。请在系统设置的“隐私与安全性 > 语音识别”中允许 zisla。")
        case .onDeviceUnavailable: AppLocalization.text("此语言的本地语音识别不可用")
        case .alreadyRunning: AppLocalization.text("正在生成字幕，请等待完成或取消")
        case .noSpeech: AppLocalization.text("录屏中未识别到可用的语音")
        case .invalidTranscript: AppLocalization.text("语音识别返回了无效的字幕时间数据")
        case .timedOut: AppLocalization.text("字幕转写超时，请重试")
        case .recognitionFailed(let message): AppLocalization.text("字幕转写失败：%@", message)
        }
    }
}

@MainActor
final class ScreenRecordingTranscriber {
    struct Word: Equatable, Sendable {
        var start: Double
        var end: Double
        var text: String
    }

    typealias Completion = @Sendable (Result<[Word], any Error>) -> Void
    typealias Cancellation = @MainActor () -> Void

    @MainActor
    struct Dependencies {
        var authorizationStatus: () -> SFSpeechRecognizerAuthorizationStatus
        var requestAuthorization: (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void
        var onDeviceAvailable: (Locale) -> Bool
        var recognize: (URL, Locale, @escaping Completion) throws -> Cancellation
        var scheduleDeadline: (@escaping @MainActor () -> Void) -> Cancellation

        static var live: Self {
            .init(
                authorizationStatus: { SFSpeechRecognizer.authorizationStatus() },
                requestAuthorization: { ScreenRecordingTranscriber.requestAuthorization($0) },
                onDeviceAvailable: { locale in
                    guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
                    return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
                },
                recognize: { url, locale, completion in
                    guard let recognizer = SFSpeechRecognizer(locale: locale),
                          recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
                        throw ScreenRecordingTranscriptionError.onDeviceUnavailable
                    }
                    let request = ScreenRecordingTranscriber.makeRequest(url: url)
                    let task = ScreenRecordingTranscriber.startRecognition(
                        recognizer: recognizer, request: request, completion: completion
                    )
                    return { withExtendedLifetime(recognizer) { task.cancel() } }
                },
                scheduleDeadline: { completion in
                    let task = Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(600)) }
                        catch { return }
                        completion()
                    }
                    return { task.cancel() }
                }
            )
        }
    }

    private let dependencies: Dependencies
    private var activeID: UUID?
    private var authorizationID: UUID?
    private var continuation: CheckedContinuation<[RecordingCaption], any Error>?
    private var cancelRecognition: Cancellation?
    private var cancelDeadline: Cancellation?

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func transcribe(url: URL, locale: Locale) async throws -> [RecordingCaption] {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard activeID == nil else { throw ScreenRecordingTranscriptionError.alreadyRunning }
            guard url.isFileURL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  FileManager.default.isReadableFile(atPath: url.path) else {
                throw ScreenRecordingTranscriptionError.invalidMedia
            }
            let status = dependencies.authorizationStatus()
            if status != .authorized, status != .notDetermined { throw ScreenRecordingTranscriptionError.permissionDenied }
            guard dependencies.onDeviceAvailable(locale) else { throw ScreenRecordingTranscriptionError.onDeviceUnavailable }
            let captions = try await withCheckedThrowingContinuation { continuation in
                activeID = id
                self.continuation = continuation
                let deadline = dependencies.scheduleDeadline { [weak self] in
                    self?.finish(id: id, result: .failure(ScreenRecordingTranscriptionError.timedOut))
                }
                if activeID == id { cancelDeadline = deadline }
                else { deadline() }
                authorize(status: status, id: id, url: url, locale: locale)
            }
            try Task.checkCancellation()
            return captions
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(id: id, result: .failure(CancellationError()))
            }
        }
    }

    func cancel() {
        if let activeID { finish(id: activeID, result: .failure(CancellationError())) }
    }

    nonisolated static func makeRequest(url: URL) -> SFSpeechURLRecognitionRequest {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        return request
    }

    private func authorize(status: SFSpeechRecognizerAuthorizationStatus, id: UUID, url: URL, locale: Locale) {
        guard activeID == id else { return }
        if status == .authorized {
            recognize(id: id, url: url, locale: locale)
        } else {
            authorizationID = id
            dependencies.requestAuthorization { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self, self.authorizationID == id else { return }
                    self.authorizationID = nil
                    if status == .authorized { self.recognize(id: id, url: url, locale: locale) }
                    else { self.finish(id: id, result: .failure(ScreenRecordingTranscriptionError.permissionDenied)) }
                }
            }
        }
    }

    private func recognize(id: UUID, url: URL, locale: Locale) {
        do {
            let cancellation = try dependencies.recognize(url, locale) { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self, self.activeID == id else { return }
                    self.finish(id: id, result: result.flatMap { words in
                        Result { try ScreenRecordingCaptionFormatter.captions(from: words) }
                    })
                }
            }
            if activeID == id { cancelRecognition = cancellation }
            else { cancellation() }
        } catch {
            finish(id: id, result: .failure(error))
        }
    }

    private func finish(id: UUID, result: Result<[RecordingCaption], any Error>) {
        guard activeID == id else { return }
        let continuation = continuation
        let recognition = cancelRecognition
        let deadline = cancelDeadline
        activeID = nil
        authorizationID = nil
        self.continuation = nil
        cancelRecognition = nil
        cancelDeadline = nil
        recognition?()
        deadline?()
        continuation?.resume(with: result)
    }

    nonisolated private static func requestAuthorization(
        _ completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization(completion)
    }

    private static func startRecognition(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest,
        completion: @escaping Completion
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request, resultHandler: { @Sendable result, error in
            if let error {
                completion(.failure(ScreenRecordingTranscriptionError.recognitionFailed(error.localizedDescription)))
                return
            }
            guard let result, result.isFinal else { return }
            let transcription = result.bestTranscription
            completion(Result { try words(from: transcription.formattedString, segments: transcription.segments.map {
                .init(start: $0.timestamp, end: $0.timestamp + $0.duration,
                      location: $0.substringRange.location, length: $0.substringRange.length)
            }) })
        })
    }

    struct Segment: Sendable {
        var start: Double
        var end: Double
        var location: Int
        var length: Int
    }

    nonisolated static func words(from text: String, segments: [Segment]) throws -> [Word] {
        guard text.utf8.count <= 4_194_304, segments.count <= 100_000 else {
            throw ScreenRecordingTranscriptionError.invalidTranscript
        }
        let formatted = text as NSString
        var words: [Word] = []
        for (index, segment) in segments.enumerated() {
            let nextStart = index + 1 < segments.count ? segments[index + 1].location : formatted.length
            guard segment.location >= 0, segment.length > 0, segment.location <= formatted.length,
                  segment.length <= formatted.length - segment.location,
                  nextStart >= segment.location + segment.length, nextStart <= formatted.length else {
                throw ScreenRecordingTranscriptionError.invalidTranscript
            }
            let utf16 = text.utf16
            let start = utf16.index(utf16.startIndex, offsetBy: segment.location)
            let end = utf16.index(utf16.startIndex, offsetBy: nextStart)
            guard String.Index(start, within: text.unicodeScalars) != nil,
                  String.Index(end, within: text.unicodeScalars) != nil else {
                throw ScreenRecordingTranscriptionError.invalidTranscript
            }
            // Punctuation sits between Speech's word ranges, so include it without inventing word timings.
            let text = formatted.substring(with: NSRange(
                location: segment.location,
                length: nextStart - segment.location
            )).trimmingCharacters(in: .whitespacesAndNewlines)
            words.append(Word(start: segment.start, end: segment.end, text: text))
        }
        return words
    }
}

enum ScreenRecordingCaptionFormatter {
    static let maximumCharacters = 42
    static let maximumWords = 100_000
    static let maximumTranscriptCharacters = 1_000_000
    private static let maximumTranscriptBytes = 4_194_304
    private static let maximumSRTTime = 12_096_000_000.0
    private static let sentenceEndings = Set("。！？.!?；;")

    static func captions(from words: [ScreenRecordingTranscriber.Word]) throws -> [RecordingCaption] {
        guard words.count <= maximumWords else { throw ScreenRecordingTranscriptionError.invalidTranscript }
        let sorted = words.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        var captions: [RecordingCaption] = []
        var current: RecordingCaption?
        var previousEnd = 0.0
        var characters = 0
        var bytes = 0
        for word in sorted {
            bytes += word.text.utf8.count
            guard word.start.isFinite, word.end.isFinite, word.start >= previousEnd,
                  word.end > word.start, word.end <= 604_800, word.text.utf8.count <= 16_384,
                  bytes <= maximumTranscriptBytes, word.text.count <= 4_000 else {
                throw ScreenRecordingTranscriptionError.invalidTranscript
            }
            previousEnd = word.end
            let text = word.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            characters += text.count
            guard characters <= maximumTranscriptCharacters else {
                throw ScreenRecordingTranscriptionError.invalidTranscript
            }
            let chunks = textChunks(text)
            var consumed = 0
            for rawChunk in chunks {
                let start = word.start + (word.end - word.start) * Double(consumed) / Double(text.count)
                consumed += rawChunk.count
                let end = word.start + (word.end - word.start) * Double(consumed) / Double(text.count)
                guard end > start else { throw ScreenRecordingTranscriptionError.invalidTranscript }
                let chunk = rawChunk.trimmingCharacters(in: .whitespaces)
                let separator = current.map { Self.separator(between: $0.text, and: chunk) } ?? ""
                if let value = current,
                   value.text.count + separator.count + chunk.count > maximumCharacters
                    || start - value.end >= 0.8 || end - value.start > 6 {
                    captions.append(value)
                    current = nil
                }
                if var value = current {
                    value.text += separator + chunk
                    value.end = end
                    current = value
                } else {
                    current = .init(start: start, end: end, text: chunk)
                }
                if let last = chunk.last, sentenceEndings.contains(last), let value = current {
                    captions.append(value)
                    current = nil
                }
            }
        }
        if let current { captions.append(current) }
        guard captions.count <= 100_000 else { throw ScreenRecordingTranscriptionError.invalidTranscript }
        guard !captions.isEmpty else { throw ScreenRecordingTranscriptionError.noSpeech }
        return captions
    }

    static func exportSRT(captions: [RecordingCaption]) -> String {
        captions.filter {
            $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start
                && $0.end <= maximumSRTTime && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
            .enumerated().map { index, caption in
                let start = Int((caption.start * 1_000).rounded())
                let end = max(start + 1, Int((caption.end * 1_000).rounded()))
                let text = caption.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    .unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
                    .map(String.init).joined()
                return "\(index + 1)\n\(timestamp(start)) --> \(timestamp(end))\n\(text)\n"
            }.joined(separator: "\n")
    }

    private static func timestamp(_ milliseconds: Int) -> String {
        String(format: "%02d:%02d:%02d,%03d", milliseconds / 3_600_000,
               milliseconds / 60_000 % 60, milliseconds / 1_000 % 60, milliseconds % 1_000)
    }

    private static func textChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var chunk = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            chunk.append(character)
            let endsSentence = sentenceEndings.contains(character)
                && (character != "." || index + 1 == characters.count || characters[index + 1].isWhitespace)
            if chunk.count == maximumCharacters || endsSentence {
                chunks.append(chunk)
                chunk = ""
            }
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        return chunks
    }

    private static func separator(between left: String, and right: String) -> String {
        guard let last = left.last, let first = right.first else { return "" }
        if "，。！？、；：,.!?;:)]}）】」』".contains(first)
            || "([{（【「『".contains(last) || isCJK(last) || isCJK(first) { return "" }
        return " "
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            (0x3400...0x9FFF).contains($0.value) || (0x3040...0x30FF).contains($0.value)
                || (0x20000...0x3134F).contains($0.value)
        }
    }
}
