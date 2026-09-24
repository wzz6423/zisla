// Adapted from upstream Antigravity quota RPC discovery; modified for bounded, cancellable Zisla requests.
// See Resources/ThirdPartyLicenses/AIQuota-LICENSE.txt.
import Darwin
import Foundation
import ZislaCore

struct AIQuotaAntigravityClient: Sendable {
    struct Candidate: Equatable, Sendable {
        let pid: Int32
        let token: String
    }

    let http: any AIQuotaHTTPClient
    var clock: @Sendable () -> Date = { Date() }
    var run: @Sendable (URL, [String]) async throws -> String = { executable, arguments in
        let output = try await AIAgentProcessRunner.run(executableURL: executable, arguments: arguments,
                timeout: 3, maximumOutputBytes: 1_024 * 1_024, maximumErrorBytes: 4_096)
        guard output.status == 0, !output.didTimeout else { throw AIQuotaError.clientUnavailable }
        return String(decoding: output.standardOutput, as: UTF8.self)
    }

    func read() async throws -> Data {
        let listing = try await run(URL(fileURLWithPath: "/bin/ps"), ["-U", "\(getuid())", "-ww", "-o", "pid=,command="])
        let candidates = Self.candidates(listing)
        guard !candidates.isEmpty else { throw AIQuotaError.clientUnavailable }
        var attempts = 0
        var failure = AIQuotaError.network
        discovery: for candidate in candidates.prefix(8) {
            let ports: [Int]
            do {
                let output = try await run(URL(fileURLWithPath: "/usr/sbin/lsof"), ["-nP", "-a", "-p", "\(candidate.pid)", "-iTCP", "-sTCP:LISTEN", "-F", "n"])
                ports = Self.ports(output)
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
            for port in ports.prefix(8) {
                guard attempts < 8 else { break discovery }
                attempts += 1
                try Task.checkCancellation()
                let url = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = Data("{}".utf8)
                request.timeoutInterval = 2
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(try AIQuotaRequestBuilder.header(candidate.token), forHTTPHeaderField: "x-codeium-csrf-token")
                do {
                    let data = try await http.data(for: request, trustLoopback: true)
                    _ = try AIQuotaResponseParser.parse(.antigravity, replies: ["main": data], now: clock())
                    return data
                } catch is CancellationError { throw CancellationError() }
                catch let error as AIQuotaError { failure = error }
                catch { failure = .network }
            }
        }
        throw failure
    }

    static func candidates(_ listing: String) -> [Candidate] {
        listing.split(separator: "\n").compactMap { line in
            guard (line.contains("/Antigravity.app/") || line.contains("/Antigravity IDE.app/")),
                  line.contains("/language_server") else { return nil }
            let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let first = words.first, let pid = Int32(first), pid > 0 else { return nil }
            let token: String?
            if let index = words.firstIndex(of: "--csrf_token"), words.indices.contains(index + 1) { token = words[index + 1] }
            else { token = words.first(where: { $0.hasPrefix("--csrf_token=") }).map { String($0.dropFirst(13)) } }
            guard let token, !token.isEmpty else { return nil }
            return Candidate(pid: pid, token: token)
        }
    }

    static func ports(_ listing: String) -> [Int] {
        var seen: Set<Int> = []
        return listing.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("n"), let last = line.split(separator: ":").last,
                  let port = Int(last), (1...65_535).contains(port), seen.insert(port).inserted else { return nil }
            return port
        }
    }
}
