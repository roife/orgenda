import SwiftUI

struct SearchResultRow: View {
    let result: SearchResult
    let store: WorkspaceStore
    let trimmedQuery: String
    let onPresent: (SearchPresentation) -> Void

    @ViewBuilder
    var body: some View {
        switch result {
        case .item(let item):
            Button { onPresent(.item(item)) } label: {
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
            Button { onPresent(.settings(destination)) } label: {
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
