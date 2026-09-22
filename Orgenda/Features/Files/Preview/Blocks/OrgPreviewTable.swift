import SwiftUI

struct OrgPreviewTable: View {
    let node: ParsedOrgNode

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 0) {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { index, row in
                    if row.type == "table_separator" {
                        Divider().gridCellColumns(columnCount).gridCellUnsizedAxes(.horizontal)
                    } else {
                        GridRow {
                            ForEach(0..<columnCount, id: \.self) { column in
                                let cells = cells(in: row)
                                OrgPreviewRichText(
                                    fragments: column < cells.count ? cells[column].map {
                                        OrgPreviewMarkup.fragments($0, trimSpaces: true)
                                    } ?? [.text(AttributedString(" "))] : [.text(AttributedString(" "))],
                                    textStyle: .subheadline
                                )
                                .font(.subheadline)
                                .fontWeight(index == 0 && hasHeader ? .semibold : .regular)
                                .padding(.vertical, 5)
                                .textSelection(.enabled)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("org.preview.table.\(node.startByte)")
    }

    private var hasHeader: Bool { node.children.dropFirst().first?.type == "table_separator" }
    private var columnCount: Int { max(1, node.children.map { cells(in: $0).count }.max() ?? 1) }

    private func cells(in row: ParsedOrgNode) -> [ParsedOrgNode?] {
        var result: [ParsedOrgNode?] = []
        var current: ParsedOrgNode?
        var hasPipe = false
        for child in row.children {
            if child.type == "table_pipe" {
                if hasPipe { result.append(current); current = nil }
                hasPipe = true
            } else if child.type == "table_cell" { current = child }
        }
        if let current { result.append(current) }
        return result
    }
}
