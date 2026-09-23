import Foundation
import Testing
@testable import ZislaKit

@Suite(.serialized)
struct ClipboardAssistantRailwayURLResolverTests {
    private let actionURL = URL(string: "https://kyfw.12306.cn/otn/queryTrainInfo/init?station_train_code=G123&date=2026-09-22")!

    @Test func exactNumberWinsOverPrefixMatchesAndUsesTheRequiredParameterOrder() async throws {
        let session = session(body: #"{"status":true,"data":[{"station_train_code":"G1230","train_no":"240000G12301"},{"station_train_code":"G123","train_no":"240000G12300"}]}"#)
        defer { session.invalidateAndCancel() }
        let destination = try await ClipboardAssistantRailwayURLResolver.resolve(actionURL, session: session)
        #expect(destination.absoluteString == "https://kyfw.12306.cn/otn/queryTrainInfo/init?train_no=240000G12300&station_train_code=G123&date=2026-09-22")
        let request = try #require(RailwayURLProtocol.request)
        #expect(request.url?.absoluteString == "https://search.12306.cn/search/v1/train/search?keyword=G123&date=20260922")
        #expect(request.httpMethod == "GET")
        #expect(request.httpShouldHandleCookies == false)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.timeoutInterval > 0 && request.timeoutInterval <= 15)
    }

    @Test(arguments: [
        #"{"status":false,"data":[{"station_train_code":"G123","train_no":"240000G12300"}]}"#,
        #"{"status":true,"data":[]}"#,
        #"{"status":true,"data":[{"station_train_code":"G1230","train_no":"240000G12301"}]}"#,
        #"{"status":true,"data":[{"station_train_code":"G123","train_no":""}]}"#,
        #"{"status":true,"data":[{"station_train_code":"G123","train_no":"240000G12300&date=2000-01-01"}]}"#,
    ])
    func unavailableOrUnsafeMatchesDoNotProduceAFallbackPage(_ body: String) async {
        let session = session(body: body)
        defer { session.invalidateAndCancel() }
        await #expect(throws: URLError(.resourceUnavailable)) {
            try await ClipboardAssistantRailwayURLResolver.resolve(actionURL, session: session)
        }
    }

    @Test(arguments: ["{}", "<html>blocked</html>", #"{"status":true,"data":[{"station_train_code":"G123"}]}"#])
    func malformedPayloadsFailWithoutOpeningAHomePage(_ body: String) async {
        let session = session(body: body)
        defer { session.invalidateAndCancel() }
        await #expect(throws: DecodingError.self) {
            try await ClipboardAssistantRailwayURLResolver.resolve(actionURL, session: session)
        }
    }

    @Test func serverErrorsCannotBecomeSuccessfulQueries() async {
        let session = session(body: #"{"status":true,"data":[{"station_train_code":"G123","train_no":"240000G12300"}]}"#, status: 503)
        defer { session.invalidateAndCancel() }
        await #expect(throws: URLError(.badServerResponse)) {
            try await ClipboardAssistantRailwayURLResolver.resolve(actionURL, session: session)
        }
    }

    @Test(arguments: [URLError.Code.timedOut, .cancelled, .notConnectedToInternet])
    func transportFailuresRemainFailuresAndAreRetryable(_ code: URLError.Code) async throws {
        let session = session(body: #"{"status":true,"data":[{"station_train_code":"G123","train_no":"240000G12300"}]}"#)
        defer { session.invalidateAndCancel() }
        RailwayURLProtocol.failure = code
        do {
            _ = try await ClipboardAssistantRailwayURLResolver.resolve(actionURL, session: session)
            Issue.record("网络失败不应返回可打开的链接")
        } catch {
            #expect((error as? URLError)?.code == code)
        }
        RailwayURLProtocol.failure = nil
        let destination = try await ClipboardAssistantRailwayURLResolver.resolve(actionURL, session: session)
        #expect(destination.host == "kyfw.12306.cn")
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingTheTaskStopsTheInFlightRequestAndAllowsRetry() async throws {
        let session = session(body: #"{"status":true,"data":[{"station_train_code":"G123","train_no":"240000G12300"}]}"#)
        let started = AsyncStream<Void>.makeStream()
        let stopped = AsyncStream<Void>.makeStream()
        RailwayURLProtocol.suspended = true
        RailwayURLProtocol.didStart = { started.continuation.yield(()) }
        RailwayURLProtocol.didStop = { stopped.continuation.yield(()) }
        let operation = Task {
            defer { started.continuation.finish() }
            return try await ClipboardAssistantRailwayURLResolver.resolve(actionURL, session: session)
        }
        defer {
            operation.cancel()
            session.invalidateAndCancel()
            started.continuation.finish()
            stopped.continuation.finish()
            RailwayURLProtocol.didStart = nil
            RailwayURLProtocol.didStop = nil
        }
        var starts = started.stream.makeAsyncIterator()
        let didStart: Void? = await starts.next()
        try #require(didStart != nil, "取消前必须已经开始真实的URLSession请求")
        operation.cancel()
        do {
            _ = try await operation.value
            Issue.record("已取消的查询不应返回可打开的链接")
        } catch {
            #expect((error as? URLError)?.code == .cancelled)
        }
        var stops = stopped.stream.makeAsyncIterator()
        let didStop: Void? = await stops.next()
        #expect(didStop != nil, "Task.cancel必须停止底层请求")
        RailwayURLProtocol.suspended = false
        let retry = try await ClipboardAssistantRailwayURLResolver.resolve(actionURL, session: session)
        #expect(retry.host == "kyfw.12306.cn")
    }

    @Test(arguments: ["https://kyfw.12306.cn/otn/queryTrainInfo/init", "https://kyfw.12306.cn/otn/queryTrainInfo/init?station_train_code=G123"])
    func incompleteActionsFailBeforeAnyNetworkRequest(_ value: String) async throws {
        let session = session(body: "{}")
        defer { session.invalidateAndCancel() }
        await #expect(throws: URLError(.badURL)) {
            try await ClipboardAssistantRailwayURLResolver.resolve(try #require(URL(string: value)), session: session)
        }
        #expect(RailwayURLProtocol.request == nil)
    }

    private func session(body: String, status: Int = 200) -> URLSession {
        RailwayURLProtocol.request = nil
        RailwayURLProtocol.body = body
        RailwayURLProtocol.status = status
        RailwayURLProtocol.failure = nil
        RailwayURLProtocol.suspended = false
        RailwayURLProtocol.didStart = nil
        RailwayURLProtocol.didStop = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RailwayURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class RailwayURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var request: URLRequest?
    nonisolated(unsafe) static var body = ""
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var failure: URLError.Code?
    nonisolated(unsafe) static var suspended = false
    nonisolated(unsafe) static var didStart: (@Sendable () -> Void)?
    nonisolated(unsafe) static var didStop: (@Sendable () -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.request = request
        if Self.suspended {
            Self.didStart?()
            return
        }
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { Self.didStop?() }
}
