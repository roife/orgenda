import Foundation

enum OrgHeadingPlacement: Equatable {
    case before, after, child
}

/// Moves an intact subtree and changes only its parsed heading markers.
struct OrgHeadingMove {
    let mutation: OrgSourceMutation
    private let relocatedSources: [Int: SourceLocation]

    func relocatedStartByte(_ byte: Int) -> Int {
        relocatedSources[byte]?.startByte ?? byte
    }

    func relocatedSource(_ source: SourceLocation) -> SourceLocation {
        relocatedSources[source.startByte] ?? source
    }

    static func plan(
        in document: ParsedOrgDocument,
        headingID: String,
        targetID: String,
        placement: OrgHeadingPlacement
    ) -> OrgHeadingMove? {
        let sections = OrgHeadingSection.sections(in: document)
        guard let heading = sections.first(where: { $0.id == headingID }),
              let target = sections.first(where: { $0.id == targetID }),
              !(heading.startByte..<heading.endByte).contains(target.startByte) else { return nil }
        let insertion = placement == .before ? target.startByte : target.endByte
        let newLevel = target.level + (placement == .child ? 1 : 0)
        let levelDelta = newLevel - heading.level
        guard insertion <= heading.startByte || insertion >= heading.endByte else { return nil }
        guard levelDelta != 0 || (insertion != heading.startByte && insertion != heading.endByte) else {
            return nil
        }

        let lower = min(insertion, heading.startByte)
        let upper = max(insertion, heading.endByte)
        let subtree = heading.startByte..<heading.endByte
        let ranges = (insertion <= heading.startByte
            ? [subtree, insertion..<heading.startByte]
            : [heading.endByte..<insertion, subtree]).filter { !$0.isEmpty }
        let bytes = document.root.text.utf8
        let newline = document.root.text.contains("\r\n") ? "\r\n" : "\n"
        var replacement = ""
        var relocated: [Int: SourceLocation] = [:]
        for (index, range) in ranges.enumerated() {
            let headings = document.headings.filter { range.contains($0.source.startByte) }
            let changedLevels = range == subtree ? levelDelta : 0
            var text = String(decoding: bytes.dropFirst(range.lowerBound).prefix(range.count), as: UTF8.self)
            if changedLevels != 0 {
                for section in sections.reversed() where range.contains(section.startByte) {
                    let marker = OrgSourceMutation(
                        startByte: section.startByte - range.lowerBound,
                        endByte: section.startByte - range.lowerBound + section.level,
                        replacement: String(repeating: "*", count: section.level + changedLevels)
                    )
                    guard let updated = try? marker.applied(to: text) else { return nil }
                    text = updated
                }
            }
            // A former EOF without a newline must not swallow the next heading.
            let separator = !text.hasSuffix("\n") && (index + 1 < ranges.count || upper < bytes.count)
                ? newline : ""
            let outputStart = lower + replacement.utf8.count
            for (ordinal, heading) in headings.enumerated() {
                var source = heading.source
                source.startByte = outputStart + heading.source.startByte - range.lowerBound
                    + ordinal * changedLevels
                source.endByte = source.startByte + heading.source.endByte - heading.source.startByte
                    + changedLevels + (heading.source.endByte == range.upperBound ? separator.utf8.count : 0)
                relocated[heading.source.startByte] = source
            }
            replacement += text + separator
        }
        let delta = replacement.utf8.count - (upper - lower)
        for heading in document.headings where relocated[heading.source.startByte] == nil {
            var source = heading.source
            if source.startByte >= upper {
                source.startByte += delta
                source.endByte += delta
            }
            relocated[heading.source.startByte] = source
        }
        return OrgHeadingMove(
            mutation: OrgSourceMutation(startByte: lower, endByte: upper,
                                        replacement: replacement),
            relocatedSources: relocated
        )
    }
}

struct OrgHeadingSection: Identifiable {
    let id: String
    let level: Int
    let parentID: String?
    let startByte: Int
    var endByte: Int

    static func sections(in document: ParsedOrgDocument) -> [OrgHeadingSection] {
        var result: [OrgHeadingSection] = []
        var ancestors: [Int] = []
        for node in document.root.children where node.type == "heading" {
            let marker = node.children.first { $0.type == "heading_marker" }?.text ?? node.text
            let level = max(1, marker.prefix { $0 == "*" }.count)
            while let index = ancestors.last, result[index].level >= level {
                result[index].endByte = node.startByte
                ancestors.removeLast()
            }
            let parentID = ancestors.last.map { result[$0].id }
            ancestors.append(result.count)
            result.append(OrgHeadingSection(id: node.id, level: level, parentID: parentID,
                                            startByte: node.startByte, endByte: document.root.text.utf8.count))
        }
        return result
    }
}
