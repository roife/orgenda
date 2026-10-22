import XCTest
@testable import Orgenda

final class ConfigurationValidationTests: XCTestCase {
    func testReadingAndSavingRejectDestinationsThatEscapeOrChangeFileStructure() throws {
        let invalidEdits: [(inout WorkspaceConfiguration) -> Void] = [
            { $0.files.inbox = "../outside.org" },
            { $0.capture.templates[0].target.path = "/outside.org" },
            { $0.capture.templates[0].target.path = "folder/../outside.org" },
            { $0.files.refile = ["folder//tasks.org"] },
            { $0.files.archive = "../outside.org::* Archived" },
            { $0.files.archive = "notes.txt::* Archived" },
            { $0.files.archive = "%s_archive::Archived" },
            { $0.files.archive = "%s_archive::* Archived\n* Injected" },
            { $0.logging.drawer = "END" },
            { $0.logging.drawer = "properties" },
            { $0.logging.drawer = "LOGBOOK\n:END:\n* Injected" }
        ]
        let document = ConfigurationDocument(configuration: .standard)
        for edit in invalidEdits {
            var configuration = WorkspaceConfiguration.standard
            edit(&configuration)
            let json = String(decoding: try JSONEncoder().encode(configuration), as: UTF8.self)
            XCTAssertThrowsError(try ConfigurationDocument(json), json)
            XCTAssertThrowsError(try document.encoded(configuration), json)
        }
    }

    func testHyphenatedLogDrawerRetainsExistingLogsAndNeighboringSource() throws {
        var configuration = WorkspaceConfiguration.standard
        configuration.logging = .init(done: .time, drawer: "狀態-LOG")
        XCTAssertNil(ConfigurationValidation.drawerMessage(configuration.logging.drawer))
        let encoded = try ConfigurationDocument(configuration: .standard).encoded(configuration)
        let logging = try ConfigurationDocument(encoded).configuration.logging
        let source = "* DONE Example\n:狀態-LOG:\nOld log\n:END:\nBody\n* Neighbor\nUntouched\n"
        let original = OrgItem(id: UUID(), title: "Example", state: configuration.workflow.initial, kind: .task, priority: .none,
            tags: [], scheduled: nil, deadline: nil, hasTime: false, durationMinutes: 30,
            recurrence: nil, body: "Body", source: SourceLocation(file: "inbox.org", startByte: 0, endByte: 0, startLine: 1),
            habitHistory: [])
        var completed = original
        completed.state = configuration.workflow.toggled(original.state)
        let result = try OrgWorkflowOperations.applyingLogs(to: source, headingStartByte: 0,
            replacing: original, with: completed, logging: logging)
        XCTAssertTrue(result.contains(":狀態-LOG:\n"))
        XCTAssertTrue(result.contains("Old log\n"))
        XCTAssertTrue(result.hasSuffix(":END:\nBody\n* Neighbor\nUntouched\n"))
        XCTAssertEqual(result.components(separatedBy: ":狀態-LOG:").count, 2)
    }
}
