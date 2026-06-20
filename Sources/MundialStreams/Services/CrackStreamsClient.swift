import Foundation

struct CrackStreamsClient: Sendable {
    private let basePageURL = URL(string: "https://crackstreams.ch/Soccer-stream/")!
    private let fallbackScheduleURL = URL(string: "https://crackstreams1.in/Soccer/")!

    func fetchCatalog() async throws -> CatalogSnapshot {
        let baseHTML = try await fetchHTML(basePageURL)
        let scheduleURL = Self.parseIframeURL(from: baseHTML, baseURL: basePageURL) ?? fallbackScheduleURL
        let scheduleHTML = try await fetchHTML(scheduleURL)

        let scrapedEvents = Self.parseEventCards(from: scheduleHTML, baseURL: scheduleURL)
        let events = await fetchEventItems(scrapedEvents)
        let channels = Self.parseFootballLinks(from: scheduleHTML, baseURL: scheduleURL)

        return CatalogSnapshot(
            events: events.sorted(by: Self.eventSort),
            channels: channels.sorted { $0.name < $1.name },
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

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CrackStreamsError.badStatus(http.statusCode, url)
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CrackStreamsError.invalidHTML(url)
        }
        return html
    }

    private func fetchEventItems(_ events: [ScrapedEvent]) async -> [StreamItem] {
        await withTaskGroup(of: StreamItem?.self) { group in
            for event in events {
                group.addTask {
                    let html = try? await fetchHTML(event.url)
                    let sources = html.map(Self.parseSources) ?? []
                    return Self.makeEventItem(event, sources: sources)
                }
            }

            var items: [StreamItem] = []
            for await item in group {
                if let item {
                    items.append(item)
                }
            }
            return items
        }
    }

    private static func parseIframeURL(from html: String, baseURL: URL) -> URL? {
        html.firstCapture(#"<iframe[^>]+src=["']([^"']+)["']"#)
            .flatMap { absoluteURL($0, baseURL: baseURL) }
    }

    private static func parseEventCards(from html: String, baseURL: URL) -> [ScrapedEvent] {
        html.captures(#"(?is)<a\s+([^>]*class=["'][^"']*\bevent-btn\b[^"']*["'][^>]*)>(.*?)</a>"#)
            .compactMap { captures in
                guard captures.count == 2,
                      let href = captures[0].attribute("href"),
                      let url = absoluteURL(href, baseURL: baseURL) else {
                    return nil
                }

                let body = captures[1]
                let title = body.firstCapture(#"(?is)<div\s+class=["']title["'][^>]*>(.*?)</div>"#)?
                    .strippingTags
                    .htmlDecoded
                    .normalizedWhitespace
                guard let title, !title.isEmpty else { return nil }

                let logoURL = body.firstCapture(#"(?is)<img[^>]+src=["']([^"']+)["']"#)
                    .flatMap { absoluteURL($0, baseURL: baseURL) }
                let utcDate = captures[0].attribute("data-utc").flatMap(Self.parseUTCDate)
                let status = captures[0].attribute("data-score")?.htmlDecoded.normalizedWhitespace

                return ScrapedEvent(
                    url: url,
                    name: title,
                    logoURL: logoURL,
                    sortDate: utcDate,
                    status: status
                )
            }
    }

    private static func parseFootballLinks(from html: String, baseURL: URL) -> [StreamItem] {
        html.captures(#"(?is)<a\s+([^>]*class=["'][^"']*\bcard\b(?![^"']*\bevent-btn\b)[^"']*["'][^>]*)>(.*?)</a>"#)
            .compactMap { captures in
                guard captures.count == 2,
                      let href = captures[0].attribute("href"),
                      let url = absoluteURL(href, baseURL: baseURL) else {
                    return nil
                }

                let body = captures[1]
                let title = body.firstCapture(#"(?is)<div\s+class=["']title["'][^>]*>(.*?)</div>"#)?
                    .strippingTags
                    .htmlDecoded
                    .normalizedWhitespace
                guard let title, !title.isEmpty else { return nil }

                let subtitle = body.firstCapture(#"(?is)<div\s+class=["']sub["'][^>]*>(.*?)</div>"#)?
                    .strippingTags
                    .htmlDecoded
                    .normalizedWhitespace
                let logoURL = body.firstCapture(#"(?is)<img[^>]+src=["']([^"']+)["']"#)
                    .flatMap { absoluteURL($0, baseURL: baseURL) }
                let source = StreamSource(name: title, url: url, isVIP: false)

                return StreamItem(
                    id: "link-\(url.absoluteString)",
                    slug: url.absoluteString,
                    name: title,
                    logoURL: logoURL,
                    kind: .channels,
                    genreID: nil,
                    genreName: subtitle ?? "Football stream",
                    timeText: nil,
                    dateText: nil,
                    sortDate: nil,
                    isVIP: false,
                    isFeatured: false,
                    sources: [source]
                )
            }
    }

    private static func parseSources(from html: String) -> [StreamSource] {
        let sources = html.captures(#"(?is)<button\s+([^>]*class=["'][^"']*\bserver-btn\b[^"']*["'][^>]*)>(.*?)</button>"#)
            .compactMap { captures -> StreamSource? in
                guard captures.count == 2,
                      let rawURL = captures[0].attribute("data-src"),
                      let url = URL(string: rawURL.htmlDecoded.normalizedWhitespace) else {
                    return nil
                }
                let name = captures[1]
                    .strippingTags
                    .htmlDecoded
                    .normalizedWhitespace
                    .nilIfEmpty ?? "Server"
                return StreamSource(name: name, url: url, isVIP: false)
            }

        return sources.removingDuplicateSources()
    }

    private static func makeEventItem(_ event: ScrapedEvent, sources: [StreamSource]) -> StreamItem {
        let effectiveSources = sources.isEmpty
            ? [StreamSource(name: "Event page", url: event.url, isVIP: false)]
            : sources

        return StreamItem(
            id: "event-\(event.url.absoluteString)",
            slug: event.url.absoluteString,
            name: event.name,
            logoURL: event.logoURL,
            kind: .events,
            genreID: nil,
            genreName: event.status ?? "Soccer",
            timeText: event.sortDate.map(Self.formatEventTime),
            dateText: nil,
            sortDate: event.sortDate,
            isVIP: false,
            isFeatured: true,
            sources: effectiveSources
        )
    }

    private static func eventSort(_ lhs: StreamItem, _ rhs: StreamItem) -> Bool {
        switch (lhs.sortDate, rhs.sortDate) {
        case let (left?, right?): left < right
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): lhs.name < rhs.name
        }
    }

    private static func parseUTCDate(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw)
    }

    private static func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        URL(string: raw.htmlDecoded, relativeTo: baseURL)?.absoluteURL
    }
}

enum CrackStreamsError: LocalizedError {
    case badStatus(Int, URL)
    case invalidHTML(URL)

    var errorDescription: String? {
        switch self {
        case .badStatus(let status, let url): "CrackStreams returned HTTP \(status) for \(url.host() ?? url.absoluteString)."
        case .invalidHTML(let url): "Could not decode HTML from \(url.absoluteString)."
        }
    }
}

private struct ScrapedEvent: Sendable {
    let url: URL
    let name: String
    let logoURL: URL?
    let sortDate: Date?
    let status: String?
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

    func attribute(_ name: String) -> String? {
        firstCapture(#"\#(name)\s*=\s*["']([^"']+)["']"#)
    }

    var htmlDecoded: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    var strippingTags: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    var normalizedWhitespace: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
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
