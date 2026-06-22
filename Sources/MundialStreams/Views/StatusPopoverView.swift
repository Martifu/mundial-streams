import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var store: AppStore
    @State private var isPlayerVisible = false
    @State private var inlineReloadToken = 0

    private var language: AppLanguage { store.selectedLanguage }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                header
                filters
                content
                footer
            }
            .padding(16)
        }
        .frame(minWidth: 960, minHeight: 780)
        .onChange(of: store.selectedProvider) { _, _ in
            isPlayerVisible = false
            inlineReloadToken += 1
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .liquidGlassPanel(cornerRadius: 14, interactive: true)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedProvider.title)
                    .font(.title3.weight(.semibold))
                Text(store.selectedProvider.subtitle(language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Language", selection: $store.selectedLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.shortTitle).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .help("Language")

            Button {
                Task { await store.refresh() }
            } label: {
                Label(
                    store.isLoading ? L10n.text(.refreshing, language) : L10n.text(.refresh, language),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.bordered)
            .disabled(store.isLoading)

            Button(L10n.text(.quit, language)) {
                NSApp.terminate(nil)
            }
            .buttonStyle(.bordered)
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker(L10n.text(.base, language), selection: $store.selectedProvider) {
                ForEach(StreamProvider.allCases) { provider in
                    Label(provider.title, systemImage: provider.systemImage)
                        .tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 420)

            Picker(L10n.text(.type, language), selection: $store.selectedKind) {
                ForEach(store.availableKinds) { kind in
                    Label(kind.title(language: language), systemImage: kind.systemImage)
                        .tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            TextField(L10n.text(.searchPlaceholder, language), text: $store.searchText)
                .textFieldStyle(.roundedBorder)

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var content: some View {
        HStack(spacing: 14) {
            itemList
                .frame(width: 330)
            detailPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(store.selectedKind.title(language: language), systemImage: store.selectedKind.systemImage)
                    .font(.headline)
                Spacer()
                Text("\(store.filteredItems.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.filteredItems) { item in
                        StreamItemRow(
                            item: item,
                            isSelected: item.id == store.selectedItem?.id
                        ) {
                            store.select(item)
                        }
                    }
                }
                .padding(2)
            }
        }
        .padding(12)
        .liquidGlassPanel(cornerRadius: 18)
    }

    @ViewBuilder
    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = store.errorMessage {
                errorBanner(error)
            }

            if let item = store.selectedItem {
                selectedItemHeader(item)
                if isPlayerVisible, let source = store.selectedSource {
                    inlinePlayer(source)
                }
                sourceList(item)
                Spacer(minLength: 0)
                actionBar(item)
            } else {
                emptyState
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassPanel(cornerRadius: 18)
    }

    private func errorBanner(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func selectedItemHeader(_ item: StreamItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            LogoView(url: item.logoURL, size: 72)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    if item.isFeatured {
                        Text(L10n.text(.featured, language))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.18), in: Capsule())
                    }
                }

                Text(item.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Label("\(item.publicSources.count) \(L10n.text(.publicSources, language))", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func sourceList(_ item: StreamItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(.sources, language))
                .font(.headline)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(item.publicSources) { source in
                        SourceRow(
                            source: source,
                            isSelected: source.id == store.selectedSource?.id
                        ) {
                            store.select(source)
                        } open: {
                            showInPopup(source)
                        } copyEmbed: {
                            store.select(source)
                            store.copySelectedEmbed()
                        }
                        .environment(\.appLanguage, language)
                    }
                }
                .padding(2)
            }
        }
    }

    @ViewBuilder
    private func actionBar(_ item: StreamItem) -> some View {
        if store.selectedSource != nil {
            HStack(spacing: 10) {
                Button {
                    showSelectedInPopup()
                } label: {
                    Label(
                        isPlayerVisible ? L10n.text(.reloadPopup, language) : L10n.text(.viewInPopup, language),
                        systemImage: "play.rectangle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openSelectedInWindow()
                } label: {
                    Label(L10n.text(.popOutWindow, language), systemImage: "macwindow.badge.plus")
                }
                .buttonStyle(.bordered)

                Button {
                    store.copySelectedURL()
                } label: {
                    Label(L10n.text(.copyURL, language), systemImage: "link")
                }
                .buttonStyle(.bordered)

                Button {
                    store.copySelectedEmbed()
                } label: {
                    Label(L10n.text(.copyEmbed, language), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text(item.slug)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private func inlinePlayer(_ source: StreamSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(source.name, systemImage: "play.rectangle.fill")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Button {
                    inlineReloadToken += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help(L10n.text(.reload, language))

                Button {
                    openSelectedInWindow()
                } label: {
                    Label(L10n.text(.window, language), systemImage: "macwindow.badge.plus")
                }
                .buttonStyle(.bordered)
                .help(L10n.text(.popOutWindow, language))

                Button {
                    withAnimation {
                        isPlayerVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .help(L10n.text(.hidePlayer, language))
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.black.opacity(0.92))

                WebStreamView(source: source, reloadToken: inlineReloadToken)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxHeight: 285)
        }
        .padding(10)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func showInPopup(_ source: StreamSource) {
        store.select(source)
        showSelectedInPopup()
    }

    private func showSelectedInPopup() {
        guard store.selectedSource != nil else { return }
        inlineReloadToken += 1
        withAnimation {
            isPlayerVisible = true
        }
    }

    private func openSelectedInWindow() {
        guard store.selectedSource != nil else { return }
        store.openSelectedSource()
        inlineReloadToken += 1
        withAnimation {
            isPlayerVisible = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(L10n.text(.noResults, language))
                .font(.headline)
            Text(L10n.text(.refreshOrChangeFilter, language))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("\(L10n.text(.updated, language)): \(store.lastUpdatedText)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(store.snapshot.allPublicSources.count) \(L10n.text(.publicSourcesFooter, language))")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct StreamItemRow: View {
    let item: StreamItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                LogoView(url: item.logoURL, size: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text("\(item.publicSources.count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.16), in: Capsule())
            }
            .padding(9)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SourceRow: View {
    @Environment(\.appLanguage) private var language

    let source: StreamSource
    let isSelected: Bool
    let select: () -> Void
    let open: () -> Void
    let copyEmbed: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: select) {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isSelected ? .blue : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(source.displayURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button(action: copyEmbed) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(.bordered)
            .help(L10n.text(.copyEmbed, language))

            Button(action: open) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .help(L10n.text(.viewInPopup, language))
        }
        .padding(9)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.035))
        }
    }
}

private struct LogoView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(0.08))

            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .controlSize(.small)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                case .failure:
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(.secondary)
                @unknown default:
                    EmptyView()
                }
            }
        }
        .frame(width: size, height: size)
    }
}
