import Foundation
import OrgTreeSitter

/// Confined to its owning actor. Published nodes contain values, never mutable TSNodes.
final class OrgDocumentSyntaxCache {
    private let parser = OrgParser()
    private(set) var tree: OrgSyntaxTree?
    private(set) var root: ParsedOrgNode?
    private(set) var workflow: WorkspaceConfiguration.Workflow?
    private var baseWorkflow: WorkspaceConfiguration.Workflow?
    private(set) var reusedBlockIDs: Set<String> = []

    @discardableResult
    func update(_ source: String, path: String, configuration: WorkspaceConfiguration) -> OrgSyntaxUpdate {
        let update = parser.update(source, previous: tree)
        let oldBlocks = root?.children ?? []
        let syntaxBlocks = update.tree.rootNode.namedChildren
        let declarationsMayChange = syntaxBlocks.contains {
            update.affects(Int($0.startByte)..<Int($0.endByte)) && $0.text.contains("#+")
        } || oldBlocks.contains {
            update.relocating($0.startByte..<$0.endByte) == nil && $0.text.contains("#+")
        }
        let nextWorkflow: WorkspaceConfiguration.Workflow
        if let workflow, baseWorkflow == configuration.workflow, !declarationsMayChange {
            nextWorkflow = workflow
        } else {
            nextWorkflow = OrgConfiguredHeading.workflow(in: source, base: configuration.workflow)
        }
        let sameWorkflow = workflow == nextWorkflow
        var candidates: [Range<Int>: ParsedOrgNode] = [:]
        for block in oldBlocks {
            let range = block.startByte..<block.endByte
            if let relocated = update.relocating(range) {
                candidates[relocated] = block
            }
        }
        let editedContainer = update.edit.flatMap { edit in
            oldBlocks.first { $0.startByte < edit.oldRange.lowerBound && $0.endByte > edit.oldRange.upperBound }
        }
        reusedBlockIDs = []
        let blocks = syntaxBlocks.map { node -> ParsedOrgNode in
            let start = Int(node.startByte)
            let end = Int(node.endByte)
            if sameWorkflow, !update.affects(start..<end), let old = candidates[start..<end] {
                reusedBlockIDs.insert(old.id)
                return old.shifted(by: start - old.startByte)
            }
            // Keep an edited block's identity only for an edit strictly inside it.
            // Insertions at boundaries must not steal the following block's ID.
            let previous = editedContainer.flatMap { $0.startByte == start && $0.type == node.type ? $0 : nil }
            var parsed = ParsedOrgNode(node, path: "\(path):\(UUID().uuidString)")
            if let previous { parsed.id = previous.id }
            return OrgConfiguredHeading.normalize(parsed, workflow: nextWorkflow)
        }
        root = ParsedOrgNode(id: root?.id ?? "\(path):root", type: update.tree.rootNode.type, text: source,
                             startByte: 0, endByte: source.utf8.count, children: blocks)
        tree = update.tree
        workflow = nextWorkflow
        baseWorkflow = configuration.workflow
        return update
    }
}
