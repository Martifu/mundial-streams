import SwiftUI

struct SettingsView: View {
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.spanish.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .spanish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Mundial Streams", systemImage: "play.tv")
                .font(.headline)
            Text(L10n.text(.settingsBody, language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
    }
}
