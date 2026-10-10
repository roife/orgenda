import XCTest
import SwiftUI
@testable import Orgenda

final class WorkspaceConfigurationTests: XCTestCase {
    func testClassicWorkflowPresetPreservesEveryOtherWorkspaceSetting() throws {
        var original = WorkspaceConfiguration.standard
        original.files.inbox = "custom/inbox.org"
        original.files.archive = "archive.org::* Saved"
        original.agenda.sources = ["custom"]
        original.agenda.excluded = ["custom/private.org"]
        original.reminders = .init(advanceMinutes: 37, repeatMinutes: 11, deadlineWarningDays: 21)
        original.logging = .init(done: .note, drawer: "HISTORY", reschedule: .note, redeadline: .time)
        original.capture.templates[0].name = "My template"
        original.capture.templates[0].target.path = "custom/inbox.org"
        var expected = original
        expected.workflow = WorkspaceConfiguration.classic.workflow
        let result = original.applyingClassicWorkflowPreset()
        XCTAssertEqual(result, expected)
        XCTAssertNoThrow(try result.validate())
    }

    func testSettingsPreviewUsesRealAgendaAndArchiveRules() throws {
        let documents: [WorkspaceDocument] = [
            .init(path: "work/inbox.org", title: "", contents: "", kind: .org),
            .init(path: "work/private.org", title: "", contents: "", kind: .org),
            .init(path: ".hidden/notes.org", title: "", contents: "", kind: .org),
            .init(path: "personal.org", title: "", contents: "", kind: .org)
        ]
        XCTAssertEqual(ConfigurationSettingsPreview.agendaPaths(in: documents,
            agenda: .init(sources: ["work"], excluded: ["work/private.org"])), ["work/inbox.org"])
        let archive = try XCTUnwrap(ConfigurationSettingsPreview.archive(rule: "%s_archive::* Archived", sourcePath: "work/inbox.org"))
        XCTAssertEqual(archive.path, "work/inbox.org_archive")
        XCTAssertEqual(archive.outline, "* Archived")
        XCTAssertNotNil(ConfigurationSettingsFieldValidation.archiveMessage("../archive.org::* Saved"))
        XCTAssertNotNil(ConfigurationSettingsFieldValidation.archiveMessage("archive.txt::* Saved"))
        XCTAssertNil(ConfigurationSettingsPreview.archive(rule: "archive.txt::* Saved", sourcePath: "work/inbox.org"))
    }

    func testReminderPreviewMatchesSchedulerIncludingStartAndUnevenIntervals() {
        XCTAssertEqual(ConfigurationSettingsPreview.reminderOffsets(advanceMinutes: 15, repeatMinutes: 5), [15, 10, 5, 0])
        XCTAssertEqual(ConfigurationSettingsPreview.reminderOffsets(advanceMinutes: 7, repeatMinutes: 5), [7, 2, 0])
        XCTAssertEqual(ConfigurationSettingsPreview.reminderOffsets(advanceMinutes: 0, repeatMinutes: 5), [0])
        XCTAssertEqual(ConfigurationSettingsPreview.reminderOffsets(advanceMinutes: 10, repeatMinutes: 0), [])
    }
    func testWorkspaceRequiresExactlyOneDefaultSequence() throws {
        var configuration = WorkspaceConfiguration.standard
        configuration.workflow.sequences.append(.init(
            id: "second", process: ["OPEN"], terminal: ["CLOSED"],
            initial: "OPEN", complete: "CLOSED", reopen: "OPEN"))
        XCTAssertThrowsError(try configuration.validate())
        XCTAssertThrowsError(try ConfigurationDocument(configuration: configuration).encoded(configuration))
        let encoded = try JSONEncoder().encode(configuration)
        XCTAssertThrowsError(try ConfigurationDocument(String(decoding: encoded, as: UTF8.self)))
        configuration.workflow.sequences = []
        XCTAssertThrowsError(try configuration.validate())
        XCTAssertNoThrow(try WorkspaceConfiguration.standard.validate())
        XCTAssertNoThrow(try WorkspaceConfiguration.classic.validate())
    }

    func testSingleWorkspaceDefaultDoesNotDisableFileLocalSequences() {
        let local = OrgConfiguredHeading.workflow(in: """
        #+TODO: TODO | DONE
        #+TODO: OPEN | CLOSED
        """, base: WorkspaceConfiguration.standard.workflow)
        XCTAssertEqual(local.sequences.count, 2)
        XCTAssertEqual(local.tokens, ["TODO", "DONE", "OPEN", "CLOSED"])
        XCTAssertEqual(local.toggled(local.state("OPEN")!).rawValue, "CLOSED")
    }

    func testRemovedFieldsArePreservedWithWarningsNotApplied() throws {
        let source = """
        {"version":1,"appearance":{"accent":"red"},"shortcuts":{"bindings":{}},
         "agenda":{"views":[{"id":"legacy"}]},"capture":{"templates":[{"id":"inbox","defaults":{"state":"WAIT"}}]}}
        """
        let document = try ConfigurationDocument(source)
        XCTAssertEqual(document.configuration, .standard)
        XCTAssertTrue(document.warnings.contains { $0.contains("appearance") })
        XCTAssertTrue(document.warnings.contains { $0.contains("shortcuts") })
        XCTAssertTrue(document.warnings.contains { $0.contains("agenda.views") })
        XCTAssertTrue(document.warnings.contains { $0.contains("defaults") })
        let saved = try document.encoded(document.configuration)
        XCTAssertTrue(saved.contains("\"accent\""))
        XCTAssertEqual(try ConfigurationDocument(saved).configuration, .standard)
    }

    @MainActor
    func testSparseKeywordOverridesPreserveDefaultAppearance() throws {
        let workflow = try ConfigurationDocument("""
        {"version":1,"workflow":{"sequences":[{"process":["TODO","NEXT","WAIT","SOMEDAY","URGENT"],
          "terminal":["DONE","CANCELED"]}],"keywords":{"WAIT":{"label":"Waiting","key":"w"}}}}
        """).configuration.workflow
        for expected in OrgWorkflowState.allCases {
            let actual = try XCTUnwrap(workflow.state(expected.rawValue))
            XCTAssertEqual(actual.symbol, expected.symbol)
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: style)
                XCTAssertEqual(UIColor(OrgendaTheme.workflowColor(actual)).resolvedColor(with: traits),
                               UIColor(OrgendaTheme.workflowColor(expected)).resolvedColor(with: traits))
            }
        }
    }

    @MainActor
    func testExplicitStateStyleSurvivesSaveAndDoesNotAffectOtherStates() throws {
        let document = try ConfigurationDocument("""
        {"version":1,"workflow":{"keywords":{"DONE":{"color":"green"}}}}
        """)
        let completed = try XCTUnwrap(document.configuration.workflow.state("DONE"))
        XCTAssertEqual(completed.symbol, "checkmark.circle.fill")
        XCTAssertEqual(OrgendaTheme.workflowColor(completed), ConfigurationColor.green.swiftUIColor)
        var next = document.configuration
        next.workflow.keywords["TODO"] = .init(key: "t")
        let roundtrip = try ConfigurationDocument(document.encoded(next))
        XCTAssertEqual(roundtrip.configuration.workflow.state("DONE")?.color, .green)
        XCTAssertEqual(roundtrip.configuration.workflow.state("TODO")?.color, .default)
        let item = try XCTUnwrap(WorkspaceStore.preview().items.first { $0.state == .todo })
        XCTAssertEqual(item.workflowTitleColor, .primary)
        var colored = item
        colored.state.color = .pink
        XCTAssertEqual(colored.workflowTitleColor, ConfigurationColor.pink.swiftUIColor)
    }

    func testPublishedExampleAndClassicPresetValidate() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appendingPathComponent("docs/config.example.json"), encoding: .utf8)
        XCTAssertEqual(try ConfigurationDocument(source).configuration.workflow.state("WAIT")?.color, .amber)
        XCTAssertNoThrow(try WorkspaceConfiguration.classic.validate())
    }

    func testCapturePrependPreservesTargetMetadata() throws {
        var template = WorkspaceConfiguration.Template()
        template.target = .init(type: .headline, path: "notes.org", outline: ["Inbox"])
        template.prepend = true
        let source = "* Inbox\n:PROPERTIES:\n:ID: abc\n:END:\nExisting text.\n* Elsewhere\n"
        let document = WorkspaceDocument(path: "notes.org", title: "", contents: source, kind: .org)
        let parsed = try XCTUnwrap(OrgIndexService.parseSynchronously([document], configuration: .standard).first)
        let output = try ConfiguredCapture.inserting("* TODO New\n", template: template, into: source, parsed: parsed)
        XCTAssertTrue(output.contains(":ID: abc\n:END:\n\n** TODO New"))
        XCTAssertTrue(output.contains("* Elsewhere"))
        XCTAssertThrowsError(try ConfiguredCapture.inserting("* TODO New\n",
            template: .init(target: .init(type: .headline, path: "notes.org", outline: ["Missing"])),
            into: source, parsed: parsed))
    }

    @MainActor
    func testCustomWorkflowChangesAreUsedWhenEditingAndToggling() throws {
        let store = WorkspaceStore(documents: [
            .init(path: "notes.org", title: "", contents: "* OPEN Task\n", kind: .org)
        ])
        store.hasWorkspaceConfiguration = true
        store.configuration.workflow.sequences = [.init(process: ["OPEN"], terminal: ["FINISHED"],
                                                       initial: "OPEN", complete: "FINISHED", reopen: "OPEN")]
        store.parseWorkspace()
        let item = try XCTUnwrap(store.items.first)
        store.toggleDone(item)
        XCTAssertTrue(store.documents[0].contents.contains("* FINISHED Task"))
        XCTAssertFalse(store.documents[0].contents.contains("CLOSED:"))
        store.toggleDone(try XCTUnwrap(store.items.first))
        XCTAssertTrue(store.documents[0].contents.contains("* OPEN Task"))
    }
    func testMinimalDefaultsAndExplicitArrays() throws {
        let document = try ConfigurationDocument(#"{"version":1,"agenda":{"sources":[]}}"#)
        XCTAssertEqual(document.configuration.workflow.tokens, ["TODO", "DONE"])
        XCTAssertEqual(document.configuration.files.inbox, "inbox.org")
        XCTAssertTrue(document.configuration.agenda.sources.isEmpty)
        XCTAssertEqual(document.configuration.workflow.state("DONE")?.icon, .check)
    }

    func testSparseNestedCollectionsAndUnknownFieldRoundTrip() throws {
        let source = """
        {"version":1,"extension":{"enabled":true},"workflow":{"keywords":{"TODO":{"color":"blue","future":"keep"}}},
         "capture":{"templates":[{"id":"inbox","name":"Custom","target":{"path":"notes.org"}}]}}
        """
        let document = try ConfigurationDocument(source)
        XCTAssertEqual(document.configuration.capture.templates[0].target.path, "notes.org")
        var next = document.configuration
        next.workflow.keywords["TODO"]?.icon = .star
        let encoded = try document.encoded(next)
        XCTAssertTrue(encoded.contains("keep"))
        XCTAssertTrue(encoded.contains("extension"))
        XCTAssertEqual(try ConfigurationDocument(encoded).configuration.workflow.keywords["TODO"]?.icon, .star)
    }

    func testInvalidConfigCannotBeAccepted() throws {
        for source in [
            #"{"version":2}"#,
            #"{"version":1,"workflow":{"sequences":[]}}"#,
            #"{"version":1,"files":{"inbox":"../escape.org"}}"#,
            ##"{"version":1,"workflow":{"keywords":{"TODO":{"color":"#ffffff"}}}}"##,
            #"{"version":1,"reminders":{"repeatMinutes":0}}"#,
            #"{"version":1,"capture":{"defaultTemplate":"missing"}}"#
        ] { XCTAssertThrowsError(try ConfigurationDocument(source), source) }
    }

    func testLoggingDrawerRejectsReservedDelimitersAndKeepsSupportedNames() {
        var configuration = WorkspaceConfiguration.standard
        for name in ["END", "end", "PROPERTIES", "Properties"] {
            configuration.logging.drawer = name
            XCTAssertThrowsError(try configuration.validate(), name)
        }
        for name in ["", "LOGBOOK", "history", "2026", "工作記錄", "_history", "cafe\u{301}", "हिन्दी", "Ⓐ", "1️⃣", "custom-name"] {
            configuration.logging.drawer = name
            XCTAssertNoThrow(try configuration.validate(), name)
        }
    }

    func testCustomAndFileLocalStatesPreserveUTF8Source() throws {
        var config = WorkspaceConfiguration.standard
        config.workflow.sequences = [.init(process: ["待办", "进行"], terminal: ["完成"],
                                           initial: "待办", complete: "完成", reopen: "待办")]
        let source = "* 进行 [#A] 标题 🐈 :work:\n* NEXT ordinary title\n"
        let document = WorkspaceDocument(path: "notes.org", title: "", contents: source, kind: .org)
        let parsed = try XCTUnwrap(OrgIndexService.parseSynchronously([document], configuration: config).first)
        XCTAssertEqual(parsed.headings[0].state?.rawValue, "进行")
        XCTAssertEqual(parsed.headings[0].title, "标题 🐈")
        XCTAssertEqual(parsed.headings[0].priority, .high)
        XCTAssertNil(parsed.headings[1].state)
        XCTAssertEqual(parsed.headings[1].title, "NEXT ordinary title")
        let node = try XCTUnwrap(parsed.root.children.first?.todoNode)
        XCTAssertEqual(String(decoding: source.utf8.dropFirst(node.startByte).prefix(node.endByte - node.startByte), as: UTF8.self), "进行 ")
        let local = OrgConfiguredHeading.workflow(in: "#+TODO: OPEN(o) HOLD(h@/!) | FINISHED(f)\n", base: config.workflow)
        XCTAssertEqual(local.tokens, ["OPEN", "HOLD", "FINISHED"])
        XCTAssertEqual(local.state("HOLD")?.enterLog, .note)
        XCTAssertEqual(local.state("HOLD")?.leaveLog, .time)
        XCTAssertTrue(try XCTUnwrap(local.state("FINISHED")).isTerminal)
    }

    func testCapturePromptExpansionDoesNotInterpretAnswers() throws {
        let template = "* TODO %^{Title|Default}\n%?\n%% %U"
        let prompts = try ConfiguredCapture.expansions(in: template)
        let prompt = try XCTUnwrap(prompts.first { $0.prompt != nil })
        let result = try ConfiguredCapture.render(template, answers: [prompt.id: "literal %U"], cursorText: "notes")
        XCTAssertTrue(result.hasPrefix("* TODO literal %U\nnotes\n% ["))
        XCTAssertThrowsError(try ConfiguredCapture.expansions(in: "* TODO %(shell-command \"x\")"))
        XCTAssertThrowsError(try ConfiguredCapture.expansions(in: "%<%Q>"))
    }

    func testConfigurationResourceIsRootOnly() {
        XCTAssertEqual(WorkspaceDocument.Kind(path: "config.json"), .configuration)
        XCTAssertNil(WorkspaceDocument.Kind(path: "notes/config.json"))
        XCTAssertNil(WorkspaceDocument.Kind(path: "other.json"))
    }

    @MainActor
    func testInvalidExternalConfigurationKeepsLastGoodAndDeletionResets() throws {
        let store = WorkspaceStore()
        store.connectionDefaults = UserDefaults(suiteName: UUID().uuidString)!
        XCTAssertTrue(store.acceptConfiguration(#"{"version":1,"files":{"inbox":"tasks.org"}}"#))
        XCTAssertTrue(store.acceptConfiguration("{broken"))
        XCTAssertEqual(store.configuration.files.inbox, "tasks.org")
        XCTAssertNotNil(store.configurationError)
        XCTAssertTrue(store.acceptConfiguration(nil))
        XCTAssertEqual(store.configuration.files.inbox, "inbox.org")
    }
}
