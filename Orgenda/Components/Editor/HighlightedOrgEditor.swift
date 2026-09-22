import SwiftUI

/// Owns the cancellable parser lifecycle while `OrgSyntaxTextEditor` owns the
/// stable TextKit view. Fast typing cancels older revisions before they publish.
struct HighlightedOrgEditor: View {
    @Binding private var text: String
    private let isEditable: Bool
    private let session: OrgEditorSession?
    private let isActive: Bool
    private let externalRevision: UInt64

    @State private var highlights: [OrgHighlightSpan] = []
    @State private var highlighter = OrgSyntaxHighlighter()

    init(text: Binding<String>, isEditable: Bool = true, session: OrgEditorSession? = nil,
         isActive: Bool = true, externalRevision: UInt64 = 0) {
        _text = text
        self.isEditable = isEditable
        self.session = session
        self.isActive = isActive
        self.externalRevision = externalRevision
    }

    var body: some View {
        OrgSyntaxTextEditor(
            text: $text,
            highlights: highlights,
            isEditable: isEditable,
            session: session,
            isActive: isActive,
            externalRevision: externalRevision
        )
        .task(id: text) {
            let revision = text
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }

            let nextHighlights = await highlighter.highlights(in: revision)
            guard !Task.isCancelled, revision == text else { return }
            highlights = nextHighlights
        }
    }
}
