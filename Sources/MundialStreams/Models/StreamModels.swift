import Foundation

enum StreamProvider: String, CaseIterable, Identifiable, Sendable {
    case crackStreams
    case timStreams
    case laHinchada
    case laCancha

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crackStreams: "CrackStreams"
        case .timStreams: "TimStreams"
        case .laHinchada: "La Hinchada"
        case .laCancha: "La Cancha"
        }
    }

    var subtitle: String {
        switch self {
        case .crackStreams: "Soccer-stream + backup servers"
        case .timStreams: "timstreams.net API publica"
        case .laHinchada: "lahinchada.xyz eventos"
        case .laCancha: "lacancha.tv en vivo"
        }
    }

    var systemImage: String {
        switch self {
        case .crackStreams: "soccerball"
        case .timStreams: "play.tv.fill"
        case .laHinchada: "sportscourt.fill"
        case .laCancha: "rectangle.split.2x1.fill"
        }
    }

    var availableKinds: [CatalogKind] {
        switch self {
        case .crackStreams: [.events, .channels]
        case .timStreams: [.events, .channels, .replays]
        case .laHinchada: [.events]
        case .laCancha: [.events, .channels]
        }
    }
}

enum CatalogKind: String, CaseIterable, Identifiable, Sendable {
    case events
    case channels
    case replays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .events: "Eventos"
        case .channels: "Links"
        case .replays: "Replays"
        }
    }

    var systemImage: String {
        switch self {
        case .events: "bolt.fill"
        case .channels: "link.circle.fill"
        case .replays: "arrow.counterclockwise.circle.fill"
        }
    }
}

struct StreamSource: Identifiable, Hashable, Sendable {
    let name: String
    let url: URL
    let isVIP: Bool
    let requestReferer: String?
    let requestOrigin: String?

    init(name: String, url: URL, isVIP: Bool, requestReferer: String? = nil, requestOrigin: String? = nil) {
        self.name = name
        self.url = url
        self.isVIP = isVIP
        self.requestReferer = requestReferer
        self.requestOrigin = requestOrigin
    }

    var id: String { "\(name)|\(url.absoluteString)" }
    var isPublic: Bool { !isVIP }
    var displayURL: String { url.absoluteString }
    var embedCode: String { EmbedCodeBuilder.iframe(for: url) }
}

struct StreamItem: Identifiable, Hashable, Sendable {
    let id: String
    let slug: String
    let name: String
    let logoURL: URL?
    let kind: CatalogKind
    let genreID: Int?
    let genreName: String?
    let timeText: String?
    let dateText: String?
    let sortDate: Date?
    let isVIP: Bool
    let isFeatured: Bool
    let sources: [StreamSource]

    var publicSources: [StreamSource] {
        sources.filter(\.isPublic)
    }

    var subtitle: String {
        if let genreName, let timeText {
            return "\(genreName) - \(timeText)"
        }
        if let genreName {
            return genreName
        }
        if let dateText {
            return dateText
        }
        return "\(publicSources.count) sources"
    }

    var searchBlob: String {
        ([name, genreName, timeText, dateText] + publicSources.map(\.name))
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }
}

struct CatalogSnapshot: Sendable {
    let events: [StreamItem]
    let channels: [StreamItem]
    let replays: [StreamItem]
    let fetchedAt: Date

    static let empty = CatalogSnapshot(events: [], channels: [], replays: [], fetchedAt: .distantPast)

    func items(for kind: CatalogKind) -> [StreamItem] {
        switch kind {
        case .events: events
        case .channels: channels
        case .replays: replays
        }
    }

    var allPublicSources: [StreamSource] {
        (events + channels + replays).flatMap(\.publicSources)
    }
}
