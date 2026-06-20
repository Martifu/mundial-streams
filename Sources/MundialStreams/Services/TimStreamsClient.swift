import Foundation

struct TimStreamsClient: Sendable {
    private let baseURL = URL(string: "https://api.nuevasantino.xyz")!
    private let decoder = JSONDecoder()

    func fetchCatalog() async throws -> CatalogSnapshot {
        async let eventsResponse: LiveUpcomingResponse = get("/api/live-upcoming")
        async let channelsResponse: ChannelsResponse = get("/api/channels")
        async let replaysResponse: ReplaysResponse = get("/api/replays")

        let (events, channels, replays) = try await (eventsResponse, channelsResponse, replaysResponse)

        return CatalogSnapshot(
            events: Self.mapEvents(events.events, genres: events.genres).sorted(by: Self.eventSort),
            channels: Self.mapChannels(channels.channels, genres: channels.genres).sorted { $0.name < $1.name },
            replays: Self.mapReplays(replays.replays).sorted(by: Self.replaySort),
            fetchedAt: Date()
        )
    }

    private func get<Response: Decodable & Sendable>(_ path: String) async throws -> Response {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MundialStreams/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TimStreamsError.badStatus(http.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private static func mapEvents(_ events: [APIEvent], genres: [String: String]) -> [StreamItem] {
        events.compactMap { event in
            let sources = mapSources(event.streams)
            guard !sources.isEmpty else { return nil }

            let genreName = event.genre.flatMap { genres[String($0)] }
            let sortDate = parseEastern(event.time)
            return StreamItem(
                id: "tim-event-\(event.url)",
                slug: event.url,
                name: event.name,
                logoURL: URL(string: event.logo.htmlDecoded),
                kind: .events,
                genreID: event.genre,
                genreName: genreName,
                timeText: event.time.map { formatEventTime($0) },
                dateText: nil,
                sortDate: sortDate,
                isVIP: event.vip ?? false,
                isFeatured: event.featured ?? false,
                sources: sources
            )
        }
    }

    private static func mapChannels(_ channels: [APIChannel], genres: [String: String]) -> [StreamItem] {
        channels.compactMap { channel in
            let sources = mapSources(channel.streams)
            guard !sources.isEmpty else { return nil }

            let genreName = channel.genre.flatMap { genres[String($0)] }
            return StreamItem(
                id: "tim-channel-\(channel.url)",
                slug: channel.url,
                name: channel.name,
                logoURL: URL(string: channel.logo.htmlDecoded),
                kind: .channels,
                genreID: channel.genre,
                genreName: genreName,
                timeText: nil,
                dateText: nil,
                sortDate: nil,
                isVIP: channel.vip ?? false,
                isFeatured: false,
                sources: sources
            )
        }
    }

    private static func mapReplays(_ replays: [APIReplay]) -> [StreamItem] {
        replays.compactMap { replay in
            let sources = mapSources(replay.streams)
            guard !sources.isEmpty else { return nil }

            return StreamItem(
                id: "tim-replay-\(replay.url)",
                slug: replay.url,
                name: replay.name,
                logoURL: URL(string: replay.logo.htmlDecoded),
                kind: .replays,
                genreID: nil,
                genreName: "Replay",
                timeText: nil,
                dateText: replay.date,
                sortDate: parseReplayDate(replay.date),
                isVIP: replay.vip ?? false,
                isFeatured: false,
                sources: sources
            )
        }
    }

    private static func mapSources(_ sources: [APIStream]) -> [StreamSource] {
        sources.compactMap { source in
            guard let url = URL(string: source.url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            return StreamSource(
                name: source.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Source",
                url: url,
                isVIP: source.vip ?? false
            )
        }
    }

    private static func eventSort(_ lhs: StreamItem, _ rhs: StreamItem) -> Bool {
        switch (lhs.sortDate, rhs.sortDate) {
        case let (left?, right?): left < right
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): lhs.name < rhs.name
        }
    }

    private static func replaySort(_ lhs: StreamItem, _ rhs: StreamItem) -> Bool {
        switch (lhs.sortDate, rhs.sortDate) {
        case let (left?, right?): left > right
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): lhs.name < rhs.name
        }
    }

    private static func parseEastern(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm"
        ]
        for pattern in patterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "America/New_York")
            formatter.dateFormat = pattern
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        return nil
    }

    private static func parseReplayDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.date(from: raw)
    }

    private static func formatEventTime(_ raw: String) -> String {
        guard let date = parseEastern(raw) else {
            return raw.replacingOccurrences(of: "T", with: " ")
        }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

enum TimStreamsError: LocalizedError {
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badStatus(let status): "TimStreams API returned HTTP \(status)."
        }
    }
}

private struct LiveUpcomingResponse: Decodable, Sendable {
    let events: [APIEvent]
    let genres: [String: String]
}

private struct ChannelsResponse: Decodable, Sendable {
    let channels: [APIChannel]
    let genres: [String: String]
}

private struct ReplaysResponse: Decodable, Sendable {
    let replays: [APIReplay]
}

private struct APIEvent: Decodable, Sendable {
    let url: String
    let name: String
    let logo: String
    let genre: Int?
    let time: String?
    let vip: Bool?
    let featured: Bool?
    let streams: [APIStream]
}

private struct APIChannel: Decodable, Sendable {
    let url: String
    let name: String
    let logo: String
    let genre: Int?
    let vip: Bool?
    let streams: [APIStream]
}

private struct APIReplay: Decodable, Sendable {
    let url: String
    let name: String
    let logo: String
    let date: String?
    let vip: Bool?
    let streams: [APIStream]
}

private struct APIStream: Decodable, Sendable {
    let name: String
    let url: String
    let vip: Bool?
}

private extension String {
    var htmlDecoded: String {
        replacingOccurrences(of: "&amp;", with: "&")
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
