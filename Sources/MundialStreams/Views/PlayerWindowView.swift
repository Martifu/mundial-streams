import SwiftUI

struct PlayerWindowView: View {
    @ObservedObject var session: StreamSession
    @State private var reloadToken = 0
    @State private var copiedMessage: String?

    private var language: AppLanguage { session.language }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .underWindowBackground)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                player
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.item.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(session.selectedSource.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                ForEach(session.item.publicSources) { source in
                    Button {
                        session.selectedSource = source
                    } label: {
                        Label(source.name, systemImage: source.id == session.selectedSource.id ? "checkmark" : "play")
                    }
                }
            } label: {
                Label(L10n.text(.source, language), systemImage: "dot.radiowaves.left.and.right")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                reloadToken += 1
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help(L10n.text(.reload, language))

            Button {
                copy(session.selectedSource.displayURL, message: L10n.text(.urlCopied, language))
            } label: {
                Image(systemName: "link")
            }
            .buttonStyle(.bordered)
            .help(L10n.text(.copyURL, language))

            Button {
                copy(session.selectedSource.embedCode, message: L10n.text(.embedCopied, language))
            } label: {
                Label(L10n.text(.copyEmbed, language), systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(.bordered)

            if let copiedMessage {
                Text(copiedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(12)
        .liquidGlassPanel(cornerRadius: 18, interactive: true)
    }

    private var player: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.92))
                .liquidGlassPanel(cornerRadius: 22)

            WebStreamView(url: session.selectedSource.url, reloadToken: reloadToken)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(_ value: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        withAnimation {
            copiedMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                withAnimation {
                    copiedMessage = nil
                }
            }
        }
    }
}
