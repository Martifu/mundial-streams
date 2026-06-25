import Foundation

struct LaCanchaClient: Sendable {
    private let homeURL = URL(string: "https://lacancha.tv/es")!
    private let liveURL = URL(string: "https://lacancha.tv/es/en-vivo")!
    private let doubleURL = URL(string: "https://lacancha.tv/es/doble")!
    private let origin = "https://lacancha.tv"
    private let decoder = JSONDecoder()

    func fetchCatalog() async throws -> CatalogSnapshot {
        async let liveHTML = fetchHTML(liveURL)
        async let doubleHTML = fetchHTML(doubleURL)

        let (live, double) = try await (liveHTML, doubleHTML)
        let liveCatalog = try parseLiveCatalog(from: live)
        let doubleItem = try parseDoubleItem(from: double)

        return CatalogSnapshot(
            events: liveCatalog.events.sorted(by: Self.eventSort),
            channels: [doubleItem] + liveCatalog.channels,
            replays: [],
            fetchedAt: Date()
        )
    }

    private func fetchHTML(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("MundialStreams/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(homeURL.absoluteString, forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LaCanchaError.badStatus(http.statusCode, url)
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw LaCanchaError.invalidHTML(url)
        }
        return html
    }

    private func parseLiveCatalog(from html: String) throws -> (events: [StreamItem], channels: [StreamItem]) {
        let flight = try Self.decodeNextFlight(from: html)
        let matchesJSON = try Self.extractJSONArray(named: "matches", from: flight)
        let streamsJSON = try Self.extractJSONArray(named: "streams", from: flight)
        let matches = try decoder.decode([LaCanchaMatch].self, from: Data(matchesJSON.utf8))
        let streams = try decoder.decode([LaCanchaStream].self, from: Data(streamsJSON.utf8))
        let featuredIndex = Self.featuredMatchIndex(from: flight) ?? 0

        let featuredEvent: StreamItem? = matches[safe: featuredIndex].flatMap { match in
            makeEventItem(match, streams: streams, sourceReferer: liveURL.absoluteString)
        }

        let liveChannel = StreamItem(
            id: "lacancha-live-page",
            slug: liveURL.absoluteString,
            name: "La Cancha - En vivo",
            logoURL: nil,
            kind: .channels,
            genreID: nil,
            genreName: "lacancha.tv",
            timeText: nil,
            dateText: nil,
            sortDate: nil,
            isVIP: false,
            isFeatured: false,
            sources: [
                StreamSource(
                    name: "Abrir pagina en vivo",
                    url: liveURL,
                    isVIP: false,
                    requestReferer: homeURL.absoluteString,
                    requestOrigin: origin
                )
            ]
        )

        return (featuredEvent.map { [$0] } ?? [], [liveChannel])
    }

    private func parseDoubleItem(from html: String) throws -> StreamItem {
        let flight = try Self.decodeNextFlight(from: html)
        let cellsJSON = try Self.extractJSONArray(named: "cells", from: flight)
        let cells = try decoder.decode([LaCanchaCell].self, from: Data(cellsJSON.utf8))
        guard !cells.isEmpty else {
            throw LaCanchaError.missingData("double cells")
        }

        let matches = cells.map(\.match)
        let title = "Pantalla dividida"
        let matchSummary = matches.map(\.displayName).joined(separator: " + ").nilIfEmpty
        let firstKickoff = matches.compactMap(\.sortDate).min()
        let directStreams = cells
            .flatMap { cell in
                if case let .list(streams) = cell.streams {
                    return streams
                }
                return []
            }
            .removingDuplicateStreams()

        let sources = [
            StreamSource(
                name: "Pantalla dividida (/es/doble)",
                url: doubleURL,
                isVIP: false,
                requestReferer: homeURL.absoluteString,
                requestOrigin: origin
            )
        ] + makeSources(from: directStreams, referer: doubleURL.absoluteString)

        return StreamItem(
            id: "lacancha-double",
            slug: doubleURL.absoluteString,
            name: title,
            logoURL: nil,
            kind: .channels,
            genreID: nil,
            genreName: matchSummary ?? "Dos partidos simultaneos",
            timeText: firstKickoff.map(Self.formatEventTime),
            dateText: nil,
            sortDate: firstKickoff,
            isVIP: false,
            isFeatured: true,
            sources: sources.removingDuplicateSources()
        )
    }

    private func makeEventItem(_ match: LaCanchaMatch, streams: [LaCanchaStream], sourceReferer: String) -> StreamItem? {
        let sources = makeSources(from: streams, referer: sourceReferer)
        guard !sources.isEmpty else { return nil }

        return StreamItem(
            id: "lacancha-event-\(match.id)",
            slug: liveURL.absoluteString,
            name: match.displayName,
            logoURL: match.homeFlagURL ?? match.awayFlagURL,
            kind: .events,
            genreID: nil,
            genreName: match.detailText,
            timeText: match.sortDate.map(Self.formatEventTime),
            dateText: nil,
            sortDate: match.sortDate,
            isVIP: false,
            isFeatured: match.status.lowercased() == "live",
            sources: sources
        )
    }

    private func makeSources(from streams: [LaCanchaStream], referer: String) -> [StreamSource] {
        streams.compactMap { stream in
            guard let url = URL(string: stream.embedURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            return StreamSource(
                name: stream.displayName,
                url: url,
                isVIP: false,
                requestReferer: referer,
                requestOrigin: origin
            )
        }
        .removingDuplicateSources()
    }

    private static func eventSort(_ lhs: StreamItem, _ rhs: StreamItem) -> Bool {
        switch (lhs.sortDate, rhs.sortDate) {
        case let (left?, right?): left < right
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): lhs.name < rhs.name
        }
    }

    private static func decodeNextFlight(from html: String) throws -> String {
        let chunks = html.captures(#"self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)"#)
        let decoded = try chunks.compactMap(\.first).map { raw in
            let json = "\"\(raw)\""
            return try JSONDecoder().decode(String.self, from: Data(json.utf8))
        }
        let flight = decoded.joined()
        guard !flight.isEmpty else {
            throw LaCanchaError.missingData("Next flight payload")
        }
        return flight
    }

    private static func extractJSONArray(named key: String, from text: String) throws -> String {
        let marker = "\"\(key)\":["
        guard let markerRange = text.range(of: marker) else {
            throw LaCanchaError.missingData(key)
        }
        return try extractBalancedJSON(from: text, at: text.index(before: markerRange.upperBound))
    }

    private static func extractBalancedJSON(from text: String, at start: String.Index) throws -> String {
        var index = start
        var depth = 0
        var isInString = false
        var isEscaped = false

        while index < text.endIndex {
            let char = text[index]

            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if char == "\\" {
                    isEscaped = true
                } else if char == "\"" {
                    isInString = false
                }
            } else {
                if char == "\"" {
                    isInString = true
                } else if char == "[" || char == "{" {
                    depth += 1
                } else if char == "]" || char == "}" {
                    depth -= 1
                    if depth == 0 {
                        let end = text.index(after: index)
                        return String(text[start..<end])
                    }
                }
            }

            index = text.index(after: index)
        }

        throw LaCanchaError.missingData("balanced JSON")
    }

    private static func featuredMatchIndex(from text: String) -> Int? {
        text.firstCapture(#""featuredMatch":"\$[^"]*:matches:(\d+)""#).flatMap(Int.init)
    }

    private static func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

enum LaCanchaError: LocalizedError {
    case badStatus(Int, URL)
    case invalidHTML(URL)
    case missingData(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let status, let url): "La Cancha returned HTTP \(status) for \(url.host() ?? url.absoluteString)."
        case .invalidHTML(let url): "Could not decode HTML from \(url.absoluteString)."
        case .missingData(let field): "Could not find La Cancha \(field) in the page payload."
        }
    }
}

private struct LaCanchaMatch: Decodable, Sendable {
    let id: String
    let competition: String?
    let stage: String?
    let homeTeam: String
    let awayTeam: String
    let homeFlag: String?
    let awayFlag: String?
    let kickoffAt: String?
    let status: String
    let homeScore: Int?
    let awayScore: Int?
    let timeElapsed: Int?
    let venueName: String?
    let venueCity: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case competition
        case stage
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case homeFlag = "home_flag"
        case awayFlag = "away_flag"
        case kickoffAt = "kickoff_at"
        case status
        case homeScore = "home_score"
        case awayScore = "away_score"
        case timeElapsed = "time_elapsed"
        case venueName = "venue_name"
        case venueCity = "venue_city"
    }

    var displayName: String {
        "\(homeTeam.localizedTeamName) vs. \(awayTeam.localizedTeamName)"
    }

    var detailText: String {
        [
            competition?.normalizedWhitespace.nilIfEmpty,
            stage?.normalizedWhitespace.nilIfEmpty,
            scoreText,
            venueText
        ]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    var scoreText: String? {
        if let homeScore, let awayScore {
            if let timeElapsed {
                return "\(homeScore)-\(awayScore) \(timeElapsed)'"
            }
            return "\(homeScore)-\(awayScore)"
        }
        return status.normalizedWhitespace.nilIfEmpty
    }

    var venueText: String? {
        [venueName?.normalizedWhitespace.nilIfEmpty, venueCity?.normalizedWhitespace.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: ", ")
            .nilIfEmpty
    }

    var sortDate: Date? {
        guard let kickoffAt else { return nil }
        return ISO8601DateFormatter().date(from: kickoffAt)
    }

    var homeFlagURL: URL? {
        homeFlag.flatMap(URL.init(string:))
    }

    var awayFlagURL: URL? {
        awayFlag.flatMap(URL.init(string:))
    }
}

private struct LaCanchaStream: Decodable, Hashable, Sendable {
    let id: String
    let embedName: String
    let embedURL: String
    let channel: LaCanchaChannel?

    private enum CodingKeys: String, CodingKey {
        case id
        case embedName = "embed_name"
        case embedURL = "embed_url"
        case channel
    }

    var displayName: String {
        embedName.normalizedWhitespace.nilIfEmpty
            ?? channel?.name.normalizedWhitespace.nilIfEmpty
            ?? "La Cancha"
    }
}

private struct LaCanchaChannel: Decodable, Hashable, Sendable {
    let name: String
    let slug: String?
}

private struct LaCanchaCell: Decodable, Sendable {
    let match: LaCanchaMatch
    let streams: LaCanchaStreams
}

private enum LaCanchaStreams: Decodable, Sendable {
    case list([LaCanchaStream])
    case reference(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let streams = try? container.decode([LaCanchaStream].self) {
            self = .list(streams)
        } else {
            self = .reference(try container.decode(String.self))
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    func firstCapture(_ pattern: String) -> String? {
        captures(pattern).first?.first
    }

    func captures(_ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let fullRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: fullRange).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: self) else {
                    return nil
                }
                return String(self[range])
            }
        }
    }

    var normalizedWhitespace: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var localizedTeamName: String {
        [
            "Cape Verde Islands": "Cabo Verde",
            "Curaçao": "Curazao",
            "Germany": "Alemania",
            "Ivory Coast": "Costa de Marfil",
            "Netherlands": "Paises Bajos",
            "Türkiye": "Turquia",
            "USA": "EE.UU."
        ][self] ?? self
    }
}

private extension Array where Element == StreamSource {
    func removingDuplicateSources() -> [StreamSource] {
        var seen = Set<String>()
        return filter { source in
            let key = "\(source.name)|\(source.url.absoluteString)"
            return seen.insert(key).inserted
        }
    }
}

private extension Array where Element == LaCanchaStream {
    func removingDuplicateStreams() -> [LaCanchaStream] {
        var seen = Set<String>()
        return filter { stream in
            seen.insert(stream.embedURL).inserted
        }
    }
}
