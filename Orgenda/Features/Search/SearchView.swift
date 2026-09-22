import SwiftUI

struct SearchView: View {
    let store: WorkspaceStore
    @Binding var query: String
    @State private var scope: SearchScope = .all
    @State private var presentation: SearchPresentation?
    @State private var results: [SearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var completedSearch: SearchRequest?

    private struct SearchRequest: Equatable {
        let query: String
        let scope: SearchScope
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            searchContent
                .background(Color(uiColor: .systemBackground))
                .navigationTitle("Search")
                .safeAreaInset(edge: .top, spacing: 0) { scopeBar }
                .sheet(item: $presentation) { destination in
                    switch destination {
                    case .item(let item):
                        OrgItemEditor(store: store, draft: item)
                    case .settings(let destination):
                        SettingsView(store: store, initialDestination: destination)
                            .presentationDragIndicator(.visible)
                    }
                }
                .sensoryFeedback(.selection, trigger: scope)
        }
        .searchable(text: $query, prompt: "Search orgenda")
        .task { scheduleSearch() }
        // Debounced, cancellable search: scanning every document on each
        // keystroke blocked the main thread. Data changes re-run the active
        // query so results stay current after edits without a stale copy.
        .onChange(of: trimmedQuery) { _, _ in scheduleSearch() }
        .onChange(of: scope) { _, _ in scheduleSearch() }
        .onChange(of: store.items) { _, _ in scheduleSearch() }
        .onChange(of: store.documents) { _, _ in scheduleSearch() }
        .onChange(of: store.journalEntries) { _, _ in scheduleSearch() }
        .onDisappear { searchTask?.cancel() }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let request = SearchRequest(query: trimmedQuery, scope: scope)
        guard !request.query.isEmpty else {
            searchTask = nil
            results = []
            completedSearch = nil
            return
        }
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled,
                  request.query == trimmedQuery, request.scope == scope else { return }
            results = store.search(request.query, scope: request.scope)
            completedSearch = request
        }
    }

    private var scopeBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Search category")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            scopeMenu
                .buttonStyle(.bordered)
                .tint(OrgendaTheme.accentText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var scopeMenu: some View {
        Menu {
            Picker("Search category", selection: $scope) {
                ForEach(SearchScope.allCases) { candidate in
                    Text(candidate == .all ? String(localized: "All categories") : candidate.title)
                        .tag(candidate)
                        .accessibilityHint("Filters search results")
                        .accessibilityIdentifier("search.scope.\(candidate.id.lowercased())")
                }
            }
        } label: {
            Label(scope.title, systemImage: "line.3.horizontal.decrease")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 32)
        }
        .accessibilityLabel("Search category")
        .accessibilityValue(scope == .all ? String(localized: "All categories") : scope.title)
        .accessibilityHint("Choose which category to search")
        .accessibilityIdentifier("search.scope.menu")
    }

    @ViewBuilder
    private var searchContent: some View {
        if trimmedQuery.isEmpty {
            if hasSuggestions {
                suggestions
            } else {
                searchGuidance
            }
        } else if completedSearch != SearchRequest(query: trimmedQuery, scope: scope) {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("search.loading")
        } else {
            if results.isEmpty {
                noResults
            } else {
                List {
                    Section {
                        ForEach(results) { result in
                            resultRow(result)
                                .padding(.vertical, 5)
                        }
                    } header: {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text(scope == .all ? String(localized: "All results") : scope.title)
                                Spacer()
                                Text(String(localized: "\(results.count) found"))
                                    .monospacedDigit()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(scope == .all ? String(localized: "All results") : scope.title)
                                Text("\(results.count) found")
                                    .monospacedDigit()
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                        .accessibilityElement(children: .combine)
                    }
                }
                .searchListSurface()
                .accessibilityIdentifier("search.results")
            }
        }
    }

    private var hasSuggestions: Bool {
        switch scope {
        case .all:
            !suggestedTags.isEmpty || !store.journalEntries.isEmpty
                || store.documents.contains { $0.kind != .folder }
        case .tasks, .calendar:
            !suggestedTags.isEmpty
        case .journal:
            !store.journalEntries.isEmpty
        case .files:
            store.documents.contains { $0.kind != .folder }
        case .settings:
            true
        }
    }

    private var searchGuidance: some View {
        ScrollView {
            ContentUnavailableView {
                Label("Start a search", systemImage: "magnifyingglass")
            } description: {
                Text(searchGuidanceDescription)
            } actions: {
                if scope != .all {
                    Button("Search All") { scope = .all }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityIdentifier("search.expandScope")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("search.guidance")
    }

    private var searchGuidanceDescription: String {
        switch scope {
        case .all: String(localized: "Search titles, notes, tags, and file contents.")
        case .tasks: String(localized: "Search task titles, notes, or tags.")
        case .calendar: String(localized: "Search the titles, notes, or tags of dated items.")
        case .journal: String(localized: "Search journal titles or text.")
        case .files: String(localized: "Search file names or contents.")
        case .settings: String(localized: "Search workspace, appearance, or reminder settings.")
        }
    }

    private var suggestions: some View {
        List {
            if !suggestedTags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestedTags, id: \.self) { tag in
                                Button {
                                    query = tag
                                } label: {
                                    Label(tag, systemImage: "number")
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 44)
                                        .background(OrgendaTheme.accent.opacity(0.08), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(OrgendaTheme.accentText)
                                .accessibilityLabel("Search for tag \(tag)")
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowSeparator(.hidden)
                } header: {
                    searchSectionTitle(String(localized: "Try a tag"))
                }
            }

            if scope == .all || scope == .journal {
                let entries = store.journalEntries.sorted { $0.date > $1.date }.prefix(3)
                if !entries.isEmpty {
                    Section {
                        ForEach(entries) { entry in
                            journalLink(entry)
                                .padding(.vertical, 4)
                        }
                    } header: {
                        searchSectionTitle(String(localized: "Recent journal entries"))
                    }
                }
            }

            if scope == .all || scope == .files {
                let files = store.documents.filter { $0.kind != .folder }.prefix(4)
                if !files.isEmpty {
                    Section {
                        ForEach(files) { document in
                            documentLink(document)
                                .padding(.vertical, 4)
                        }
                    } header: {
                        searchSectionTitle(String(localized: "Browse files"))
                    }
                }
            }

            if scope == .settings {
                Section {
                    Button {
                        presentation = .settings(nil)
                    } label: {
                        SearchResultLabel(
                            icon: "gearshape",
                            title: String(localized: "Browse Settings"),
                            subtitle: String(localized: "Workspace, appearance, and reminders"),
                            tint: OrgendaTheme.accent
                        )
                    }
                    .accessibilityHint("Opens Settings")
                }
            }
        }
        .listSectionSpacing(16)
        .searchListSurface()
        .accessibilityIdentifier("search.suggestions")
    }

    private func searchSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .textCase(nil)
            .fixedSize(horizontal: false, vertical: true)
            // Plain list headers carry ~20pt of system padding on each side;
            // pull it back so suggestions read as compact groups.
            .padding(.vertical, -10)
    }

    private var suggestedTags: [String] {
        guard scope == .all || scope == .tasks || scope == .calendar else { return [] }
        let items = store.items.filter { item in
            switch scope {
            case .tasks: item.kind == .task || item.kind == .project || item.kind == .habit
            case .calendar: item.agendaDate != nil
            default: true
            }
        }
        let counts = items.flatMap(\.tags).reduce(into: [String: Int]()) { counts, tag in
            counts[tag, default: 0] += 1
        }
        return Array(counts.keys.sorted {
            let first = counts[$0, default: 0]
            let second = counts[$1, default: 0]
            return first == second ? $0.localizedStandardCompare($1) == .orderedAscending : first > second
        }.prefix(8))
    }

    private var noResults: some View {
        ScrollView {
            ContentUnavailableView {
                Label("No results", systemImage: "magnifyingglass")
            } description: {
                Text(scope == .all
                     ? "No matches for “\(trimmedQuery)”. Try another word or a shorter phrase."
                     : "No matches for “\(trimmedQuery)” in \(scope.title). Try searching all categories.")
            } actions: {
                if scope != .all {
                    Button("Search All") { scope = .all }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("search.expandScope")
                }
                Button("Clear Search") { query = "" }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func resultRow(_ result: SearchResult) -> some View {
        switch result {
        case .item(let item):
            Button { presentation = .item(item) } label: {
                SearchResultLabel(
                    icon: item.kind.systemImage,
                    title: item.title,
                    subtitle: itemSubtitle(item),
                    tint: OrgendaTheme.kindColor(item.kind),
                    query: trimmedQuery,
                    detail: "\(item.kind.title) · \(item.source.file)",
                    state: item.hasWorkflowState ? item.state : nil
                )
            }
            .accessibilityHint("Opens item details")
        case .journal(let entry):
            journalLink(entry)
        case .document(let document):
            documentLink(document)
        case .setting(let destination):
            Button { presentation = .settings(destination) } label: {
                SearchResultLabel(icon: "gearshape", title: destination.title, subtitle: destination.subtitle, tint: .secondary, query: trimmedQuery)
            }
            .accessibilityHint(Text("Opens \(destination.title) settings"))
            .accessibilityIdentifier("search.setting.\(destination.rawValue)")
        }
    }

    private func itemSubtitle(_ item: OrgItem) -> String {
        let matchingTags = item.tags.filter {
            $0.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        if !matchingTags.isEmpty {
            return matchingTags.map { "#\($0)" }.joined(separator: "  ")
        }
        return searchExcerpt(item.body, matching: trimmedQuery)
    }

    private func journalLink(_ entry: JournalEntry) -> some View {
        NavigationLink {
            SearchJournalDetail(entry: entry)
        } label: {
            SearchResultLabel(
                icon: "book.closed",
                title: entry.title,
                subtitle: searchExcerpt(entry.body, matching: trimmedQuery),
                tint: OrgendaTheme.habit,
                query: trimmedQuery,
                detail: OrgendaDatePresentation.dateTime(entry.date)
            )
        }
    }

    private func documentLink(_ document: WorkspaceDocument) -> some View {
        NavigationLink {
            if document.kind == .folder {
                WorkspaceFolderView(store: store, folder: document)
            } else {
                OrgDocumentView(store: store, path: document.path, searchQuery: trimmedQuery.isEmpty ? nil : trimmedQuery)
            }
        } label: {
            SearchResultLabel(
                icon: document.kind == .folder ? "folder" : "doc.text",
                title: document.title,
                subtitle: trimmedQuery.isEmpty ? document.path : searchExcerpt(document.contents, matching: trimmedQuery),
                tint: OrgendaTheme.accent,
                query: trimmedQuery,
                detail: trimmedQuery.isEmpty ? nil : document.path
            )
        }
        .accessibilityIdentifier("search.document.\(document.path)")
    }
}

private enum SearchPresentation: Identifiable {
    case item(OrgItem)
    case settings(SettingsDestination?)

    var id: String {
        switch self {
        case .item(let item): "item-\(item.id)"
        case .settings(let destination): "settings-\(destination?.rawValue ?? "root")"
        }
    }
}

private struct SearchResultLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 30
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    var query = ""
    var detail: String?
    var state: OrgWorkflowState?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: iconSize, height: iconSize)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let state { OrgWorkflowIcon(state) }
                    Text(highlightedTitle)
                        .foregroundStyle(state.map(OrgendaTheme.workflowColor) ?? .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body.weight(.medium))
                if !subtitle.isEmpty {
                    Text(highlighted(subtitle))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty,
              let range = result.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return result
        }
        result[range].inlinePresentationIntent = .stronglyEmphasized
        result[range].foregroundColor = OrgendaTheme.accentText
        return result
    }

    private var highlightedTitle: AttributedString {
        var value = highlighted(title)
        if let state { value.foregroundColor = OrgendaTheme.workflowColor(state) }
        return value
    }
}

private func searchExcerpt(_ source: String, matching query: String) -> String {
    let text = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard !query.isEmpty,
          let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
        return String(text.prefix(160))
    }
    let start = text.index(match.lowerBound, offsetBy: -45, limitedBy: text.startIndex) ?? text.startIndex
    let end = text.index(match.upperBound, offsetBy: 110, limitedBy: text.endIndex) ?? text.endIndex
    return (start == text.startIndex ? "" : "…")
        + String(text[start..<end])
        + (end == text.endIndex ? "" : "…")
}

private struct SearchJournalDetail: View {
    let entry: JournalEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(OrgendaDatePresentation.dateTime(entry.date), systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(entry.title)
                    .font(.title.weight(.bold))
                Text(entry.body)
                    .font(.body)
                    .lineSpacing(5)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .navigationTitle("Journal Entry")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension View {
    func searchListSurface() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
    }
}
