import Darwin
import Foundation
import ZislaCore

public enum AIModelDiscoveryError: LocalizedError, Sendable {
    case invalidEndpoint(String)
    case invalidResponse
    case http(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "端点地址无效"
        case .invalidResponse: "端点返回了无法识别的模型目录"
        case let .http(statusCode): "读取模型目录失败（HTTP \(statusCode)）"
        }
    }
}

/// Reads the model catalog from a running local service or an OpenAI-compatible service without changing the workspace's chat or key-routing state.
public struct AIModelDiscoveryService: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func models(for endpoint: AIEndpoint, apiKey: String? = nil) async throws -> [AIDiscoveredModel] {
        let url = try modelsURL(for: endpoint)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authorization = Self.authorizationHeader(for: apiKey) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIModelDiscoveryError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIModelDiscoveryError.http(statusCode: http.statusCode)
        }

        let names: [String]
        switch endpoint.kind {
        case .ollama:
            names = try JSONDecoder().decode(OllamaTagsResponse.self, from: data).models.map(\.name)
        case .openAICompatible:
            names = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data).data.map(\.id)
        }
        let normalizedNames = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let uniqueNames = Set(normalizedNames)
        return uniqueNames
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { AIDiscoveredModel(name: $0) }
    }

    static func authorizationHeader(for apiKey: String?) -> String? {
        guard let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            return nil
        }
        return "Bearer \(apiKey)"
    }

    private func modelsURL(for endpoint: AIEndpoint) throws -> URL {
        var url = try baseURL(from: endpoint)
        switch endpoint.kind {
        case .ollama:
            if url.lastPathComponent.lowercased() == "v1" {
                url.deleteLastPathComponent()
            }
            url.appendPathComponent("api")
            url.appendPathComponent("tags")
        case .openAICompatible:
            let pathComponents = url.path.split(separator: "/")
            if !pathComponents.contains(where: { $0.lowercased() == "v1" }) {
                url.appendPathComponent("v1", isDirectory: true)
            }
            url.appendPathComponent("models")
        }
        return url
    }

    private func baseURL(from endpoint: AIEndpoint) throws -> URL {
        let source = endpoint.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: source),
              let url = components.url,
              AIEndpointSecurity.permits(url) else {
            throw AIModelDiscoveryError.invalidEndpoint(source)
        }
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }
}

public enum AIHardwareProfileDetector {
    public static func current() -> AIHardwareProfile {
        let hardware = SystemHardwareInfoReader.read()
        return AIHardwareProfile(
            machineName: Host.current().localizedName ?? "此 Mac",
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            cpuName: hardware.cpuName ?? sysctlString(named: "machdep.cpu.brand_string"),
            cpuCoreCount: hardware.cpuCoreCount,
            cpuPerformanceCoreCount: hardware.cpuPerformanceCoreCount,
            cpuEfficiencyCoreCount: hardware.cpuEfficiencyCoreCount,
            gpuName: hardware.gpuName,
            gpuCoreCount: hardware.gpuCoreCount
        )
    }

    private static func sysctlString(named name: String) -> String? {
        var size: size_t = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(size))
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.dropLast(), as: UTF8.self)
    }
}

private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        var name: String
    }

    var models: [Model]
}

private struct OpenAIModelsResponse: Decodable {
    struct Model: Decodable {
        var id: String
    }

    var data: [Model]
}
