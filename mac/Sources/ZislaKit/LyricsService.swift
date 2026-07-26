import Foundation

public struct SyncedLyrics: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var time: Double
        public var text: String

        public init(time: Double, text: String) {
            self.time = time
            self.text = text
        }
    }

    public var lines: [Line]

    public init(lines: [Line]) {
        self.lines = lines.sorted { lhs, rhs in
            lhs.time == rhs.time ? lhs.text < rhs.text : lhs.time < rhs.time
        }
    }

    public func currentLine(at elapsedTime: Double) -> String? {
        lines.last(where: { $0.time <= elapsedTime })?.text
    }

    public func currentLineProgress(at elapsedTime: Double, duration: Double?) -> Double? {
        guard let index = lines.lastIndex(where: { $0.time <= elapsedTime }) else { return nil }
        let startTime = lines[index].time
        let endTime = lines.indices.contains(index + 1) ? lines[index + 1].time : duration
        guard let endTime, endTime > startTime else { return nil }
        return min(max((elapsedTime - startTime) / (endTime - startTime), 0), 1)
    }

    static func parse(_ value: String?) -> SyncedLyrics? {
        guard let value, !value.isEmpty else { return nil }
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        var parsed: [Line] = []

        for rawLine in value.split(whereSeparator: \Character.isNewline) {
            let line = String(rawLine)
            let range = NSRange(line.startIndex..., in: line)
            let matches = expression.matches(in: line, range: range)
            guard let lastMatch = matches.last,
                  let textStart = Range(lastMatch.range, in: line)?.upperBound else { continue }
            let text = line[textStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            for match in matches {
                guard let minutesRange = Range(match.range(at: 1), in: line),
                      let secondsRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minutesRange]),
                      let seconds = Double(line[secondsRange]) else { continue }
                var fraction = 0.0
                if let fractionRange = Range(match.range(at: 3), in: line) {
                    let digits = line[fractionRange]
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                parsed.append(Line(time: minutes * 60 + seconds + fraction, text: text))
            }
        }

        guard !parsed.isEmpty else { return nil }
        return SyncedLyrics(lines: parsed)
    }
}

struct LyricsTrackIdentity: Hashable, Sendable {
    var title: String
    var artist: String
    var duration: Double?

    init?(title: String, artist: String, duration: Double?) {
        let normalizedTitle = LyricsService.normalized(title)
        let normalizedArtist = LyricsService.normalized(artist)
        guard !normalizedTitle.isEmpty, !normalizedArtist.isEmpty else { return nil }
        self.title = normalizedTitle
        self.artist = normalizedArtist
        self.duration = duration
    }
}

/// Lyrics search result, also carrying the full artist name from the API.
/// MediaRemote usually returns only the first artist; this supplements the display
/// with the complete artist list returned by the API.
struct LyricsSearchResult: Sendable {
    var lyrics: SyncedLyrics?
    var artistName: String?
}

actor LyricsService {
    private struct LRCLIBTrack: Decodable, Sendable {
        var trackName: String
        var artistName: String
        var duration: Double?
        var syncedLyrics: String?
    }

    private struct NetEaseSearchResponse: Decodable, Sendable {
        struct Result: Decodable, Sendable {
            var songs: [Song]?
        }

        struct Song: Decodable, Sendable {
            struct Artist: Decodable, Sendable {
                var name: String
            }

            var id: Int
            var name: String
            var duration: Double?
            var artists: [Artist]
        }

        var result: Result?
    }

    private struct NetEaseLyricsResponse: Decodable, Sendable {
        struct Lyrics: Decodable, Sendable {
            var lyric: String?
        }

        var code: Int?
        var lrc: Lyrics?
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            self.session = URLSession(configuration: configuration)
        }
    }

    func lyrics(title: String, artist: String, duration: Double?) async -> LyricsSearchResult {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = components?.url else {
            return await netEaseLyrics(title: title, artist: artist, duration: duration)
        }

        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse,
               http.statusCode == 200 {
                let selection = try Self.selectLyricsTrack(
                   from: data,
                   title: title,
                   artist: artist,
                   duration: duration
                )
                if selection.lyrics != nil {
                    return selection
                }
            }
        } catch {}

        return await netEaseLyrics(title: title, artist: artist, duration: duration)
    }

    private func netEaseLyrics(
        title: String,
        artist: String,
        duration: Double?
    ) async -> LyricsSearchResult {
        var search = URLComponents(string: "https://music.163.com/api/search/get/web")
        search?.queryItems = [
            URLQueryItem(name: "s", value: "\(title) \(artist)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "offset", value: "0"),
        ]
        guard let searchURL = search?.url,
              let searchData = await netEaseData(from: searchURL),
              let selection = try? Self.selectNetEaseSong(
                  from: searchData,
                  title: title,
                  artist: artist,
                  duration: duration
              ) else { return LyricsSearchResult(lyrics: nil, artistName: nil) }

        var lyric = URLComponents(string: "https://music.163.com/api/song/lyric")
        lyric?.queryItems = [
            URLQueryItem(name: "id", value: "\(selection.songID)"),
            URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "kv", value: "1"),
            URLQueryItem(name: "tv", value: "-1"),
        ]
        guard let lyricURL = lyric?.url,
              let lyricData = await netEaseData(from: lyricURL) else {
            return LyricsSearchResult(lyrics: nil, artistName: selection.artistName)
        }
        let lyrics = try? Self.parseNetEaseLyrics(from: lyricData)
        return LyricsSearchResult(lyrics: lyrics, artistName: selection.artistName)
    }

    private func netEaseData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("zisla/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    nonisolated static func selectLyrics(
        from data: Data,
        title: String,
        artist: String,
        duration: Double?
    ) throws -> SyncedLyrics? {
        try selectLyricsTrack(from: data, title: title, artist: artist, duration: duration).lyrics
    }

    nonisolated static func selectLyricsTrack(
        from data: Data,
        title: String,
        artist: String,
        duration: Double?
    ) throws -> LyricsSearchResult {
        let candidates = try JSONDecoder().decode([LRCLIBTrack].self, from: data)
        let normalizedTitle = normalized(title)
        let normalizedArtist = normalized(artist)
        let matches = candidates.filter { candidate in
            normalized(candidate.trackName) == normalizedTitle
                && artistMatches(candidate.artistName, query: normalizedArtist)
                && durationMatches(candidate.duration, expected: duration)
                && SyncedLyrics.parse(candidate.syncedLyrics) != nil
        }
        let selected = matches.min { lhs, rhs in
            durationDistance(lhs.duration, expected: duration)
                < durationDistance(rhs.duration, expected: duration)
        }
        return LyricsSearchResult(
            lyrics: SyncedLyrics.parse(selected?.syncedLyrics),
            artistName: selected?.artistName
        )
    }

    /// MediaRemote usually returns only the first artist, while LRCLIB may return "Artist1, Artist2".
    /// Tries an exact match first, then splits the candidate by separators and matches each part.
    nonisolated static func artistMatches(_ candidateArtist: String, query: String) -> Bool {
        if normalized(candidateArtist) == query { return true }
        let separators = CharacterSet(charactersIn: ",&/、;|")
        return candidateArtist
            .components(separatedBy: separators)
            .contains { normalized($0) == query }
    }

    private struct NetEaseSongSelection: Sendable {
        var songID: Int
        var artistName: String?
    }

    nonisolated static func selectNetEaseSongID(
        from data: Data,
        title: String,
        artist: String,
        duration: Double?
    ) throws -> Int? {
        try selectNetEaseSong(from: data, title: title, artist: artist, duration: duration)?.songID
    }

    /// Selects the song while also returning the full artist list (the `artists` array from the NetEase API).
    nonisolated private static func selectNetEaseSong(
        from data: Data,
        title: String,
        artist: String,
        duration: Double?
    ) throws -> NetEaseSongSelection? {
        let response = try JSONDecoder().decode(NetEaseSearchResponse.self, from: data)
        let normalizedTitle = normalized(title)
        let normalizedArtist = normalized(artist)
        let matches = (response.result?.songs ?? []).filter { song in
            let artistNames = song.artists.map(\.name)
            let artistMatches = normalized(artistNames.joined()) == normalizedArtist
                || artistNames.contains { normalized($0) == normalizedArtist }
            return normalized(song.name) == normalizedTitle
                && artistMatches
                && durationMatches(song.duration.map { $0 / 1_000 }, expected: duration)
        }
        guard let selected = matches.min(by: { lhs, rhs in
            durationDistance(lhs.duration.map { $0 / 1_000 }, expected: duration)
                < durationDistance(rhs.duration.map { $0 / 1_000 }, expected: duration)
        }) else { return nil }

        let artistName = selected.artists.map(\.name)
            .joined(separator: ", ")
        return NetEaseSongSelection(
            songID: selected.id,
            artistName: artistName.isEmpty ? nil : artistName
        )
    }

    nonisolated static func parseNetEaseLyrics(from data: Data) throws -> SyncedLyrics? {
        let response = try JSONDecoder().decode(NetEaseLyricsResponse.self, from: data)
        guard response.code == nil || response.code == 200 else { return nil }
        return SyncedLyrics.parse(response.lrc?.lyric)
    }

    nonisolated static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    nonisolated private static func durationMatches(_ value: Double?, expected: Double?) -> Bool {
        guard let value, let expected, value > 0, expected > 0 else { return true }
        return abs(value - expected) <= max(3, expected * 0.03)
    }

    nonisolated private static func durationDistance(_ value: Double?, expected: Double?) -> Double {
        guard let value, let expected else { return 0 }
        return abs(value - expected)
    }
}
