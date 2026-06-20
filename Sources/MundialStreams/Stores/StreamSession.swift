import Foundation

@MainActor
final class StreamSession: ObservableObject {
    let item: StreamItem
    let language: AppLanguage
    @Published var selectedSource: StreamSource

    init(item: StreamItem, selectedSource: StreamSource, language: AppLanguage) {
        self.item = item
        self.selectedSource = selectedSource
        self.language = language
    }
}
