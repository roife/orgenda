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
                        HStack(spacing: 8) {
                            ForEach(suggestions.tags, id: \.self) { tag in
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
                            SearchResultRow(result: .journal(entry), store: store, trimmedQuery: "", onPresent: onPresent)
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
                            SearchResultRow(result: .document(document), store: store, trimmedQuery: "", onPresent: onPresent)
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

}
