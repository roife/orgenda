import SwiftUI

struct SearchView: View {
    let store: WorkspaceStore
    @Binding var query: String
    var focusRequest: UUID? = nil
    @FocusState private var isSearchFocused: Bool
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

    private var suggestions: SearchSuggestions {
        SearchSuggestions(scope: scope, items: store.items,
                          journalEntries: store.journalEntries, documents: store.documents)
    }

    var body: some View {
        NavigationStack {
            searchContent
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
                .navigationTitle("Search")
                // Search has its own scope header. Keep navigation chrome from
                // collapsing separately while the search field gains focus.
                .toolbar(.hidden, for: .navigationBar)
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
        .searchFocused($isSearchFocused)
        .task(id: focusRequest) {
            if focusRequest != nil { isSearchFocused = true }
        }
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
            guard !Task.isCancelled else { return }
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
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
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
            if suggestions.isAvailable {
                SearchSuggestionsView(
                    store: store, scope: scope, suggestions: suggestions, query: $query,
                    onPresent: { presentation = $0 }
                )
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
                            SearchResultRow(result: result, store: store, trimmedQuery: trimmedQuery, onPresent: { presentation = $0 })
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

    private var searchGuidance: some View {
        SearchEmptyState(title: "Start a search", description: searchGuidanceDescription) {
            if scope != .all {
                Button("Search All") { scope = .all }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("search.expandScope")
                    .padding(.top, 24)
            }
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

    private var noResults: some View {
        SearchEmptyState(
            title: "No results",
            description: scope == .all
                ? String(localized: "No matches for “\(trimmedQuery)”. Try another word or a shorter phrase.")
                : String(localized: "No matches for “\(trimmedQuery)” in \(scope.title). Try searching all categories.")
        ) {
            VStack(spacing: 12) {
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
            .padding(.top, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

}

/// A single SwiftUI layout keeps the icon, title, and description together
/// during search activation and keyboard resizing. ContentUnavailableView
/// adjusts its own placement during that transition, producing a second jump.
private struct SearchEmptyState<Actions: View>: View {
    let title: LocalizedStringKey
    let description: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.bold())
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
            actions()
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .orgendaEmptyState()
    }
}
