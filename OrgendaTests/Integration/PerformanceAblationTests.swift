import XCTest
@testable import Orgenda

/// Ablation benchmarks for the performance work. Each test runs the optimized
/// implementation and the pre-optimization algorithm on identical input and
/// prints `ABLATION <name>: old=…ms new=…ms speedup=…×` so every change can be
/// justified with data. Numbers are from Debug builds; relative ratios are the
/// signal, absolute values are indicative only.
@MainActor
final class PerformanceAblationTests: XCTestCase {

    private func milliseconds(_ iterations: Int, _ body: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations { body() }
        return (CFAbsoluteTimeGetCurrent() - start) * 1_000 / Double(iterations)
    }

    private func report(_ name: String, old: Double, new: Double) {
        let speedup = old / max(new, 0.000_001)
        print(String(format: "ABLATION %@: old=%.3fms new=%.3fms speedup=%.2fx", name, old, new, speedup))
    }

    private func reportOneSided(_ name: String, label: String, value: Double) {
        print(String(format: "ABLATION %@: %@=%.3fms (removed from the hot path)", name, label, value))
    }

    // MARK: - Fixtures

    private func orgSource(headings: Int, bodyLines: Int = 6) -> String {
        var source = "#+title: Ablation\n"
        for index in 0..<headings {
            source += "* TODO [#B] Task number \(index) :work:\n"
            source += "SCHEDULED: <2026-09-\(String(format: "%02d", index % 28 + 1)) Tue 09:30-10:30 +1w -2d> DEADLINE: <2026-10-\(String(format: "%02d", index % 28 + 1)) Thu 17:00>\n"
            for line in 0..<bodyLines {
                source += "Body line \(line) for task \(index) with some realistic prose text.\n"
            }
        }
        return source
    }

    private func makeStore(headings: Int, files: Int = 3) -> WorkspaceStore {
        let documents = (0..<files).map { file in
            WorkspaceDocument(
                path: file == 0 ? "agenda/actions.org" : "notes/file\(file).org",
                title: "File \(file)",
                contents: orgSource(headings: headings / files + (file == 0 ? headings % files : 0)),
                kind: .org
            )
        }
        let store = WorkspaceStore(documents: documents)
        store.parseWorkspace()
        return store
    }

    // MARK: - A1/A2: regex compilation on hot paths

    private func planningLineOld(named name: String, in planning: String) -> String? {
        let pattern = "\(name):[ \\t]*(<[^>\\r\\n]+>|\\[[^]\\r\\n]+\\])(?:--(<[^>\\r\\n]+>|\\[[^]\\r\\n]+\\]))?"
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: planning, range: NSRange(planning.startIndex..., in: planning)),
            let firstRange = Range(match.range(at: 1), in: planning)
        else { return nil }
        return String(planning[firstRange])
    }

    private static let staticPlanningExpressions: [String: NSRegularExpression] = {
        ["SCHEDULED", "DEADLINE", "CLOSED"].reduce(into: [:]) { result, name in
            let pattern = "\(name):[ \\t]*(<[^>\\r\\n]+>|\\[[^]\\r\\n]+\\])(?:--(<[^>\\r\\n]+>|\\[[^]\\r\\n]+\\]))?"
            result[name] = try? NSRegularExpression(pattern: pattern)
        }
    }()

    private func planningLineNew(named name: String, in planning: String) -> String? {
        guard
            let regex = Self.staticPlanningExpressions[name],
            let match = regex.firstMatch(in: planning, range: NSRange(planning.startIndex..., in: planning)),
            let firstRange = Range(match.range(at: 1), in: planning)
        else { return nil }
        return String(planning[firstRange])
    }

    func testAblation_A1_planningRegexPerHeading() {
        let planning = "SCHEDULED: <2026-09-20 Sun 09:30-10:30 +1w> DEADLINE: <2026-10-01 Thu 17:00> CLOSED: [2026-09-21 Mon 10:00]"
        var sink = 0
        let old = milliseconds(3_000) {
            sink += planningLineOld(named: "SCHEDULED", in: planning)?.count ?? 0
            sink += planningLineOld(named: "DEADLINE", in: planning)?.count ?? 0
            sink += planningLineOld(named: "CLOSED", in: planning)?.count ?? 0
        }
        let new = milliseconds(3_000) {
            sink += planningLineNew(named: "SCHEDULED", in: planning)?.count ?? 0
            sink += planningLineNew(named: "DEADLINE", in: planning)?.count ?? 0
            sink += planningLineNew(named: "CLOSED", in: planning)?.count ?? 0
        }
        XCTAssertGreaterThan(sink, 0)
        report("A1-planning-regex", old: old, new: new)
    }

    func testAblation_A2_repeaterInitPerRow() {
        var sink = 0
        let old = milliseconds(5_000) {
            if let expression = try? NSRegularExpression(
                pattern: #"\A(\+\+|\.\+|\+)([1-9]\d*)([hdwmy])(?:/([1-9]\d*)([hdwmy]))?\z"#
            ), let match = expression.firstMatch(in: "+1w", range: NSRange(location: 0, length: 3)) {
                sink += match.numberOfRanges
            }
        }
        let new = milliseconds(5_000) {
            sink += OrgRepeater("+1w")?.interval ?? 0
        }
        XCTAssertGreaterThan(sink, 0)
        report("A2-repeater-regex", old: old, new: new)
    }

    // MARK: - A3: date formatting

    func testAblation_A3_orgendaDayKey() {
        let dates = (0..<400).map { Date(timeIntervalSince1970: 1_788_048_000).adding(days: $0 - 30) }
        let calendar = Calendar.autoupdatingCurrent
        var sink = 0
        let old = milliseconds(200) {
            for date in dates {
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                sink += String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0).count
            }
        }
        let new = milliseconds(200) {
            for date in dates { sink += date.orgendaDayKey.count }
        }
        XCTAssertGreaterThan(sink, 0)
        report("A3-orgendaDayKey", old: old, new: new)
    }

    func testAblation_A3_previewDateFormatter() {
        let locale = Locale.autoupdatingCurrent
        let date = Date(timeIntervalSince1970: 1_788_048_000)
        var sink = 0
        let old = milliseconds(1_000) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate("MMM d EEE")
            sink += formatter.string(from: date).count
            formatter.setLocalizedDateFormatFromTemplate("jmm")
            sink += formatter.string(from: date).count
        }
        var cache: [String: DateFormatter] = [:]
        func cached(_ template: String) -> DateFormatter {
            if let formatter = cache[template] { return formatter }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate(template)
            cache[template] = formatter
            return formatter
        }
        let new = milliseconds(1_000) {
            sink += cached("MMM d EEE").string(from: date).count
            sink += cached("jmm").string(from: date).count
        }
        XCTAssertGreaterThan(sink, 0)
        report("A3-preview-formatter", old: old, new: new)
    }

    // MARK: - B: workspace pipeline

    func testAblation_B1_parseWorkspaceMainThreadBlocking() {
        let store = makeStore(headings: 300)
        let blocking = milliseconds(5) { store.parseWorkspace() }
        reportOneSided("B1-sync-parseWorkspace", label: "main-thread-block", value: blocking)
    }

    func testAblation_B3_derivedCollections() {
        let store = makeStore(headings: 400)
        let date = Date(timeIntervalSince1970: 1_788_048_000)
        var sink = 0

        // Pre-optimization: every access re-filtered and re-sorted.
        func legacyDatedItems() -> [OrgItem] {
            store.items
                .filter { $0.agendaDate != nil }
                .sorted { $0.agendaDate! < $1.agendaDate! }
        }
        func legacyItems(on day: Date) -> [OrgItem] {
            legacyDatedItems().compactMap { item in
                let dates = [item.scheduled, item.deadline, item.eventDate].compactMap { $0 }
                return dates.contains(where: { Calendar.autoupdatingCurrent.isDate($0, inSameDayAs: day) }) ? item : nil
            }
        }
        let old = milliseconds(60) {
            sink += legacyDatedItems().count
            sink += legacyItems(on: date).count
            sink += legacyItems(on: date.adding(days: 1)).count
        }
        let new = milliseconds(60) {
            sink += store.datedItems.count
            sink += store.items(on: date).count
            sink += store.items(on: date.adding(days: 1)).count
        }
        XCTAssertGreaterThan(sink, 0)
        report("B3-derived-collections", old: old, new: new)
    }

    func testAblation_B4_mergingMatchComplexity() {
        // Algorithm-level comparison: per-heading full-array scans (old) versus
        // a per-file candidate index built once (new). 300 headings × 600 items.
        struct Item { let file: String; let startByte: Int; let title: String }
        struct Heading { let file: String; let startByte: Int; let title: String }
        let items = (0..<600).map { Item(file: "f\($0 % 5).org", startByte: $0 * 100, title: "Task \($0)") }
        let headings = (0..<300).map { Heading(file: "f\($0 % 5).org", startByte: $0 * 200, title: "Task \($0 * 2)") }
        var sink = 0

        let old = milliseconds(200) {
            var matched: Set<Int> = []
            for heading in headings {
                let available = items.indices.filter { items[$0].file == heading.file && !matched.contains($0) }
                if let index = available.first(where: { items[$0].startByte == heading.startByte && items[$0].title == heading.title })
                    ?? available.first(where: { items[$0].title == heading.title }) {
                    matched.insert(index)
                    sink += 1
                }
            }
        }
        let new = milliseconds(200) {
            var byFile = Dictionary(grouping: items.indices, by: { items[$0].file })
            for heading in headings {
                let candidates = byFile[heading.file] ?? []
                if let position = candidates.firstIndex(where: { items[$0].startByte == heading.startByte && items[$0].title == heading.title })
                    ?? candidates.firstIndex(where: { items[$0].title == heading.title }) {
                    byFile[heading.file]?.remove(at: position)
                    sink += 1
                }
            }
        }
        XCTAssertGreaterThan(sink, 0)
        report("B4-merging-match", old: old, new: new)
    }

    func testAblation_B5_lineNumberRepair() {
        let contents = orgSource(headings: 120, bodyLines: 20)
        let offsets = stride(from: 0, to: contents.utf8.count, by: max(1, contents.utf8.count / 100)).map { $0 }
        var sink = 0
        let old = milliseconds(100) {
            for offset in offsets {
                sink += 1 + contents.utf8.prefix(offset).filter { $0 == 10 }.count
            }
        }
        let new = milliseconds(100) {
            var starts = [0]
            var cursor = 0
            for byte in contents.utf8 {
                if byte == 10 { starts.append(cursor + 1) }
                cursor += 1
            }
            for offset in offsets {
                var lower = 0, upper = starts.count
                while lower < upper {
                    let middle = (lower + upper) / 2
                    if starts[middle] <= offset { lower = middle + 1 } else { upper = middle }
                }
                sink += lower
            }
        }
        XCTAssertGreaterThan(sink, 0)
        report("B5-line-number-repair", old: old, new: new)
    }

    func testAblation_R1_reminderPlanReusesParsedDocuments() {
        let store = makeStore(headings: 150)
        let parsed = store.parsedDocuments
        let items = store.items
        let documents = store.documents
        var sink = 0
        let old = milliseconds(10) {
            sink += OrgReminderPlan.reminders(for: items, documents: documents).count
        }
        let new = milliseconds(10) {
            sink += OrgReminderPlan.reminders(for: items, parsed: parsed).count
        }
        report("R1-reminder-plan", old: old, new: new)
    }

    func testAblation_B2_planningDraftBeforeParse() {
        let store = makeStore(headings: 200, files: 1)
        guard let document = store.documents.first else { return XCTFail("missing document") }
        let parseCost = milliseconds(20) {
            _ = OrgIndexService.parseSynchronously([document])
        }
        reportOneSided("B2-before-parse-saved", label: "saved-parse", value: parseCost)
    }

    // MARK: - C: view-layer recomputation

    func testAblation_C1_previewRowsPerScrollFrame() {
        let store = makeStore(headings: 250, files: 1)
        guard let parsed = store.parsedDocuments.values.first else { return XCTFail("missing parse") }
        let children = parsed.root.children
        var sink = 0
        let perRebuild = milliseconds(50) {
            sink += OrgPreviewOutline.rows(from: children).count
        }
        XCTAssertGreaterThan(sink, 0)
        // Old behaviour: one rebuild per scroll frame (~60/s). New: zero.
        report("C1-preview-rows-per-second-at-60fps", old: perRebuild * 60, new: 0)
    }

    func testAblation_C2_timelineDaysPerBodyEvaluation() {
        let anchor = Date(timeIntervalSince1970: 1_788_048_000).startOfDay
        var sink = 0
        let perRebuild = milliseconds(100) {
            sink += (-30...365).map { anchor.adding(days: $0).orgendaDayKey.count }.reduce(0, +)
        }
        XCTAssertGreaterThan(sink, 0)
        report("C2-timeline-days-per-body-eval", old: perRebuild, new: 0)
    }

    func testAblation_C4_headingCountSplit() {
        let store = makeStore(headings: 150, files: 1)
        guard let document = store.documents.first else { return XCTFail("missing document") }
        var sink = 0
        let old = milliseconds(300) {
            sink += document.contents.split(separator: "\n").filter { $0.hasPrefix("*") }.count
        }
        let new = milliseconds(300) {
            sink += store.parsedDocuments[document.path]?.headings.count ?? 0
        }
        XCTAssertGreaterThan(sink, 0)
        report("C4-heading-count", old: old, new: new)
    }

    func testAblation_C3_searchScanPerKeystroke() {
        let store = makeStore(headings: 300)
        var sink = 0
        let perScan = milliseconds(30) {
            sink += store.search("task 42", scope: .all).count
        }
        XCTAssertGreaterThan(sink, 0)
        // Old: one full scan per keystroke (12 chars here). New: one debounced scan.
        report("C3-search-per-12char-query", old: perScan * 12, new: perScan)
    }
}
