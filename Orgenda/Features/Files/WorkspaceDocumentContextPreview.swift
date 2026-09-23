import SwiftUI

struct WorkspaceDocumentContextPreview: View {
    let document: WorkspaceDocument
    let store: WorkspaceStore

    var body: some View {
        OrgContextPreview(title: document.title, subtitle: document.path,
                          systemImage: document.kind == .folder ? "folder.fill" : "doc.text",
                          tint: document.kind == .folder ? .orange : OrgendaTheme.accentText) {
            if document.kind == .folder {
                let children = visibleFolderDocuments(store.documents, folderPath: document.path)
                if children.isEmpty {
                    Text("This folder is empty").foregroundStyle(.secondary)
                } else {
                    ForEach(children.prefix(5)) { child in
                        Label(child.title, systemImage: child.kind == .folder ? "folder" : "doc.text")
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    if children.count > 5 {
                        Text(verbatim: "…").foregroundStyle(.secondary)
                    }
                }
            } else if !document.contents.isEmpty {
                Text(String(document.contents.prefix(1200)))
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(10)
            }
        }
        .accessibilityIdentifier("files.contextPreview")
    }
}
