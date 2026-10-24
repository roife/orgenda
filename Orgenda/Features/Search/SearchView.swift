import SwiftUI

struct SearchView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let store: WorkspaceStore
    @Binding var query: String
    var focusRequest: UUID? = nil
    @FocusState private var isSearchFocused: Bool
    @State private var scope: SearchScope = .all
    @State private var presentation: SearchPresentation?
    @State private var results: [SearchMatch] = []
    @State private var completedSearch: SearchRequest?

    private struct SearchRequest: Equatable {
        let query: String
        let scope: SearchScope
        let revision: UInt64
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchRequest: SearchRequest {
        SearchRequest(query: trimmedQuery, scope: scope, revision: store.searchRevision)
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
                .background(OrgendaTheme.background)
                .navigationTitle("Search")
                // Regular-width search lives in the navigation bar; hiding it
                // also removes the iPad search field. Compact layouts use the
                // search tab and keep the scope header stable during focus.
                .toolbar(horizontalSizeClass == .compact ? .hidden : .visible, for: .navigationBar)
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
        .searchable(
            text: $query,
            placement: horizontalSizeClass == .compact ? .automatic : .navigationBarDrawer(displayMode: .always),
            prompt: "Search orgenda"
        )
        .searchFocused($isSearchFocused)
        .task(id: focusRequest) {
            if focusRequest != nil { isSearchFocused = true }
        }
        .task(id: searchRequest) { await search(searchRequest) }
    }

    private func search(_ request: SearchRequest) async {
        guard !request.query.isEmpty else {
            results = []
            completedSearch = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let matches = await store.search(request.query, scope: request.scope)
        guard !Task.isCancelled, request == searchRequest else { return }
        results = matches
        completedSearch = request
    }

    private var scopeBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: OrgendaSpacing.contentInset) {
            Text("Search category")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Spacer(minLength: OrgendaSpacing.rowInset)
            scopeMenu
                .buttonStyle(.bordered)
                .tint(OrgendaTheme.accentText)
        }
        .padding(.horizontal, OrgendaSpacing.pageMargin)
        .padding(.vertical, OrgendaSpacing.rowInset)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
        .background(OrgendaTheme.background)
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
        } else if let completedSearch, !results.isEmpty {
            resultsList(for: completedSearch)
        } else if completedSearch != searchRequest {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("search.loading")
        } else {
            noResults
        }
    }

    private func resultsList(for request: SearchRequest) -> some View {
        List {
            Section {
                ForEach(results) { match in
                    SearchResultRow(
                        result: match.result, store: store, trimmedQuery: request.query,
                        subtitle: match.subtitle, onPresent: { presentation = $0 }
                    )
                    .padding(.vertical, OrgendaSpacing.compactInset)
                }
            } header: {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(request.scope == .all ? String(localized: "All results") : request.scope.title)
                        Spacer()
                        resultCount
                    }
                    VStack(alignment: .leading, spacing: OrgendaSpacing.compactInset) {
                        Text(request.scope == .all ? String(localized: "All results") : request.scope.title)
                        resultCount
                    }
                }
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
                .accessibilityElement(children: .combine)
            }
            .listRowInsets(.horizontal, OrgendaSpacing.pageMargin)
        }
        .searchListSurface()
        .accessibilityIdentifier("search.results")
    }

    private var resultCount: some View {
        HStack(spacing: OrgendaSpacing.rowInset) {
            if completedSearch != searchRequest {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Searching…")
                    .accessibilityIdentifier("search.loading")
            }
            Text("\(results.count) found")
                .monospacedDigit()
        }
    }

    private var searchGuidance: some View {
        SearchEmptyState(title: "Start a search", description: searchGuidanceDescription) {
            if scope != .all {
                Button("Search All") { scope = .all }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("search.expandScope")
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
            VStack(spacing: OrgendaSpacing.contentInset) {
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
        }
        .scrollDismissesKeyboard(.interactively)
    }

}

private struct SearchEmptyState<Actions: View>: View {
    let title: LocalizedStringKey
    let description: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "magnifyingglass")
        } description: {
            Text(description)
        } actions: {
            actions()
        }
        .orgendaEmptyState()
        .accessibilityIdentifier("search.empty")
    }
}
