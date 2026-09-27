import Foundation
import Testing
import XCTest

@testable import ZislaKit

@Suite(.serialized)
struct ClipboardTranslationServiceTests {
    @Test
    func firstCompleteSuccessCancelsTheLoserWithoutWaitingForIt() async throws {
        let first = TranslationGate<String>()
        let loser = TranslationGate<String>()
        let timeout = TranslationGate<Void>(cooperatesWithCancellation: true)
        let service = ClipboardTranslationService(
            providers: [{ _, _ in try await first.wait() }, { _, _ in try await loser.wait() }],
            waitForTimeout: { try await timeout.wait() }
        )
        let completed = XCTestExpectation(description: "首个完整译文立即完成")
        let task = Task {
            defer { completed.fulfill() }
            return try await service.translate("source", targetLanguage: "zh-CN")
        }
        #expect(await XCTWaiter.fulfillment(of: [first.started, loser.started, timeout.started], timeout: 3) == .completed)
        await first.resolve(.success("  译文\n第二行  "))
        #expect(await XCTWaiter.fulfillment(of: [completed, loser.cancelled, timeout.cancelled], timeout: 3) == .completed)
        await loser.resolve(.success("迟到译文"))
        #expect(try await task.value == "  译文\n第二行  ")
    }

    @Test(arguments: [false, true])
    func failureAndEmptyOutputCannotBeatACompleteTranslation(emptyOutput: Bool) async throws {
        let service = ClipboardTranslationService(providers: [
            { _, _ in
                if emptyOutput { return " \n\t" }
                throw URLError(.timedOut)
            },
            { _, _ in "完整译文" },
        ])
        #expect(try await service.translate("source", targetLanguage: "zh-CN") == "完整译文")
    }

    @Test
    func allFailuresEndWithoutWaitingForTheTimeoutAndAdditionalProvidersCanWin() async throws {
        let timeout = TranslationGate<Void>(cooperatesWithCancellation: true)
        let service = ClipboardTranslationService(
            providers: [{ _, _ in throw URLError(.notConnectedToInternet) }, { _, _ in "" }],
            waitForTimeout: { try await timeout.wait() }
        )
        await #expect(throws: ClipboardTranslationError.unavailable) {
            try await service.translate("source", targetLanguage: "zh-CN")
        }
        #expect(await XCTWaiter.fulfillment(of: [timeout.cancelled], timeout: 3) == .completed)
        let systemOnly = ClipboardTranslationService(providers: [])
        #expect(try await systemOnly.translate("source", targetLanguage: "zh-CN", additionalProviders: [
            { _, _ in "系统译文" },
        ]) == "系统译文")
        await #expect(throws: ClipboardTranslationError.unavailable) {
            try await systemOnly.translate("source", targetLanguage: "zh-CN")
        }
    }

    @Test(arguments: [false, true])
    func timeoutAndCancellationDoNotWaitForAnUncooperativeProvider(cancel: Bool) async {
        let provider = TranslationGate<String>()
        let timeout = TranslationGate<Void>(cooperatesWithCancellation: true)
        let service = ClipboardTranslationService(
            providers: [{ _, _ in try await provider.wait() }],
            waitForTimeout: { try await timeout.wait() }
        )
        let completed = XCTestExpectation(description: "取消或超时结束请求")
        let task = Task {
            defer { completed.fulfill() }
            return try await service.translate("source", targetLanguage: "zh-CN")
        }
        #expect(await XCTWaiter.fulfillment(of: [provider.started, timeout.started], timeout: 3) == .completed)
        if cancel { task.cancel() } else { await timeout.resolve(.success(())) }
        #expect(await XCTWaiter.fulfillment(of: [completed, provider.cancelled], timeout: 3) == .completed)
        await provider.resolve(.success("不可返回的迟到译文"))
        switch await task.result {
        case .success: Issue.record("取消或超时不得返回译文")
        case .failure(let error):
            if cancel { #expect(error is CancellationError) }
            else { #expect(error as? ClipboardTranslationError == .unavailable) }
        }
    }

    @Test(arguments: ["", " \n\t"])
    func invalidInputsNeverStartAProvider(_ invalid: String) async {
        let service = ClipboardTranslationService(providers: [{ _, _ in
            Issue.record("无效输入不得触发翻译平台")
            return "unexpected"
        }])
        await #expect(throws: ClipboardTranslationError.invalidInput) {
            try await service.translate(invalid, targetLanguage: "zh-CN")
        }
        await #expect(throws: ClipboardTranslationError.invalidInput) {
            try await service.translate("valid source", targetLanguage: invalid)
        }
    }

    @Test
    func alreadyCancelledWorkNeverStartsAProvider() async {
        let service = ClipboardTranslationService(providers: [{ _, _ in
            Issue.record("取消的请求不得触发翻译平台")
            return "unexpected"
        }])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.translate("source", targetLanguage: "zh-CN")
        }
        switch await task.result {
        case .success: Issue.record("取消的请求不得成功")
        case .failure(let error): #expect(error is CancellationError)
        }
    }

    @Test
    func googleJoinsEverySegmentAndEncodesTextWithoutQueryInjection() async throws {
        let text = "Hello + world & q=INJECTED? # \"\n第二行"
        let session = session { _ in
            .body(#"[[["你好，","Hello",null,null],["完整世界。","world",null,null]],null,"en"]"#)
        }
        defer { TranslationURLProtocol.finish(session) }
        #expect(try await ClipboardTranslationService.google(text: text, targetLanguage: "zh-CN", session: session) == "你好，完整世界。")
        let request = try #require(TranslationURLProtocol.requests(for: session).first)
        #expect(request.url?.host == "translate.googleapis.com")
        #expect(request.url?.path == "/translate_a/single")
        #expect(Self.formQuery(request)["q"] == text)
        #expect(Self.formQuery(request)["tl"] == "zh-CN")
        #expect(Self.formQuery(request)["sl"] == "auto")
        #expect(Self.formQuery(request).count == 5)
        #expect(!request.httpShouldHandleCookies)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test(arguments: ["", "{}", "[]", "[[]]", "<html>blocked</html>", "[[[null]]]", #"[[["first"],[null]]]"#, #"[[["first"],[""]]]"#])
    func googleRejectsMissingOrPartialPayloads(_ body: String) async {
        let session = session { _ in .body(body) }
        defer { TranslationURLProtocol.finish(session) }
        await #expect(throws: (any Error).self) {
            try await ClipboardTranslationService.google(text: "source", targetLanguage: "zh-CN", session: session)
        }
    }

    @Test(arguments: [false, true])
    func myMemorySegmentsUTF8AndPreservesAllSourceWhitespace(whitespaceChunk: Bool) async throws {
        let prefix = whitespaceChunk
            ? "Hello world. This paragraph describes how we translate complete English sentences while keeping whitespace unchanged. "
                + String(repeating: " ", count: 1_200)
            : " \n\t"
        let text = prefix + String(repeating: "This is English text with + symbols & punctuation.\n", count: 35) + "\tEND. \n"
        let session = session { request in
            let query = Self.formQuery(request)["q"] ?? ""
            return .body(Self.myMemoryBody(query))
        }
        defer { TranslationURLProtocol.finish(session) }
        let translated = try await ClipboardTranslationService.myMemory(text: text, targetLanguage: "zh-CN", session: session)
        #expect(translated == text, "分段回拼不得丢字、丢换行或把加号改为空格")
        let requests = TranslationURLProtocol.requests(for: session)
        #expect(requests.count > 1)
        for request in requests {
            let query = Self.formQuery(request)
            let chunk = try #require(query["q"])
            #expect(chunk.utf8.count <= 500)
            #expect(query["langpair"] == "en|zh-CN")
            #expect(query.count == 2)
            #expect(!request.httpShouldHandleCookies)
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        }
    }

    @Test
    func myMemoryMatchesTheObservedPublicResponseAndPreservesLiteralEntities() async throws {
        let session = session { _ in
            .body(#"{"responseData":{"translatedText":"你好世界 &amp; literal","match":0.99},"quotaFinished":false,"mtLangSupported":null,"responseDetails":"","responseStatus":200,"responderId":null,"exception_code":null,"matches":[]}"#)
        }
        defer { TranslationURLProtocol.finish(session) }
        #expect(try await ClipboardTranslationService.myMemory(text: "Hello world.", targetLanguage: "zh-CN", session: session) == "你好世界 &amp; literal")
    }

    @Test(arguments: [
        ("这是一段简体中文，测试完整翻译结果，不要遗漏任何文字。", "zh-CN"),
        ("這是一段繁體中文，測試完整翻譯結果，不要遺漏任何文字。", "zh-TW"),
        ("This is a full English sentence for language recognition.", "en"),
    ])
    func myMemoryUsesAnExplicitSourceLanguage(_ source: (String, String)) async throws {
        let session = session { _ in .body(Self.myMemoryBody("translated")) }
        defer { TranslationURLProtocol.finish(session) }
        _ = try await ClipboardTranslationService.myMemory(text: source.0, targetLanguage: "ja", session: session)
        let request = try #require(TranslationURLProtocol.requests(for: session).first)
        #expect(Self.formQuery(request)["langpair"] == "\(source.1)|ja")
    }

    @Test(arguments: [204, 403, 429, 500, 503])
    func HTTPFailuresNeverBecomeTranslations(_ status: Int) async {
        let session = session { _ in .body(#"[[["not a success"]]]"#, status: status) }
        defer { TranslationURLProtocol.finish(session) }
        await #expect(throws: ClipboardTranslationError.invalidResponse) {
            try await ClipboardTranslationService.google(text: "Hello world.", targetLanguage: "zh-CN", session: session)
        }
    }

    @Test
    func everyTruncatedJSONPrefixFailsWithoutReturningPartialText() async {
        let response = #"[[["translated","source",null,null]],null,"en"]"#
        for length in 0..<response.utf8.count {
            let partial = String(decoding: Array(response.utf8.prefix(length)), as: UTF8.self)
            let session = session { _ in .body(partial) }
            defer { TranslationURLProtocol.finish(session) }
            await #expect(throws: (any Error).self) {
                try await ClipboardTranslationService.google(text: "Hello world.", targetLanguage: "zh-CN", session: session)
            }
        }
    }

    @Test(arguments: ["", "{}", #"{"responseData":{"translatedText":"partial"},"quotaFinished":true,"responseStatus":200}"#, #"{"responseData":{"translatedText":"error"},"quotaFinished":false,"responseStatus":403}"#, #"{"responseData":{"translatedText":" \n"},"quotaFinished":false,"responseStatus":200}"#])
    func myMemoryRejectsErrorsQuotasAndEmptyResults(_ body: String) async {
        let session = session { _ in .body(body) }
        defer { TranslationURLProtocol.finish(session) }
        await #expect(throws: (any Error).self) {
            try await ClipboardTranslationService.myMemory(text: "Hello world.", targetLanguage: "zh-CN", session: session)
        }
    }

    @Test
    func aFailedLaterChunkNeverReturnsTheTranslatedPrefix() async {
        let session = session { request in
            Self.formQuery(request)["q"]?.contains("SECOND") == true
                ? .body("", status: 429) : .body(Self.myMemoryBody("首段译文"))
        }
        defer { TranslationURLProtocol.finish(session) }
        let text = String(repeating: "First English sentence. ", count: 22) + "SECOND English sentence."
        await #expect(throws: ClipboardTranslationError.invalidResponse) {
            try await ClipboardTranslationService.myMemory(text: text, targetLanguage: "zh-CN", session: session)
        }
        #expect(TranslationURLProtocol.requests(for: session).count >= 2)
    }

    @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet])
    func aGoogleTransportFailureAllowsMyMemoryToWin(_ failure: URLError.Code) async throws {
        let session = session { request in
            request.url?.host == "translate.googleapis.com"
                ? .failure(failure) : .body(Self.myMemoryBody("你好世界"))
        }
        defer { TranslationURLProtocol.finish(session) }
        let translated = try await ClipboardTranslationService.live(session: session).translate("Hello world.", targetLanguage: "zh-CN")
        #expect(translated == "你好世界")
        #expect(Set(TranslationURLProtocol.requests(for: session).compactMap { $0.url?.host }) == ["translate.googleapis.com", "api.mymemory.translated.net"])
    }

    @Test
    func cancellingStopsTheActualURLSessionRequest() async {
        let started = XCTestExpectation(description: "请求已经进入 URLProtocol")
        let stopped = XCTestExpectation(description: "取消传递到底层 URLSession")
        let session = TranslationURLProtocol.session(
            didStart: { started.fulfill() },
            didStop: { stopped.fulfill() },
            handler: { _ in .suspended }
        )
        defer { TranslationURLProtocol.finish(session) }
        let task = Task {
            try await ClipboardTranslationService.google(text: "Hello world.", targetLanguage: "zh-CN", session: session)
        }
        #expect(await XCTWaiter.fulfillment(of: [started], timeout: 3) == .completed)
        task.cancel()
        switch await task.result {
        case .success: Issue.record("已取消网络请求不得返回译文")
        case .failure(let error): #expect((error as? URLError)?.code == .cancelled)
        }
        #expect(await XCTWaiter.fulfillment(of: [stopped], timeout: 3) == .completed)
    }

    @Test
    func chunkingIsLosslessAndByteBoundedForSeededUnicodeInputs() throws {
        var state: UInt64 = 0xCAFE
        let alphabet = ["中", "🙂", "e\u{301}", "👨‍👩‍👧‍👦", " ", "\n", "x", "+", "العربية"]
        for _ in 0..<64 {
            var text = ""
            for _ in 0..<120 {
                state = state &* 6_364_136_223_846_793_005 &+ 1
                text += alphabet[Int((state >> 32) % UInt64(alphabet.count))]
            }
            let chunks = try ClipboardTranslationService.chunks(text, maximumBytes: 500)
            #expect(chunks.joined() == text)
            #expect(chunks.allSatisfy { !$0.isEmpty && $0.utf8.count <= 500 })
        }
        #expect(try ClipboardTranslationService.chunks("", maximumBytes: 500).isEmpty)
        #expect(try ClipboardTranslationService.chunks(String(repeating: "a", count: 500), maximumBytes: 500).count == 1)
        for maximum in [0, 1, 2] {
            #expect(throws: ClipboardTranslationError.invalidInput) {
                try ClipboardTranslationService.chunks("中", maximumBytes: maximum)
            }
        }
        #expect(throws: ClipboardTranslationError.invalidInput) {
            try ClipboardTranslationService.chunks("e" + String(repeating: "\u{301}", count: 300), maximumBytes: 500)
        }
    }

    private func session(handler: @escaping @Sendable (URLRequest) -> TranslationURLProtocol.Response) -> URLSession {
        TranslationURLProtocol.session(handler: handler)
    }

    private static func formQuery(_ request: URLRequest) -> [String: String] {
        let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedQuery } ?? ""
        return Dictionary(uniqueKeysWithValues: query.split(separator: "&").map { item in
            let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let value = parts.count == 2 ? String(parts[1]) : ""
            return (String(parts[0]), value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "")
        })
    }

    private static func myMemoryBody(_ text: String) -> String {
        let payload: [String: Any] = ["responseData": ["translatedText": text], "quotaFinished": false, "responseStatus": 200]
        return String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
    }
}

private actor TranslationGate<Value: Sendable> {
    nonisolated let started = XCTestExpectation(description: "异步依赖已经开始")
    nonisolated let cancelled = XCTestExpectation(description: "异步依赖收到取消")
    private let cooperatesWithCancellation: Bool
    private var result: Result<Value, any Error>?
    private var continuation: CheckedContinuation<Value, any Error>?

    init(cooperatesWithCancellation: Bool = false) {
        self.cooperatesWithCancellation = cooperatesWithCancellation
    }

    func wait() async throws -> Value {
        try await withTaskCancellationHandler {
            started.fulfill()
            return try await withCheckedThrowingContinuation { continuation in
                if let result { continuation.resume(with: result) }
                else { self.continuation = continuation }
            }
        } onCancel: {
            self.cancelled.fulfill()
            if self.cooperatesWithCancellation {
                Task { await self.resolve(.failure(CancellationError())) }
            }
        }
    }

    func resolve(_ result: Result<Value, any Error>) {
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
    }
}

private final class TranslationURLProtocol: URLProtocol, @unchecked Sendable {
    enum Response: Sendable {
        case body(String, status: Int = 200)
        case failure(URLError.Code)
        case suspended
    }

    private final class Fixture: @unchecked Sendable {
        let handler: @Sendable (URLRequest) -> Response
        let didStart: (@Sendable () -> Void)?
        let didStop: (@Sendable () -> Void)?
        let lock = NSLock()
        var requests: [URLRequest] = []

        init(
            didStart: (@Sendable () -> Void)?,
            didStop: (@Sendable () -> Void)?,
            handler: @escaping @Sendable (URLRequest) -> Response
        ) {
            self.didStart = didStart
            self.didStop = didStop
            self.handler = handler
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: Fixture] = [:]
    private let fixtureLock = NSLock()
    private var fixture: Fixture?

    static func session(
        didStart: (@Sendable () -> Void)? = nil,
        didStop: (@Sendable () -> Void)? = nil,
        handler: @escaping @Sendable (URLRequest) -> Response
    ) -> URLSession {
        let id = UUID().uuidString
        lock.withLock { fixtures[id] = Fixture(didStart: didStart, didStop: didStop, handler: handler) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Translation-Test": id]
        return URLSession(configuration: configuration)
    }

    static func requests(for session: URLSession) -> [URLRequest] {
        guard let fixture = lock.withLock({ fixtures[sessionID(session)] }) else { return [] }
        return fixture.lock.withLock { fixture.requests }
    }

    static func finish(_ session: URLSession) {
        session.invalidateAndCancel()
        _ = lock.withLock { fixtures.removeValue(forKey: sessionID(session)) }
    }

    private static func sessionID(_ session: URLSession) -> String {
        session.configuration.httpAdditionalHeaders!["X-Translation-Test"] as! String
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Translation-Test"),
              let fixture = Self.lock.withLock({ Self.fixtures[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        fixtureLock.withLock { self.fixture = fixture }
        fixture.lock.withLock { fixture.requests.append(request) }
        fixture.didStart?()
        switch fixture.handler(request) {
        case .body(let body, let status):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code): client?.urlProtocol(self, didFailWithError: URLError(code))
        case .suspended: break
        }
    }

    override func stopLoading() { fixtureLock.withLock { fixture }?.didStop?() }
}
