import COrgTreeSitter
import CTreeSitter
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
        let bytes = Array(source.utf8)
        let tree = bytes.withUnsafeBufferPointer { buffer in
            ts_parser_parse_string(
                rawParser,
                nil,
                buffer.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                UInt32(buffer.count)
            )
        }!
        return OrgSyntaxTree(storage: OrgTreeStorage(tree: tree, bytes: bytes))
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
    private let storage: OrgTreeStorage

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
        guard let expression = ts_node_string(rawNode) else { return "" }
        defer { free(expression) }
        return String(cString: expression)
    }
}
