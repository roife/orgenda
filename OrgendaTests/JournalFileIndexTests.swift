import XCTest
@testable import Orgenda

final class JournalFileIndexTests: XCTestCase {
    func testYearFilesRebuildMultipleEntriesAndPreserveSource() throws {
        let source = """
        #+TITLE: Journal
        * 2031-12-31 Wed
        ** Evening
        Last note of the year.

        * 2032-01-01 Thu
        ** Morning
        First note.
        ** Afternoon
        Second note.
        """
        let document = document(path: "journal/2032.org", contents: source)
        let entries = JournalFileIndex.entries(in: [document])

        XCTAssertEqual(entries.map(\.title), ["Evening", "Morning", "Afternoon"])
        XCTAssertEqual(entries.map(\.body), ["Last note of the year.", "First note.", "Second note."])
        XCTAssertEqual(dayKey(entries[0].date), "2031-12-31")
        XCTAssertEqual(dayKey(entries[1].date), "2032-01-01")
        XCTAssertEqual(entries[0].source.startLine, 3)
        XCTAssertEqual(sourceText(entries[1], in: source), "** Morning\nFirst note.\n")
        XCTAssertEqual(sourceText(entries[2], in: source), "** Afternoon\nSecond note.")
    }

    func testUnicodeOffsetsAndNestedSourceBlocksRemainIntact() throws {
        let source = """
        #+TITLE: 日記 🌱
        * 2028-02-29 Tue
        ** 早晨 ☕️
        今天的筆記。
        #+begin_src org
        * 2099-01-01 Thu
        ** 不是日記標題
        #+end_src
        *** 延伸
        更多內容。
        ** 晚安
        收尾。
        """
        let entries = JournalFileIndex.entries(in: [document(contents: source)])

        XCTAssertEqual(entries.map(\.title), ["早晨 ☕️", "晚安"])
        XCTAssertEqual(entries[0].source.startByte, "#+TITLE: 日記 🌱\n* 2028-02-29 Tue\n".utf8.count)
        XCTAssertEqual(entries[1].source.startLine, 11)
        XCTAssertEqual(sourceText(entries[1], in: source), "** 晚安\n收尾。")
        XCTAssertTrue(entries[0].body.contains("** 不是日記標題"))
        XCTAssertTrue(entries[0].body.contains("*** 延伸\n更多內容。"))
    }

    func testIDsSurviveReloadBodyEditsAndUnrelatedEarlierEntries() {
        let original = document(contents: "* 2026-09-12 Sat\n** Walk\nA walk.\n** Walk\nAnother walk.")
        let initial = JournalFileIndex.entries(in: [original])
        XCTAssertEqual(initial.map(\.id), JournalFileIndex.entries(in: [original]).map(\.id))
        XCTAssertNotEqual(initial[0].id, initial[1].id)

        let edited = document(contents: "* 2026-09-11 Fri\n** Reading\nA book.\n" + original.contents.replacingOccurrences(of: "A walk.", with: "A longer walk."))
        let reloaded = JournalFileIndex.entries(in: [edited]).filter { $0.title == "Walk" }
        XCTAssertEqual(initial.map(\.id), reloaded.map(\.id))
    }

    func testDailyOrgJournalFilenamesProvideDatesAndTimes() {
        let source = "* Friday, 25 December 2037\n** 09:15 Breakfast\nA quiet morning.\n** 21:40\nEvening note."
        let entries = JournalFileIndex.entries(in: [document(path: "personal/journal/20371225.org", contents: source)])
        XCTAssertEqual(entries.map(\.title), ["Breakfast", "Journal entry"])
        XCTAssertTrue(entries.allSatisfy { dayKey($0.date) == "2037-12-25" })
        XCTAssertEqual(Calendar.current.component(.hour, from: entries[0].date), 9)
        XCTAssertEqual(Calendar.current.component(.minute, from: entries[0].date), 15)
        XCTAssertEqual(Calendar.current.component(.hour, from: entries[1].date), 21)
    }

    func testInvalidDatesAndNonJournalFilesDoNotCreateEntries() {
        let entries = JournalFileIndex.entries(in: [
            document(path: "calendar.org", contents: "* 2026-09-12 Sat\n** Meeting\nAgenda."),
            document(path: "journal-notes/2026.org", contents: "* 2026-09-12 Sat\n** Note\nText."),
            document(contents: "* 2027-02-29 Mon\n** Invalid leap day\nText.\n* 2026-13-02 Mon\n** Invalid month\nText.\n* Project notes\n** Undated\nText."),
            document(path: "journal/20260230.org", contents: "** Invalid filename\nText.")
        ])
        XCTAssertTrue(entries.isEmpty)
    }

    func testDailyFileWithoutHeadingsAndDayBodyHaveUsefulEntries() {
        let entries = JournalFileIndex.entries(in: [
            document(path: "journal/2030-04-05.org", contents: "Just a note.\n"),
            document(path: "journal/2031.org", contents: "* 2031-06-01 Sun\nA day without an entry heading.\n")
        ])
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.body), ["Just a note.", "A day without an entry heading."])
        XCTAssertEqual(entries[0].source.startByte, 0)
        XCTAssertEqual(entries[0].source.endByte, "Just a note.\n".utf8.count)
    }

    private func document(path: String = "journal/2026.org", contents: String) -> WorkspaceDocument {
        WorkspaceDocument(path: path, title: "Journal", contents: contents, kind: .org)
    }

    private func sourceText(_ entry: JournalEntry, in source: String) -> String {
        String(decoding: Array(source.utf8)[entry.source.startByte..<entry.source.endByte], as: UTF8.self)
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
