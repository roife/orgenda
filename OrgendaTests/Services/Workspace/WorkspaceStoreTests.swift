import XCTest
@testable import Orgenda

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_788_048_000)

    func testRapidMutationsInTwoFilesBothRefreshTheirParsedDocuments() async throws {
        let store = WorkspaceStore.preview(now: referenceDate)
        store.parseWorkspace()
        let inboxTree = try XCTUnwrap(store.parsedDocuments["inbox.org"]?.root)
        let notesTree = try XCTUnwrap(store.parsedDocuments["notes/reading.org"]?.root)
        let todo = try XCTUnwrap(firstNode(ofType: "todo_keyword", in: inboxTree))
        let checkbox = try XCTUnwrap(
            allNodes(ofType: "checkbox", in: notesTree).first(where: {
                $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "[ ]"
            })
        )

        XCTAssertTrue(
            store.applySourceReplacement(
                path: "inbox.org",
                startByte: todo.startByte,
                endByte: todo.endByte,
                expectedText: todo.text,
                replacement: "NEXT" + trailingWhitespace(in: todo.text)
            )
        )
        XCTAssertTrue(
            store.applySourceReplacement(
                path: "notes/reading.org",
                startByte: checkbox.startByte,
                endByte: checkbox.endByte,
                expectedText: checkbox.text,
                replacement: "[X]" + trailingWhitespace(in: checkbox.text)
            )
        )

        await store.waitForWorkspaceIndex()

        XCTAssertEqual(
            firstNode(ofType: "todo_keyword", in: try XCTUnwrap(store.parsedDocuments["inbox.org"]?.root))?
                .text.trimmingCharacters(in: .whitespacesAndNewlines),
            "NEXT"
        )
        XCTAssertTrue(
            allNodes(ofType: "checkbox", in: try XCTUnwrap(store.parsedDocuments["notes/reading.org"]?.root))
                .contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "[X]" }
        )
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

    private func parsedStore(_ contents: String, path: String = "inbox.org") -> WorkspaceStore {
        let store = WorkspaceStore(documents: [
            WorkspaceDocument(path: path, title: path, contents: contents, kind: .org)
        ], selectedDate: referenceDate)
        store.parseWorkspace()
        return store
    }

    private func trailingWhitespace(in token: String) -> String {
        String(token.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
    }

    private func firstNode(ofType type: String, in node: ParsedOrgNode) -> ParsedOrgNode? {
        if node.type == type { return node }
        return node.children.lazy.compactMap { self.firstNode(ofType: type, in: $0) }.first
    }

    private func allNodes(ofType type: String, in node: ParsedOrgNode) -> [ParsedOrgNode] {
        (node.type == type ? [node] : []) + node.children.flatMap { self.allNodes(ofType: type, in: $0) }
    }
}
