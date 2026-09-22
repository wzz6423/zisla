import Foundation

public enum ClipboardAssistantRailwayURLResolver {
    public static func resolve(_ url: URL, session: URLSession = .shared) async throws -> URL {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard let number = items?.first(where: { $0.name == "station_train_code" })?.value,
              let date = items?.first(where: { $0.name == "date" })?.value else {
            throw URLError(.badURL)
        }
        var search = URLComponents(string: "https://search.12306.cn/search/v1/train/search")!
        search.queryItems = [
            URLQueryItem(name: "keyword", value: number),
            URLQueryItem(name: "date", value: date.replacingOccurrences(of: "-", with: "")),
        ]
        var request = URLRequest(url: search.url!)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(TrainSearch.self, from: data)
        guard payload.status,
              let train = payload.data?.first(where: { $0.station_train_code == number }),
              train.train_no.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil else {
            throw URLError(.resourceUnavailable)
        }
        var destination = URLComponents(string: "https://kyfw.12306.cn/otn/queryTrainInfo/init")!
        // 12306 reads these three values by position before automatically querying the timetable.
        destination.queryItems = [
            URLQueryItem(name: "train_no", value: train.train_no),
            URLQueryItem(name: "station_train_code", value: number),
            URLQueryItem(name: "date", value: date),
        ]
        return destination.url!
    }

    private struct TrainSearch: Decodable {
        let status: Bool
        let data: [Train]?
    }

    private struct Train: Decodable {
        let station_train_code: String
        let train_no: String
    }
}
