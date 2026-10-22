import Foundation
import XCTest
@testable import Orgenda

@MainActor
final class WorkspaceStateDatabaseTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("StateDatabaseTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    func testStaleConnectionCannotOverwriteNewerDraft() throws {
        let first = try WorkspaceStateDatabase(directory: directory)
        defer { first.close() }
        let empty = WorkspaceState(identity: "workspace")
        var initial = empty
        initial.commitSequence = 1
        initial.pending["inbox.org"] = WorkspaceDraft(blob: "initial-blob")
        try first.save(initial, previous: empty, paths: nil, storeText: { $0 })

        let second = try WorkspaceStateDatabase(directory: directory)
        defer { second.close() }
        let stale = try second.load(identity: "workspace", text: { $0 })
        var newer = initial
        newer.commitSequence = 2
        newer.pending["inbox.org"]?.blob = "newer-blob"
        try first.save(newer, previous: initial, paths: ["inbox.org"], storeText: { $0 })

        var attempted = stale
        attempted.commitSequence += 1
        attempted.pending["inbox.org"]?.blob = "stale-blob"
        XCTAssertThrowsError(try second.save(attempted, previous: stale, paths: ["inbox.org"], storeText: { $0 }))
        let durable = try second.load(identity: "workspace", text: { $0 })
        XCTAssertEqual(durable.commitSequence, newer.commitSequence)
        XCTAssertEqual(durable.pending, newer.pending)
    }
}
