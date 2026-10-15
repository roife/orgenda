import Foundation

/// A conservative byte-exact line merge. Disjoint edits are combined; touching
/// insertions or overlapping replacements remain explicit user conflicts.
enum WorkspaceTextMerge {
    private struct Edit {
        var range: Range<Int>
        var replacement: [Data]
    }

    static func merge(base: String, local: String, remote: String) -> String? {
        let baseBytes = Data(base.utf8), localBytes = Data(local.utf8), remoteBytes = Data(remote.utf8)
        if localBytes == remoteBytes { return local }
        if localBytes == baseBytes { return remote }
        if remoteBytes == baseBytes { return local }
        let source = lines(baseBytes)
        let localEdits = edits(from: source, to: lines(localBytes))
        let remoteEdits = edits(from: source, to: lines(remoteBytes))
        var merged = localEdits
        for incoming in remoteEdits {
            var duplicate = false
            for existing in localEdits {
                if existing.range == incoming.range && existing.replacement == incoming.replacement { duplicate = true; break }
                let overlaps: Bool
                if existing.range.isEmpty { overlaps = incoming.range.lowerBound <= existing.range.lowerBound && existing.range.lowerBound <= incoming.range.upperBound }
                else if incoming.range.isEmpty { overlaps = existing.range.lowerBound <= incoming.range.lowerBound && incoming.range.lowerBound <= existing.range.upperBound }
                else { overlaps = existing.range.overlaps(incoming.range) }
                if overlaps { return nil }
            }
            if !duplicate { merged.append(incoming) }
        }
        var result = Data(), cursor = 0
        for edit in merged.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            guard edit.range.lowerBound >= cursor else { return nil }
            for line in source[cursor..<edit.range.lowerBound] { result.append(line) }
            for line in edit.replacement { result.append(line) }
            cursor = edit.range.upperBound
        }
        for line in source[cursor...] { result.append(line) }
        return String(data: result, encoding: .utf8)
    }

    private static func lines(_ bytes: Data) -> [Data] {
        var result: [Data] = [], start = bytes.startIndex
        for index in bytes.indices where bytes[index] == 10 {
            result.append(bytes[start...index])
            start = bytes.index(after: index)
        }
        if start < bytes.endIndex { result.append(bytes[start...]) }
        return result
    }

    private static func edits(from base: [Data], to target: [Data]) -> [Edit] {
        var removed = Set<Int>(), inserted: [Int: Data] = [:]
        for change in target.difference(from: base) {
            switch change {
            case .remove(let index, _, _): removed.insert(index)
            case .insert(let index, let value, _): inserted[index] = value
            }
        }
        var result: [Edit] = [], sourceIndex = 0, targetIndex = 0
        while sourceIndex < base.count || targetIndex < target.count {
            if removed.contains(sourceIndex) || inserted[targetIndex] != nil {
                let start = sourceIndex
                var replacement: [Data] = []
                while true {
                    if removed.contains(sourceIndex) { sourceIndex += 1 }
                    else if let value = inserted[targetIndex] { replacement.append(value); targetIndex += 1 }
                    else { break }
                }
                result.append(Edit(range: start..<sourceIndex, replacement: replacement))
            } else { sourceIndex += 1; targetIndex += 1 }
        }
        return result
    }
}
