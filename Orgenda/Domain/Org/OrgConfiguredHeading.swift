import Foundation

enum OrgConfiguredHeading {
    static func workflow(in source: String, base: WorkspaceConfiguration.Workflow) -> WorkspaceConfiguration.Workflow {
        var sequences: [WorkspaceConfiguration.Sequence] = []
        var styles = base.keywords
        var inBlock = false
        for line in source.components(separatedBy: .newlines) {
            let upper = line.uppercased()
            if upper.hasPrefix("#+BEGIN_") { inBlock = true }
            if upper.hasPrefix("#+END_") { inBlock = false; continue }
            guard !inBlock, ["#+TODO:", "#+SEQ_TODO:", "#+TYP_TODO:"].contains(where: { upper.hasPrefix($0) }),
                  let colon = line.firstIndex(of: ":") else { continue }
            let words = line[line.index(after: colon)...].split(whereSeparator: \.isWhitespace).map(String.init)
            var process: [String] = []
            var terminal: [String] = []
            var done = false
            for word in words {
                if word == "|" { done = true; continue }
                let token = String(word.prefix { $0 != "(" })
                guard !token.isEmpty else { continue }
                var localStyle = styles[token] ?? .init()
                localStyle.key = ""
                localStyle.log = .init()
                if let opening = word.firstIndex(of: "("), word.hasSuffix(")") {
                    let markers = String(word[word.index(after: opening)..<word.index(before: word.endIndex)])
                    let parts = markers.components(separatedBy: "/")
                    localStyle.key = String(parts[0].prefix { $0 != "!" && $0 != "@" })
                    func rule(_ value: String) -> WorkspaceConfiguration.LogRule {
                        value.contains("@") ? .note : value.contains("!") ? .time : .none
                    }
                    localStyle.log.enter = rule(parts[0])
                    localStyle.log.leave = parts.count > 1 ? rule(parts[1]) : .none
                }
                styles[token] = localStyle
                if done { terminal.append(token) } else { process.append(token) }
            }
            if terminal.isEmpty, process.count > 1 { terminal.append(process.removeLast()) }
            guard let initial = process.first, let complete = terminal.first else { continue }
            sequences.append(.init(id: "file-\(sequences.count)", process: process, terminal: terminal,
                                   initial: initial, complete: complete, reopen: initial))
        }
        return sequences.isEmpty ? base : .init(sequences: sequences, keywords: styles)
    }

    /// Reconstruct just the heading metadata; retain inline descendants when
    /// they remain wholly inside the title, preserving Org markup and offsets.
    static func normalize(_ node: ParsedOrgNode, workflow: WorkspaceConfiguration.Workflow) -> ParsedOrgNode {
        guard node.type == "heading" else {
            return ParsedOrgNode(id: node.id, type: node.type, text: node.text, startByte: node.startByte,
                                 endByte: node.endByte, children: node.children.map { normalize($0, workflow: workflow) })
        }
        let bytes = Array(node.text.utf8)
        var position = 0
        while position < bytes.count && bytes[position] == 42 { position += 1 }
        while position < bytes.count && [9, 32].contains(bytes[position]) { position += 1 }
        var children = node.children.filter { $0.type == "heading_marker" || $0.type == "tag_list" }
        func make(_ type: String, _ start: Int, _ end: Int, children: [ParsedOrgNode] = []) -> ParsedOrgNode {
            ParsedOrgNode(id: "\(node.id):\(type):\(start)", type: type,
                          text: String(decoding: bytes[start..<end], as: UTF8.self),
                          startByte: node.startByte + start, endByte: node.startByte + end, children: children)
        }
        let tokenStart = position
        while position < bytes.count && ![9, 32, 10, 13].contains(bytes[position]) { position += 1 }
        let token = String(decoding: bytes[tokenStart..<position], as: UTF8.self)
        if workflow.state(token) != nil {
            while position < bytes.count && [9, 32].contains(bytes[position]) { position += 1 }
            children.append(make("todo_keyword", tokenStart, position))
        } else { position = tokenStart }
        let rest = String(decoding: bytes[position...], as: UTF8.self)
        if let range = rest.range(of: #"^\[#(?:[A-Z]|[0-9]{1,2})\][ \t]*"#, options: .regularExpression) {
            let end = position + rest[range].utf8.count
            children.append(make("priority", position, end))
            position = end
        }
        var end = node.children.first(where: { $0.type == "tag_list" }).map { $0.startByte - node.startByte } ?? bytes.count
        while end > position && [10, 13].contains(bytes[end - 1]) { end -= 1 }
        if end > position {
            let inline = node.children.first(where: { $0.type == "heading_title" })?.children.filter {
                $0.startByte >= node.startByte + position && $0.endByte <= node.startByte + end
            } ?? []
            children.append(make("heading_title", position, end, children: inline))
        }
        return ParsedOrgNode(id: node.id, type: node.type, text: node.text, startByte: node.startByte,
                             endByte: node.endByte, children: children.sorted { $0.startByte < $1.startByte })
    }
}
