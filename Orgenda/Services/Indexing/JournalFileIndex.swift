import CryptoKit
import Foundation
import OrgTreeSitter

/// Reconstructs journal cards from their saved source without depending on a
/// particular year or on the lifetime of the workspace store.
enum JournalFileIndex {
    static func entries(in documents: [WorkspaceDocument]) -> [JournalEntry] {
        let parser = OrgParser()
        var entries: [JournalEntry] = []
        var occurrences: [String: Int] = [:]

        for document in documents.sorted(by: { $0.path < $1.path }) {
            guard document.kind == .org,
                  document.path.split(separator: "/").dropLast().contains(where: {
                      $0.lowercased() == "journal"
                  })
            else { continue }

            let bytes = Array(document.contents.utf8)
            let headings = parser.parse(document.contents).rootNode.namedChildren
                .filter { $0.type == "heading" }
                .map { node in
                    Heading(
                        level: node.text.prefix(while: { $0 == "*" }).count,
                        title: String(node.text.drop(while: { $0 == "*" }))
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                        startByte: Int(node.startByte), endByte: Int(node.endByte),
                        startLine: Int(node.startPoint.row) + 1
                    )
                }
            let filename = URL(fileURLWithPath: document.path).deletingPathExtension().lastPathComponent
            let filenameDay = Day(filename: filename)

            func append(day: Day, title: String, bodyStart: Int, sourceStart: Int, end: Int, line: Int) {
                let body = String(decoding: bytes[bodyStart..<end], as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let (date, displayTitle) = day.entry(title: title)
                let identity = "\(document.path)\u{0}\(day.key)\u{0}\(title)"
                let occurrence = occurrences[identity, default: 0]
                occurrences[identity] = occurrence + 1
                entries.append(JournalEntry(
                    id: stableID("\(identity)\u{0}\(occurrence)"),
                    date: date, title: displayTitle, body: body,
                    source: SourceLocation(
                        file: document.path, startByte: sourceStart, endByte: end, startLine: line
                    )
                ))
            }

            var currentDay = filenameDay
            for (index, heading) in headings.enumerated() {
                if heading.level == 1 {
                    currentDay = Day(heading: heading.title) ?? filenameDay
                }
                guard let day = currentDay, heading.level <= 2 else { continue }
                let following = headings.dropFirst(index + 1)
                let end = following.first(where: { $0.level <= heading.level })?.startByte ?? bytes.count

                if heading.level == 1 {
                    // A day heading groups its level-two entries. Its source is
                    // only a card when the day has body text and no such entries.
                    guard !following.prefix(while: { $0.level > 1 }).contains(where: { $0.level == 2 }),
                          !String(decoding: bytes[heading.endByte..<end], as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else { continue }
                }

                append(day: day, title: heading.title, bodyStart: heading.endByte,
                       sourceStart: heading.startByte, end: end, line: heading.startLine)
            }

            if headings.isEmpty, let day = filenameDay,
               !document.contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                append(day: day, title: document.title, bodyStart: 0,
                       sourceStart: 0, end: bytes.count, line: 1)
            }
        }
        return entries
    }

    private struct Heading {
        let level: Int
        let title: String
        let startByte: Int
        let endByte: Int
        let startLine: Int
    }

    private struct Day {
        let date: Date
        let key: String

        private static let headingDayExpression = try? NSRegularExpression(
            pattern: #"^\d{4}-\d{2}-\d{2}(?=\s|$)"#
        )
        private static let compactFilenameExpression = try? NSRegularExpression(pattern: #"^\d{8}$"#)
        private static let filenameDayExpression = try? NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}$"#)
        private static let timePrefixExpression = try? NSRegularExpression(pattern: #"^\d{2}:\d{2}(?=\s|$)"#)

        private static func firstRange(
            _ expression: NSRegularExpression?, in source: String
        ) -> Range<String.Index>? {
            expression?
                .firstMatch(in: source, range: NSRange(source.startIndex..., in: source))
                .flatMap { Range($0.range, in: source) }
        }

        init?(heading: String) {
            guard let match = Self.firstRange(Self.headingDayExpression, in: heading)
            else { return nil }
            self.init(key: String(heading[match]))
        }

        init?(filename: String) {
            if Self.firstRange(Self.compactFilenameExpression, in: filename) != nil {
                let digits = Array(filename)
                self.init(key: String(digits[0..<4]) + "-" + String(digits[4..<6]) + "-" + String(digits[6..<8]))
            } else {
                guard Self.firstRange(Self.filenameDayExpression, in: filename) != nil
                else { return nil }
                self.init(key: filename)
            }
        }

        private init?(key: String) {
            let values = key.split(separator: "-").compactMap { Int($0) }
            guard values.count == 3 else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .autoupdatingCurrent
            let components = DateComponents(year: values[0], month: values[1], day: values[2])
            guard let date = calendar.date(from: components),
                  calendar.dateComponents([.year, .month, .day], from: date) == components
            else { return nil }
            self.date = date
            self.key = key
        }

        func entry(title: String) -> (Date, String) {
            guard let range = Self.firstRange(Self.timePrefixExpression, in: title)
            else { return (date, title) }
            let time = title[range].split(separator: ":").compactMap { Int($0) }
            guard time.count == 2, (0..<24).contains(time[0]), (0..<60).contains(time[1])
            else { return (date, title) }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .autoupdatingCurrent
            let timedDate = calendar.date(bySettingHour: time[0], minute: time[1], second: 0, of: date) ?? date
            let text = title[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (timedDate, text.isEmpty ? String(localized: "Journal entry") : text)
        }
    }

    private static func stableID(_ identity: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(identity.utf8)).prefix(16))
        // A name-derived custom UUID; unlike Hasher this survives process restarts.
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
