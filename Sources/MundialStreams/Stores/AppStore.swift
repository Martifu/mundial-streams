import AppKit
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot: CatalogSnapshot = .empty
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedProvider: StreamProvider = .crackStreams {
        didSet { handleProviderChange() }
    }
    @Published var selectedKind: CatalogKind = .events {
        didSet { ensureSelection() }
    }
    @Published var selectedItemID: StreamItem.ID?
    @Published var selectedSourceID: StreamSource.ID?
    @Published var searchText = "" {
        didSet { ensureSelection() }
    }
    @Published var selectedLanguage: AppLanguage = .spanish {
        didSet { UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "appLanguage") }
    }

    private let crackStreamsClient = CrackStreamsClient()
    private let timStreamsClient = TimStreamsClient()
    private var streamWindows: [StreamWindowController] = []

    init() {
        if let rawLanguage = UserDefaults.standard.string(forKey: "appLanguage"),
           let language = AppLanguage(rawValue: rawLanguage) {
            selectedLanguage = language
        }
        Task { await refresh() }
    }

    var itemsForSelectedKind: [StreamItem] {
        snapshot.items(for: selectedKind)
    }

    var availableKinds: [CatalogKind] {
        selectedProvider.availableKinds
    }

    var filteredItems: [StreamItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return itemsForSelectedKind }
        return itemsForSelectedKind.filter { $0.searchBlob.contains(query) }
    }

    var selectedItem: StreamItem? {
        if let selectedItemID,
           let item = filteredItems.first(where: { $0.id == selectedItemID }) {
            return item
        }
        return filteredItems.first
    }

    var selectedSource: StreamSource? {
        guard let item = selectedItem else { return nil }
        if let selectedSourceID,
           let source = item.publicSources.first(where: { $0.id == selectedSourceID }) {
            return source
        }
        return item.publicSources.first
    }

    var lastUpdatedText: String {
        guard snapshot.fetchedAt != .distantPast else { return L10n.text(.neverUpdated, selectedLanguage) }
        return snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)
    }

    func refresh() async {
        let provider = selectedProvider
        isLoading = true
        errorMessage = nil
        do {
            let nextSnapshot = try await fetchCatalog(for: provider)
            guard provider == selectedProvider else { return }
            snapshot = nextSnapshot
            ensureSelection()
        } catch {
            guard provider == selectedProvider else { return }
            errorMessage = error.localizedDescription
        }
        if provider == selectedProvider {
            isLoading = false
        }
    }

    func select(_ item: StreamItem) {
        selectedKind = item.kind
        selectedItemID = item.id
        selectedSourceID = item.publicSources.first?.id
    }

    func select(_ source: StreamSource) {
        selectedSourceID = source.id
    }

    func copySelectedURL() {
        guard let source = selectedSource else { return }
        copy(source.displayURL)
    }

    func copySelectedEmbed() {
        guard let source = selectedSource else { return }
        copy(source.embedCode)
    }

    func openSelectedSource() {
        guard let item = selectedItem, let source = selectedSource else { return }
        open(source, for: item)
    }

    func open(_ source: StreamSource, for item: StreamItem) {
        let session = StreamSession(item: item, selectedSource: source, language: selectedLanguage)
        let controller = StreamWindowController(session: session)
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.streamWindows.removeAll { $0 === controller }
        }
        streamWindows.append(controller)
        controller.show()
    }

    private func ensureSelection() {
        if !availableKinds.contains(selectedKind) {
            selectedKind = availableKinds.first ?? .events
            return
        }

        let visibleItems = filteredItems
        if let selectedItemID,
           let item = itemsForSelectedKind.first(where: { $0.id == selectedItemID }),
           !item.publicSources.isEmpty {
            if selectedSourceID == nil || !item.publicSources.contains(where: { $0.id == selectedSourceID }) {
                selectedSourceID = item.publicSources.first?.id
            }
            return
        }

        selectedItemID = visibleItems.first?.id
        selectedSourceID = visibleItems.first?.publicSources.first?.id
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func handleProviderChange() {
        snapshot = .empty
        selectedItemID = nil
        selectedSourceID = nil
        if !availableKinds.contains(selectedKind) {
            selectedKind = availableKinds.first ?? .events
        }
        Task { await refresh() }
    }

    private func fetchCatalog(for provider: StreamProvider) async throws -> CatalogSnapshot {
        switch provider {
        case .crackStreams:
            try await crackStreamsClient.fetchCatalog()
        case .timStreams:
            try await timStreamsClient.fetchCatalog()
        }
    }
}
