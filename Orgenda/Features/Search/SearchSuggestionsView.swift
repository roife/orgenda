import SwiftUI

struct SearchSuggestionsView: View {
    let store: WorkspaceStore
    let scope: SearchScope
    let suggestions: SearchSuggestions
    @Binding var query: String
    let onPresent: (SearchPresentation) -> Void

    var body: some View {
        List {
            if !suggestions.tags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: OrgendaSpacing.rowInset) {
                            ForEach(suggestions.tags, id: \.self) { tag in
                                Button {
                                    query = tag
                                } label: {
                                    HStack(spacing: OrgendaSpacing.compactInset) {
                                        Image(systemName: "number")
                                        Text(tag)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .tint(OrgendaTheme.accentText)
                                .font(.caption.weight(.medium))
                                .controlSize(.small)
                                .accessibilityLabel("Search for tag \(tag)")
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowSeparator(.hidden)
                } header: {
                    searchSectionTitle(String(localized: "Try a tag"))
                }
                .listRowInsets(.horizontal, OrgendaSpacing.pageMargin)
            }

            if scope == .all || scope == .journal {
                let entries = store.journalEntries.sorted { $0.date > $1.date }.prefix(3)
                if !entries.isEmpty {
                    Section {
                        ForEach(entries) { entry in
                            SearchResultRow(result: .journal(entry), store: store, trimmedQuery: "",
                                            subtitle: searchExcerpt(entry.body), onPresent: onPresent)
                                .padding(.vertical, OrgendaSpacing.compactInset)
                        }
                    } header: {
                        searchSectionTitle(String(localized: "Recent journal entries"))
                    }
                    .listRowInsets(.horizontal, OrgendaSpacing.pageMargin)
                }
            }

            if scope == .all || scope == .files {
                let files = store.documents.filter { $0.kind != .folder }.prefix(4)
                if !files.isEmpty {
                    Section {
                        ForEach(files) { document in
                            SearchResultRow(result: .document(document), store: store, trimmedQuery: "",
                                            subtitle: document.path, onPresent: onPresent)
                                .padding(.vertical, OrgendaSpacing.compactInset)
                        }
                    } header: {
                        searchSectionTitle(String(localized: "Browse files"))
                    }
                    .listRowInsets(.horizontal, OrgendaSpacing.pageMargin)
                }
            }

            if scope == .settings {
                Section {
                    Button {
                        onPresent(.settings(nil))
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
                .listRowInsets(.horizontal, OrgendaSpacing.pageMargin)
            }
        }
        .searchListSurface()
        .accessibilityIdentifier("search.suggestions")
    }

    private func searchSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .textCase(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

}
