import Foundation
import OrgTreeSitter

/// Semantic categories emitted by the Org tree-sitter highlighter.
///
/// These values deliberately contain no presentation details. The editor owns
/// the mapping from a semantic kind to colors, fonts, and text decorations.
enum OrgHighlightKind: String, CaseIterable, Hashable, Sendable {
    case heading
    case todo
    case priority
    case tag
    case planning
    case timestamp
    case property
    case keyword
    case comment
    case link
    case bold
    case italic
    case underline
    case strikethrough
    case code
    case verbatim
    case sourceBlock
    case quoteBlock
    case listMarker
    case checkbox
    case table
    case footnote
    case drawer
    case drawerDelimiter
    case clock
    case progress
    case target
    case macro
    case math
}

/// A presentation-independent highlight over an Org document's UTF-16 text.
/// `range` can be applied directly to `NSMutableAttributedString` or TextKit.
struct OrgHighlightSpan: Hashable, Sendable {
    let range: NSRange
    let kind: OrgHighlightKind
}

struct OrgHighlightBlock: Sendable {
    let id: String
    let revision: UUID
    let range: NSRange
    /// Relative to the block, so inserting text earlier does not invalidate these spans.
    let spans: [OrgHighlightSpan]
}

struct OrgHighlightSnapshot: Sendable {
    let revision = UUID()
    let source: String
    let baseWorkflow: WorkspaceConfiguration.Workflow
    let workflow: WorkspaceConfiguration.Workflow
    let blocks: [OrgHighlightBlock]
}

/// Each editor retains its syntax snapshot and block-local UTF-16 highlights.
actor OrgSyntaxHighlighter {
    private let syntax = OrgDocumentSyntaxCache()
    private var snapshot: OrgHighlightSnapshot?

    func highlights(in source: String, configuration: WorkspaceConfiguration = .classic) -> OrgHighlightSnapshot {
        if let snapshot, snapshot.baseWorkflow == configuration.workflow,
           snapshot.source.utf8.elementsEqual(source.utf8) { return snapshot }
        syntax.update(source, path: "highlight.org", configuration: configuration)
        let previous = Dictionary(uniqueKeysWithValues: (snapshot?.blocks ?? []).map { ($0.id, $0) })
        var blocks: [OrgHighlightBlock] = []
        var byteOffset = 0
        var utf16Offset = 0
        // Random-access slices avoid walking String.UTF8View from its start for every block.
        let bytes = Array(source.utf8)
        for node in syntax.root!.children {
            if node.startByte > byteOffset {
                utf16Offset += String(decoding: bytes[byteOffset..<node.startByte], as: UTF8.self).utf16.count
            }
            let cached = syntax.reusedBlockIDs.contains(node.id) ? previous[node.id] : nil
            let length = cached?.range.length ?? node.text.utf16.count
            let spans = cached?.spans ?? Self.spans(in: node)
            blocks.append(OrgHighlightBlock(id: node.id, revision: cached?.revision ?? UUID(),
                                            range: NSRange(location: utf16Offset, length: length), spans: spans))
            utf16Offset += length
            byteOffset = node.endByte
        }
        let result = OrgHighlightSnapshot(source: source, baseWorkflow: configuration.workflow,
                                          workflow: syntax.workflow!, blocks: blocks)
        snapshot = result
        return result
    }

    private nonisolated static func spans(in block: ParsedOrgNode) -> [OrgHighlightSpan] {
        let rangeMap = UTF16RangeMap(block.text)
        var result: [OrgHighlightSpan] = []
        var pending = [block]
        while let node = pending.popLast() {
            if let kind = highlightKind(for: node.type),
               let range = rangeMap.range(startByte: node.startByte - block.startByte,
                                                    endByte: node.endByte - block.startByte) {
                result.append(OrgHighlightSpan(range: range, kind: kind))
            }
            pending.append(contentsOf: node.children.reversed())
        }
        return result.sorted { lhs, rhs in
            if lhs.range.location != rhs.range.location { return lhs.range.location < rhs.range.location }
            if lhs.range.length != rhs.range.length { return lhs.range.length > rhs.range.length }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }

    private nonisolated static func highlightKind(for nodeType: String) -> OrgHighlightKind? {
        switch nodeType {
        case "heading_marker", "heading_title":
            return .heading
        case "todo_keyword":
            return .todo
        case "priority":
            return .priority
        case "tag_list":
            return .tag
        case "planning_keyword":
            return .planning
        case "clock_keyword", "clock_duration":
            return .clock
        case "active_timestamp", "inactive_timestamp":
            return .timestamp
        case "property":
            return .property
        case "drawer", "property_drawer":
            return .drawer
        case "property_drawer_begin", "property_drawer_end", "drawer_begin", "drawer_end":
            return .drawerDelimiter
        case "keyword_name", "block_keyword", "source_block_end", "quote_block_begin", "quote_block_end":
            return .keyword
        case "example_block_begin", "example_block_end", "export_block_begin", "export_block_end",
             "verse_block_begin", "verse_block_end", "center_block_begin", "center_block_end",
             "dynamic_block_begin", "dynamic_block_end":
            return .keyword
        case "latex_block", "latex_fragment":
            return .math
        case "macro", "export_snippet":
            return .macro
        case "comment", "comment_block":
            return .comment
        case "link", "angle_link", "plain_link":
            return .link
        case "target", "radio_target":
            return .target
        case "bold":
            return .bold
        case "italic":
            return .italic
        case "underline":
            return .underline
        case "strikethrough":
            return .strikethrough
        case "code":
            return .code
        case "verbatim":
            return .verbatim
        case "source_block", "example_block", "export_block", "fixed_width":
            return .sourceBlock
        case "quote_block", "verse_block", "center_block":
            return .quoteBlock
        case "unordered_list_marker", "ordered_list_marker", "list_counter", "description_tag", "horizontal_rule":
            return .listMarker
        case "statistics_cookie":
            return .progress
        case "checkbox":
            return .checkbox
        case "table":
            return .table
        case "footnote_definition_marker", "footnote_reference", "inline_footnote":
            return .footnote
        default:
            return nil
        }
    }

}

/// A linear-time map from UTF-8 byte boundaries to UTF-16 offsets. A `nil`
/// entry represents an offset inside a multi-byte Unicode scalar.
private struct UTF16RangeMap {
    private let offsets: [Int?]

    init(_ source: String) {
        var offsets = Array<Int?>(repeating: nil, count: source.utf8.count + 1)
        var byteOffset = 0
        var utf16Offset = 0
        offsets[0] = 0

        for scalar in source.unicodeScalars {
            byteOffset += scalar.utf8.count
            utf16Offset += scalar.value > 0xFFFF ? 2 : 1
            offsets[byteOffset] = utf16Offset
        }

        self.offsets = offsets
    }

    func range(startByte: Int, endByte: Int) -> NSRange? {
        guard startByte >= 0,
              endByte > startByte,
              endByte < offsets.count,
              let location = offsets[startByte],
              let upperBound = offsets[endByte]
        else { return nil }

        return NSRange(location: location, length: upperBound - location)
    }
}
