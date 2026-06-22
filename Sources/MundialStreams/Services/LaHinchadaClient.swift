import Foundation

struct LaHinchadaClient: Sendable {
    private let eventsURL = URL(string: "https://lahinchada.xyz/eventos/combined_events.json")!
    private let requestReferer = "https://lahinchada.xyz/eventos/"
    private let requestOrigin = "https://lahinchada.xyz"
    private let decoder = JSONDecoder()

    func fetchCatalog() async throws -> CatalogSnapshot {
        let events: [LaHinchadaEvent] = try await get(eventsURL)

        return CatalogSnapshot(
            events: Self.mapEvents(
                events,
                requestReferer: requestReferer,
                requestOrigin: requestOrigin
            ).sorted(by: Self.eventSort),
            channels: [],
            replays: [],
            fetchedAt: Date()
        )
    }

    private func get<Response: Decodable & Sendable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MundialStreams/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(requestReferer, forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LaHinchadaError.badStatus(http.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private static func mapEvents(
        _ events: [LaHinchadaEvent],
        requestReferer: String,
        requestOrigin: String
    ) -> [StreamItem] {
        events.enumerated().compactMap { index, event in
            let title = event.title.normalizedWhitespace
            guard !title.isEmpty else { return nil }

            let sources = event.opciones
                .sorted(by: optionSort)
                .compactMap { name, rawURL -> StreamSource? in
                    guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        return nil
                    }
                    return StreamSource(
                        name: name.normalizedWhitespace.nilIfEmpty ?? "Opcion",
                        url: url,
                        isVIP: false,
                        requestReferer: requestReferer,
                        requestOrigin: requestOrigin
                    )
                }
                .removingDuplicateSources()

            guard !sources.isEmpty else { return nil }

            let rawTime = event.time?.normalizedWhitespace.nilIfEmpty
            let displayTime = rawTime.map(adjustedDisplayTime)
            let channel = event.canalAsignado?.normalizedWhitespace.nilIfEmpty
            let status = event.status?.statusText
            let genreName = [channel, status].compactMap { $0 }.joined(separator: " - ").nilIfEmpty

            return StreamItem(
                id: "lahinchada-event-\(index)-\(rawTime ?? "sin-hora")-\(title)",
                slug: "https://lahinchada.xyz/eventos/",
                name: title,
                logoURL: nil,
                kind: .events,
                genreID: nil,
                genreName: genreName ?? event.category?.normalizedWhitespace.nilIfEmpty ?? "Eventos",
                timeText: displayTime,
                dateText: nil,
                sortDate: rawTime.flatMap(sortDate),
                isVIP: false,
                isFeatured: false,
                sources: sources
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

    private static func optionSort(
        _ lhs: Dictionary<String, String>.Element,
        _ rhs: Dictionary<String, String>.Element
    ) -> Bool {
        switch (lhs.key.trailingNumber, rhs.key.trailingNumber) {
        case let (left?, right?) where left != right:
            return left < right
        default:
            return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
        }
    }

    private static func adjustedDisplayTime(_ raw: String) -> String {
        guard let (hour, minute) = parseTime(raw) else { return raw }
        let adjustedHour = (hour + 23) % 24
        return String(format: "%02d:%02d", adjustedHour, minute)
    }

    private static func sortDate(_ raw: String) -> Date? {
        guard let (hour, minute) = parseTime(raw) else { return nil }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)
    }

    private static func parseTime(_ raw: String) -> (hour: Int, minute: Int)? {
        let parts = raw.split(separator: ":", maxSplits: 1).compactMap { Int($0) }
        guard parts.count == 2,
              (0...23).contains(parts[0]),
              (0...59).contains(parts[1]) else {
            return nil
        }
        return (parts[0], parts[1])
    }
}

enum LaHinchadaError: LocalizedError {
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badStatus(let status): "La Hinchada returned HTTP \(status)."
        }
    }
}

private struct LaHinchadaEvent: Decodable, Sendable {
    let title: String
    let time: String?
    let category: String?
    let status: String?
    let canalAsignado: String?
    let opciones: [String: String]

    private enum CodingKeys: String, CodingKey {
        case title
        case time
        case category
        case status
        case canalAsignado = "canal_asignado"
        case opciones
    }
}

private extension String {
    var normalizedWhitespace: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var trailingNumber: Int? {
        let digits = reversed().prefix { $0.isNumber }.reversed()
        return digits.isEmpty ? nil : Int(String(digits))
    }

    var statusText: String? {
        components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && $0.rangeOfCharacter(from: .letters) != nil }
            .joined(separator: " ")
            .normalizedWhitespace
            .nilIfEmpty
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
