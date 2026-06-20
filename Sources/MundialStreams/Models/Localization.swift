import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case spanish = "es"
    case english = "en"
    case portuguese = "pt"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spanish: "Español"
        case .english: "English"
        case .portuguese: "Português"
        }
    }

    var shortTitle: String {
        switch self {
        case .spanish: "ES"
        case .english: "EN"
        case .portuguese: "PT"
        }
    }
}

enum L10n {
    static func text(_ key: Key, _ language: AppLanguage) -> String {
        switch language {
        case .spanish: spanish[key] ?? english[key] ?? key.rawValue
        case .english: english[key] ?? key.rawValue
        case .portuguese: portuguese[key] ?? english[key] ?? key.rawValue
        }
    }

    enum Key: String {
        case base
        case type
        case searchPlaceholder
        case refreshing
        case refresh
        case quit
        case sources
        case publicSources
        case featured
        case viewInPopup
        case reloadPopup
        case popOutWindow
        case window
        case copyURL
        case copyEmbed
        case updated
        case neverUpdated
        case publicSourcesFooter
        case noResults
        case refreshOrChangeFilter
        case reload
        case hidePlayer
        case source
        case urlCopied
        case embedCopied
        case settingsBody
        case events
        case links
        case replays
        case crackSubtitle
        case timSubtitle
        case footballStream
        case replay
    }

    private static let spanish: [Key: String] = [
        .base: "Base",
        .type: "Tipo",
        .searchPlaceholder: "Buscar partido, server o source",
        .refreshing: "Refrescando",
        .refresh: "Refrescar",
        .quit: "Salir",
        .sources: "Sources",
        .publicSources: "sources públicas",
        .featured: "Destacado",
        .viewInPopup: "Ver en popup",
        .reloadPopup: "Recargar popup",
        .popOutWindow: "Sacar a ventana",
        .window: "Ventana",
        .copyURL: "Copiar URL",
        .copyEmbed: "Copy embed",
        .updated: "Actualizado",
        .neverUpdated: "Sin refrescar",
        .publicSourcesFooter: "sources públicas",
        .noResults: "No hay resultados",
        .refreshOrChangeFilter: "Refresca o cambia el filtro.",
        .reload: "Recargar",
        .hidePlayer: "Ocultar reproductor",
        .source: "Source",
        .urlCopied: "URL copiada",
        .embedCopied: "Embed copiado",
        .settingsBody: "La app corre desde la barra de estado. Usa el icono de la barra para abrir el popup, refrescar fuentes y abrir streams en ventanas redimensionables.",
        .events: "Eventos",
        .links: "Links",
        .replays: "Replays",
        .crackSubtitle: "Soccer-stream + backup servers",
        .timSubtitle: "API pública de timstreams.net",
        .footballStream: "Stream de futbol",
        .replay: "Replay"
    ]

    private static let english: [Key: String] = [
        .base: "Base",
        .type: "Type",
        .searchPlaceholder: "Search match, server, or source",
        .refreshing: "Refreshing",
        .refresh: "Refresh",
        .quit: "Quit",
        .sources: "Sources",
        .publicSources: "public sources",
        .featured: "Featured",
        .viewInPopup: "View in popup",
        .reloadPopup: "Reload popup",
        .popOutWindow: "Pop out window",
        .window: "Window",
        .copyURL: "Copy URL",
        .copyEmbed: "Copy embed",
        .updated: "Updated",
        .neverUpdated: "Not refreshed",
        .publicSourcesFooter: "public sources",
        .noResults: "No results",
        .refreshOrChangeFilter: "Refresh or change the filter.",
        .reload: "Reload",
        .hidePlayer: "Hide player",
        .source: "Source",
        .urlCopied: "URL copied",
        .embedCopied: "Embed copied",
        .settingsBody: "The app runs from the macOS status bar. Use the status icon to open the popup, refresh sources, and open streams in resizable windows.",
        .events: "Events",
        .links: "Links",
        .replays: "Replays",
        .crackSubtitle: "Soccer-stream + backup servers",
        .timSubtitle: "Public timstreams.net API",
        .footballStream: "Football stream",
        .replay: "Replay"
    ]

    private static let portuguese: [Key: String] = [
        .base: "Base",
        .type: "Tipo",
        .searchPlaceholder: "Buscar partida, servidor ou fonte",
        .refreshing: "Atualizando",
        .refresh: "Atualizar",
        .quit: "Sair",
        .sources: "Fontes",
        .publicSources: "fontes públicas",
        .featured: "Destaque",
        .viewInPopup: "Ver no popup",
        .reloadPopup: "Recarregar popup",
        .popOutWindow: "Abrir em janela",
        .window: "Janela",
        .copyURL: "Copiar URL",
        .copyEmbed: "Copiar embed",
        .updated: "Atualizado",
        .neverUpdated: "Ainda não atualizado",
        .publicSourcesFooter: "fontes públicas",
        .noResults: "Sem resultados",
        .refreshOrChangeFilter: "Atualize ou altere o filtro.",
        .reload: "Recarregar",
        .hidePlayer: "Ocultar player",
        .source: "Fonte",
        .urlCopied: "URL copiada",
        .embedCopied: "Embed copiado",
        .settingsBody: "O app roda na barra de status do macOS. Use o ícone para abrir o popup, atualizar fontes e abrir streams em janelas redimensionáveis.",
        .events: "Eventos",
        .links: "Links",
        .replays: "Replays",
        .crackSubtitle: "Soccer-stream + servidores backup",
        .timSubtitle: "API pública do timstreams.net",
        .footballStream: "Stream de futebol",
        .replay: "Replay"
    ]
}

extension StreamProvider {
    func subtitle(language: AppLanguage) -> String {
        switch self {
        case .crackStreams: L10n.text(.crackSubtitle, language)
        case .timStreams: L10n.text(.timSubtitle, language)
        }
    }
}

extension CatalogKind {
    func title(language: AppLanguage) -> String {
        switch self {
        case .events: L10n.text(.events, language)
        case .channels: L10n.text(.links, language)
        case .replays: L10n.text(.replays, language)
        }
    }
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .spanish
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}
