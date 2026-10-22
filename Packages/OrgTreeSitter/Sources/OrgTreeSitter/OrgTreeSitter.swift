import COrgTreeSitter
import TreeSitter
import Foundation

/// Metadata and low-level entry points for the bundled Org grammar.
public enum OrgTreeSitter {
    /// The generated language ABI consumed by tree-sitter.
    public static var language: OpaquePointer {
        tree_sitter_org()!
    }

    public static var abiVersion: UInt32 {
        ts_language_abi_version(language)
    }
}

/// A reusable tree-sitter parser configured for Org documents.
public final class OrgParser {
    private let rawParser: OpaquePointer

    public init() {
        let parser = ts_parser_new()!
        precondition(ts_parser_set_language(parser, OrgTreeSitter.language))
        rawParser = parser
    }

    deinit {
        ts_parser_delete(rawParser)
    }

    /// Parses UTF-8 Org text into an immutable syntax tree.
    public func parse(_ source: String) -> OrgSyntaxTree {
        update(source, previous: nil).tree
    }

    /// The previous snapshot remains immutable, including nodes retained by readers.
    public func update(_ source: String, previous: OrgSyntaxTree?) -> OrgSyntaxUpdate {
        let bytes = Array(source.utf8)
        let edit = previous.flatMap { OrgSyntaxEdit(old: $0.storage.bytes, new: bytes) }
        if let previous, edit == nil {
            return OrgSyntaxUpdate(tree: previous, edit: nil, changedRanges: [])
        }
        let editedTree = previous.map { ts_tree_copy($0.storage.tree)! }
        defer { if let editedTree { ts_tree_delete(editedTree) } }
        if let editedTree, let edit {
            var input = edit.input
            ts_tree_edit(editedTree, &input)
        }
        let tree = bytes.withUnsafeBufferPointer { buffer in
            ts_parser_parse_string(
                rawParser,
                editedTree,
                buffer.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                UInt32(buffer.count)
            )
        }!
        var ranges: [Range<Int>] = []
        if let editedTree {
            var count: UInt32 = 0
            if let changed = ts_tree_get_changed_ranges(editedTree, tree, &count) {
                defer { free(changed) }
                ranges = (0..<Int(count)).map { Int(changed[$0].start_byte)..<Int(changed[$0].end_byte) }
            }
            // Text-only edits (dates, checkbox values, names) can keep the same syntax.
            if let edit { ranges.append(edit.newRange) }
        } else {
            ranges = [0..<bytes.count]
        }
        return OrgSyntaxUpdate(tree: OrgSyntaxTree(storage: OrgTreeStorage(tree: tree, bytes: bytes)),
                               edit: edit, changedRanges: ranges)
    }
}

public struct OrgSyntaxUpdate {
    public let tree: OrgSyntaxTree
    public let edit: OrgSyntaxEdit?
    /// New-document coordinates, including the actual text edit, even a deletion.
    public let changedRanges: [Range<Int>]

    /// Only ranges wholly outside the replaced text can be reused without inspection.
    public func relocating(_ range: Range<Int>) -> Range<Int>? {
        guard let edit else { return range }
        if range.upperBound <= edit.oldRange.lowerBound { return range }
        if range.lowerBound >= edit.oldRange.upperBound {
            let delta = edit.newRange.count - edit.oldRange.count
            return (range.lowerBound + delta)..<(range.upperBound + delta)
        }
        return nil
    }

    public func affects(_ range: Range<Int>) -> Bool {
        changedRanges.contains {
            $0.isEmpty ? range.lowerBound <= $0.lowerBound && $0.lowerBound <= range.upperBound
                : range.overlaps($0)
        }
    }
}

public struct OrgSyntaxEdit {
    public let oldRange: Range<Int>
    public let newRange: Range<Int>
    fileprivate let input: TSInputEdit

    fileprivate init?(old: [UInt8], new: [UInt8]) {
        var start = 0
        while start < min(old.count, new.count), old[start] == new[start] { start += 1 }
        guard start != old.count || start != new.count else { return nil }
        // A common byte prefix/suffix may end inside a Unicode scalar.
        while start > 0, start < old.count, old[start] & 0xc0 == 0x80 { start -= 1 }
        var oldEnd = old.count
        var newEnd = new.count
        while oldEnd > start, newEnd > start, old[oldEnd - 1] == new[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }
        while oldEnd < old.count, old[oldEnd] & 0xc0 == 0x80 {
            oldEnd += 1
            newEnd += 1
        }
        func point(_ bytes: ArraySlice<UInt8>, from initial: TSPoint = TSPoint(row: 0, column: 0)) -> TSPoint {
            var result = initial
            for byte in bytes {
                if byte == 10 { result.row += 1; result.column = 0 }
                else { result.column += 1 }
            }
            return result
        }
        let startPoint = point(old[..<start])
        oldRange = start..<oldEnd
        newRange = start..<newEnd
        input = TSInputEdit(start_byte: UInt32(start), old_end_byte: UInt32(oldEnd), new_end_byte: UInt32(newEnd),
                            start_point: startPoint, old_end_point: point(old[start..<oldEnd], from: startPoint),
                            new_end_point: point(new[start..<newEnd], from: startPoint))
    }
}

private final class OrgTreeStorage {
    let tree: OpaquePointer
    let bytes: [UInt8]

    init(tree: OpaquePointer, bytes: [UInt8]) {
        self.tree = tree
        self.bytes = bytes
    }

    deinit {
        ts_tree_delete(tree)
    }
}

/// An immutable parse result. Nodes retain this tree's storage when copied.
public struct OrgSyntaxTree {
    fileprivate let storage: OrgTreeStorage

    fileprivate init(storage: OrgTreeStorage) {
        self.storage = storage
    }

    public var rootNode: OrgSyntaxNode {
        OrgSyntaxNode(rawNode: ts_tree_root_node(storage.tree), storage: storage)
    }

    public var sExpression: String {
        rootNode.sExpression
    }

    public var hasError: Bool {
        rootNode.hasError
    }
}

public struct OrgPoint: Hashable, Sendable {
    public let row: UInt32
    public let column: UInt32
}

/// A stable view of one named or anonymous node in an `OrgSyntaxTree`.
public struct OrgSyntaxNode {
    private let rawNode: TSNode
    private let storage: OrgTreeStorage

    fileprivate init(rawNode: TSNode, storage: OrgTreeStorage) {
        self.rawNode = rawNode
        self.storage = storage
    }

    public var type: String {
        String(cString: ts_node_type(rawNode))
    }

    public var isNamed: Bool {
        ts_node_is_named(rawNode)
    }

    public var isMissing: Bool {
        ts_node_is_missing(rawNode)
    }

    public var hasError: Bool {
        ts_node_has_error(rawNode)
    }

    public var startByte: UInt32 {
        ts_node_start_byte(rawNode)
    }

    public var endByte: UInt32 {
        ts_node_end_byte(rawNode)
    }

    public var startPoint: OrgPoint {
        let point = ts_node_start_point(rawNode)
        return OrgPoint(row: point.row, column: point.column)
    }

    public var endPoint: OrgPoint {
        let point = ts_node_end_point(rawNode)
        return OrgPoint(row: point.row, column: point.column)
    }

    public var text: String {
        String(
            decoding: storage.bytes[Int(startByte)..<Int(endByte)],
            as: UTF8.self
        )
    }

    public var namedChildren: [OrgSyntaxNode] {
        (0..<ts_node_named_child_count(rawNode)).map { index in
            OrgSyntaxNode(rawNode: ts_node_named_child(rawNode, index), storage: storage)
        }
    }

    public func child(named fieldName: String) -> OrgSyntaxNode? {
        let child = fieldName.withCString { name in
            ts_node_child_by_field_name(rawNode, name, UInt32(fieldName.utf8.count))
        }
        guard !ts_node_is_null(child) else { return nil }
        return OrgSyntaxNode(rawNode: child, storage: storage)
    }

    public var sExpression: String {
        let expression = ts_node_string(rawNode)!
        defer { free(expression) }
        return String(cString: expression)
    }
}
