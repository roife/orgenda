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
}

/// A presentation-independent highlight over an Org document's UTF-16 text.
/// `range` can be applied directly to `NSMutableAttributedString` or TextKit.
struct OrgHighlightSpan: Hashable, Sendable {
    let range: NSRange
    let kind: OrgHighlightKind
}

/// Serializes access to the reusable tree-sitter parser and turns its syntax
/// nodes into editor-friendly semantic spans.
///
/// `highlights(in:)` is intentionally synchronous inside the actor. A caller
/// can run it from a cancellable `Task` after a 90 ms (or longer) debounce. The
/// traversal checks cancellation so superseded editor revisions stop promptly.
actor OrgSyntaxHighlighter {
    private let parser = OrgParser()

    func highlights(in source: String) -> [OrgHighlightSpan] {
        guard !source.isEmpty, !Task.isCancelled else { return [] }
        let tree = parser.parse(source)

        let rangeMap = UTF16RangeMap(source)
        let mathRanges = OrgMathParser.matches(in: source).compactMap {
            rangeMap.range(startByte: $0.startByte, endByte: $0.endByte)
        }
        var result: [OrgHighlightSpan] = []
        var pending = [tree.rootNode]

        while let node = pending.popLast() {
            guard !Task.isCancelled else { return [] }

            if !node.isMissing,
               let kind = Self.highlightKind(for: node.type),
               let range = rangeMap.range(
                   startByte: Int(node.startByte),
                   endByte: Int(node.endByte)
               ), !Self.isOrgMarkup(kind, inside: mathRanges, range: range) {
                result.append(OrgHighlightSpan(range: range, kind: kind))
            }

            // Push in reverse so traversal and equal-location ordering remain
            // deterministic and follow source order.
            pending.append(contentsOf: node.namedChildren.reversed())
        }

        // Broad structural spans come first at the same location, allowing a
        // consumer to apply nested token styles afterwards.
        return result.sorted { lhs, rhs in
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            if lhs.range.length != rhs.range.length {
                return lhs.range.length > rhs.range.length
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }

    /// Converts a tree-sitter byte range into the UTF-16 coordinate space used
    /// by Foundation text APIs. Invalid, reversed, out-of-bounds, or mid-scalar
    /// offsets are rejected instead of being rounded to a nearby character.
    nonisolated static func utf16Range(
        startByte: Int,
        endByte: Int,
        in source: String
    ) -> NSRange? {
        UTF16RangeMap(source).range(startByte: startByte, endByte: endByte)
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

    private nonisolated static func isOrgMarkup(
        _ kind: OrgHighlightKind,
        inside mathRanges: [NSRange],
        range: NSRange
    ) -> Bool {
        guard [.bold, .italic, .underline, .strikethrough, .code, .verbatim].contains(kind) else {
            return false
        }
        return mathRanges.contains { NSIntersectionRange($0, range).length == range.length }
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
              let upperBound = offsets[endByte],
              upperBound >= location
        else { return nil }

        return NSRange(location: location, length: upperBound - location)
    }
}
