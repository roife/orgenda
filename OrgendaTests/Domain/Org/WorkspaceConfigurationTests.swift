import XCTest
import SwiftUI
@testable import Orgenda

final class WorkspaceConfigurationTests: XCTestCase {
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

    func testConfigurationOnlyExposesOrgBehaviorNotApplicationCustomization() throws {
        let document = ConfigurationDocument(configuration: .standard)
        let encoded = try document.encoded(.standard)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["version", "workflow", "capture", "files", "agenda", "logging", "reminders"])
        let agenda = try XCTUnwrap(root["agenda"] as? [String: Any])
        XCTAssertEqual(Set(agenda.keys), ["sources", "excluded"])
        let files = try XCTUnwrap(root["files"] as? [String: Any])
        XCTAssertNil(files["journalPeriod"])
        let capture = try XCTUnwrap(root["capture"] as? [String: Any])
        let templates = try XCTUnwrap(capture["templates"] as? [[String: Any]])
        XCTAssertNil(templates[0]["defaults"])
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
    func testDefaultWorkflowAppearanceMatchesOriginalLightAndDarkPalette() throws {
        let expected: [(String, String, [CGFloat], [CGFloat])] = [
            ("TODO", "circle", [0.34, 0.38, 0.42], [0.72, 0.76, 0.80]),
            ("NEXT", "arrow.right.circle", [0.10, 0.36, 0.78], [0.38, 0.67, 1.00]),
            ("WAIT", "hourglass", [0.68, 0.35, 0.04], [1.00, 0.68, 0.30]),
            ("SOMEDAY", "moon", [0.43, 0.29, 0.57], [0.75, 0.62, 0.90]),
            ("URGENT", "exclamationmark.circle.fill", [0.78, 0.16, 0.15], [1.00, 0.42, 0.38]),
            ("DONE", "checkmark.circle.fill", [0.52, 0.53, 0.56], [0.62, 0.63, 0.67]),
            ("CANCELED", "xmark.circle", [0.69, 0.20, 0.43], [0.95, 0.53, 0.72])
        ]
        // Check static fixtures, classic preset, a new custom sequence, and a
        // sparse style edited only for its label/key. They must look identical.
        var workflow = WorkspaceConfiguration.classic.workflow
        workflow.keywords = [:]
        let edited = try ConfigurationDocument("""
        {"version":1,"workflow":{"sequences":[{"process":["TODO","NEXT","WAIT","SOMEDAY","URGENT"],
          "terminal":["DONE","CANCELED"]}],"keywords":{"WAIT":{"label":"Waiting","key":"w"}}}}
        """).configuration.workflow
        for (token, symbol, light, dark) in expected {
            for state in [OrgWorkflowState(rawValue: token), WorkspaceConfiguration.classic.workflow.state(token),
                          workflow.state(token), edited.state(token)] {
                let state = try XCTUnwrap(state)
                XCTAssertEqual(state.symbol, symbol)
                XCTAssertEqual(state.color, .default)
                for (style, rgb) in [(UIUserInterfaceStyle.light, light), (.dark, dark)] {
                    let actual = UIColor(OrgendaTheme.workflowColor(state)).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    XCTAssertTrue(actual.getRed(&r, green: &g, blue: &b, alpha: &a))
                    XCTAssertEqual(r, rgb[0], accuracy: 0.001, token)
                    XCTAssertEqual(g, rgb[1], accuracy: 0.001, token)
                    XCTAssertEqual(b, rgb[2], accuracy: 0.001, token)
                    XCTAssertEqual(a, 1, accuracy: 0.001, token)
                }
            }
        }
        XCTAssertEqual(WorkspaceConfiguration.standard.workflow.state("DONE")?.color, .default)
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

    func testCustomTerminalLogAndReopen() throws {
        var configuration = WorkspaceConfiguration.standard
        configuration.workflow.sequences = [.init(process: ["OPEN"], terminal: ["FINISHED"],
                                                  initial: "OPEN", complete: "FINISHED", reopen: "OPEN")]
        let finished = try XCTUnwrap(configuration.workflow.state("FINISHED"))
        XCTAssertEqual(configuration.workflow.toggled(finished).rawValue, "OPEN")
        XCTAssertTrue(finished.isTerminal)
    }

    func testConfigurationResourceIsRootOnly() {
        XCTAssertEqual(WorkspaceSession.documentKind("config.json"), .configuration)
        XCTAssertNil(WorkspaceSession.documentKind("notes/config.json"))
        XCTAssertNil(WorkspaceSession.documentKind("other.json"))
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
