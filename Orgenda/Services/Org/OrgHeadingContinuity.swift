import Foundation

/// Heading offsets change as earlier text is edited. Match outline paths instead
/// of retaining IDs that encode those old byte offsets.
enum OrgHeadingContinuity {
    static func remap(
        _ collapsed: Set<String>, from old: ParsedOrgDocument, to new: ParsedOrgDocument,
        move: OrgHeadingMove? = nil
    ) -> Set<String> {
        if let move, let expected = try? move.mutation.applied(to: old.root.text),
           expected.utf8.elementsEqual(new.root.text.utf8) {
            let starts = Set(old.root.children.filter {
                $0.type == "heading" && collapsed.contains($0.id)
            }.map { move.relocatedStartByte($0.startByte) })
            return Set(new.root.children.filter {
                $0.type == "heading" && starts.contains($0.startByte)
            }.map(\.id))
        }
        let oldKeys = keys(in: old)
        let selectedKeys = Set(collapsed.compactMap { oldKeys[$0] })
        return Set(keys(in: new).filter { selectedKeys.contains($0.value) }.map(\.key))
    }

    private static func keys(in document: ParsedOrgDocument) -> [String: String] {
        var parents: [(level: Int, key: String)] = []
        var occurrences: [String: Int] = [:]
        var result: [String: String] = [:]
        for node in document.root.children where node.type == "heading" {
            let marker = node.children.first { $0.type == "heading_marker" }?.text ?? node.text
            let level = max(1, marker.prefix { $0 == "*" }.count)
            while let last = parents.last, last.level >= level { parents.removeLast() }
            let title = node.children.first { $0.type == "heading_title" }?.text ?? node.text
            let parent = parents.last?.key ?? ""
            let base = "\(parent)/\(title.utf8.count):\(title)"
            let ordinal = occurrences[base, default: 0]
            occurrences[base] = ordinal + 1
            let key = "\(base)#\(ordinal)"
            result[node.id] = key
            parents.append((level, key))
        }
        return result
    }
}
