import XCTest
@testable import Orgenda

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_788_048_000)

    func testTransferredCustomStatePreservesMetadataAndRejectsStaleSource() throws {
        let source = "#+TODO: OPEN | FINISHED(!)\n* Parent\n** FINISHED Task\nOriginal notes.\n"
        let store = parsedStore(source)
        let original = try XCTUnwrap(store.items.first)
        let encoded = try JSONEncoder().encode(OrgTaskTransfer(item: original))
        let transfer = try JSONDecoder().decode(OrgTaskTransfer.self, from: encoded)
        XCTAssertEqual(transfer.item, original)
        XCTAssertTrue(transfer.item.state.isTerminal)
        XCTAssertEqual(transfer.item.state.enterLog, .time)
        XCTAssertEqual(transfer.item.source.ancestorTitles, ["Parent"])

        let current = source.replacingOccurrences(of: "Original notes.", with: "Newer notes.")
        store.updateDocument(path: "inbox.org", contents: current)
        var edited = transfer.item
        edited.title = "Edited title"
        XCTAssertFalse(store.save(edited, original: transfer.item))
        XCTAssertEqual(store.documents.first?.contents, current)
    }

    func testStaleEditorBaselineRejectsNewerSourceNotesBeforeAndAfterReindex() throws {
        for reindex in [false, true] {
            let store = parsedStore("* TODO Original\nOriginal notes.\n")
            let baseline = try XCTUnwrap(store.items.first)
            var draft = baseline
            draft.title = "Edited title"
            store.updateDocument(path: "inbox.org", contents: "* TODO Original\nNewer source notes.\n")
            if reindex { store.parseWorkspace() }

            XCTAssertFalse(store.save(draft, original: baseline))
            XCTAssertEqual(store.documents.first?.contents, "* TODO Original\nNewer source notes.\n")
            XCTAssertEqual(draft.body, "Original notes.")
        }
    }

    func testImmediateEditAfterUnicodeSourceChangePreservesCurrentBytes() throws {
        for (before, after) in [("Café", "Cafe\u{301}"), ("Cafe\u{301}", "Café")] {
            let store = parsedStore("* TODO \(before)\nBody.\n* TODO Tail\n")
            var draft = try XCTUnwrap(store.items.first)
            let current = "* TODO \(after)\nBody.\n* TODO Tail\n"
            store.updateDocument(path: "inbox.org", contents: current)

            let exact = try XCTUnwrap(store.exactSource(for: draft))
            XCTAssertTrue(exact.utf8.elementsEqual("* TODO \(after)\nBody.\n".utf8))
            draft.state = store.configuration.workflow.toggled(draft.state)
            XCTAssertTrue(store.save(draft))
            XCTAssertTrue(try XCTUnwrap(store.documents.first?.contents).utf8.elementsEqual(
                "* DONE \(after)\nBody.\n* TODO Tail\n".utf8
            ))
        }
    }

    func testPlanningEditAfterUnicodeSourceChangeKeepsRequiredHistory() throws {
        let store = parsedStore("* Café\n* TODO Task\nSCHEDULED: <2026-10-18 Sun>\n")
        store.configuration.logging.reschedule = .time
        let current = "* Cafe\u{301}\n* TODO Task\nSCHEDULED: <2026-10-18 Sun>\n"
        store.updateDocument(path: "inbox.org", contents: current)
        let parsed = try XCTUnwrap(OrgIndexService.parseSynchronously(
            store.documents, configuration: store.configuration
        ).first)
        let node = try XCTUnwrap(firstNode(ofType: "planning_entry", in: parsed.root))
        var draft = try XCTUnwrap(OrgPlanningEntryDraft(source: node.text))
        draft.timestamps[0].date = try XCTUnwrap(Date.orgTimestamp(year: 2026, month: 10, day: 19))

        XCTAssertTrue(store.applyPlanningDraft(path: "inbox.org", node: node, draft: draft))
        let contents = try XCTUnwrap(store.documents.first?.contents)
        XCTAssertTrue(contents.utf8.starts(with: "* Cafe\u{301}\n* TODO Task\n".utf8))
        XCTAssertTrue(contents.contains("SCHEDULED: <2026-10-19 Mon>"))
        XCTAssertTrue(contents.contains("Rescheduled from"))
    }

    func testCaptureRejectsCanonicallyEqualButStaleDestination() throws {
        let before = "* TODO Café\n"
        let after = "* TODO Cafe\u{301}\n"
        let store = parsedStore(before)
        store.updateDocument(path: "inbox.org", contents: after)
        let template = WorkspaceConfiguration.Template()

        XCTAssertFalse(store.capture(template, rendered: "* TODO New\n", date: referenceDate,
                                     createMissing: false, expectedContents: before))
        XCTAssertTrue(try XCTUnwrap(store.documents.first?.contents).utf8.elementsEqual(after.utf8))
        XCTAssertTrue(store.capture(template, rendered: "* TODO New\n", date: referenceDate,
                                    createMissing: false, expectedContents: after))
    }

    func testConfigurationRefreshKeepsExactSourceForTheNextSave() throws {
        let store = WorkspaceStore()
        let suite = "OrgendaConfigurationAudit-" + UUID().uuidString
        store.connectionDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.connectionDefaults.removePersistentDomain(forName: suite) }
        let before = "{\"version\":1,\"files\":{\"journal\":\"Café\"}}"
        let after = "{\"version\":1,\"files\":{\"journal\":\"Cafe\u{301}\"}}"
        XCTAssertTrue(store.acceptConfiguration(before))
        let revision = store.configurationRevision

        XCTAssertTrue(store.acceptConfiguration(after))
        XCTAssertEqual(store.configurationRevision, revision + 1)
        XCTAssertTrue(try XCTUnwrap(store.configurationSource).utf8.elementsEqual(after.utf8))
        let encoded = try store.configurationDocument.encoded(store.configuration)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        let files = try XCTUnwrap(object["files"] as? [String: Any])
        XCTAssertTrue(try XCTUnwrap(files["journal"] as? String).utf8.elementsEqual("Cafe\u{301}".utf8))
    }

    private func parsedStore(_ contents: String) -> WorkspaceStore {
        let store = WorkspaceStore(documents: [
            WorkspaceDocument(path: "inbox.org", title: "inbox.org", contents: contents, kind: .org)
        ], selectedDate: referenceDate)
        store.parseWorkspace()
        return store
    }

    private func firstNode(ofType type: String, in node: ParsedOrgNode) -> ParsedOrgNode? {
        if node.type == type { return node }
        return node.children.lazy.compactMap { self.firstNode(ofType: type, in: $0) }.first
    }

}
