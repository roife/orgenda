import XCTest
@testable import Orgenda

final class WorkspaceConfigurationTests: XCTestCase {
    func testSettingsRoundTripPreservesPartialConfigurationAndDropsUnknownMembers() throws {
        XCTAssertEqual(try ConfigurationDocument(#"{"version":1}"#).configuration, .standard)
        let document = try ConfigurationDocument(#"""
        {
          "version": 1,
          "ignoredMember": {"future": true},
          "workflow": {
            "sequences": [{"id": "custom", "ignoredMember": 1}],
            "keywords": {
              "TODO": {"label": "待办", "log": {"enter": "note", "ignoredMember": false}}
            }
          },
          "files": {"inbox": "任务/inbox.org", "refile": [], "refileMaxLevel": 5},
          "logging": {"drawer": "", "reschedule": "time"},
          "reminders": {"advanceMinutes": 0, "repeatMinutes": 10},
          "capture": {
            "defaultTemplate": "quick",
            "templates": [{
              "id": "quick", "name": "快速记录", "prepend": true, "emptyLines": 0,
              "target": {"path": "任务/inbox.org", "outline": [], "ignoredMember": [1, 2]},
              "ignoredMember": null
            }]
          },
          "agenda": {"sources": [], "excluded": ["private"], "ignoredMember": "unused"}
        }
        """#)
        var expected = WorkspaceConfiguration.standard
        expected.workflow.sequences[0].id = "custom"
        expected.workflow.keywords["TODO"] = .init(label: "待办", log: .init(enter: .note))
        expected.files.inbox = "任务/inbox.org"
        expected.files.refileMaxLevel = 5
        expected.logging.drawer = ""
        expected.logging.reschedule = .time
        expected.reminders.advanceMinutes = 0
        expected.reminders.repeatMinutes = 10
        expected.capture.defaultTemplate = "quick"
        expected.capture.templates = [.init(id: "quick", name: "快速记录",
            target: .init(path: "任务/inbox.org"), prepend: true, emptyLines: 0)]
        expected.agenda.excluded = ["private"]
        XCTAssertEqual(document.configuration, expected)

        // Editing one setting must retain the other known values and their defaults.
        var edited = document.configuration
        edited.reminders.deadlineWarningDays = 7
        expected.reminders.deadlineWarningDays = 7
        let encoded = try document.encoded(edited)
        XCTAssertFalse(encoded.contains("ignoredMember"))
        XCTAssertEqual(try ConfigurationDocument(encoded).configuration, expected)
    }

    func testNullFieldsUseDefaults() throws {
        let sources = [
            #"{"version":1,"workflow":null,"files":null,"logging":null,"reminders":null,"capture":null,"agenda":null}"#,
            #"{"version":1,"workflow":{"sequences":null,"keywords":null},"capture":{"templates":null}}"#,
            #"""
            {
              "version": 1,
              "workflow": {"sequences": [{"id": null, "process": null, "terminal": null}]},
              "files": {"inbox": null, "refile": null, "refileMaxLevel": null},
              "logging": {"done": null, "drawer": null},
              "reminders": {"advanceMinutes": null, "repeatMinutes": null},
              "capture": {"defaultTemplate": null, "templates": [{
                "id": null, "type": null, "prepend": null, "emptyLines": null,
                "target": {"type": null, "path": null, "outline": null}
              }]},
              "agenda": {"sources": null, "excluded": null}
            }
            """#
        ]
        for source in sources {
            XCTAssertEqual(try ConfigurationDocument(source).configuration, .standard, source)
        }
        let keywordSource = #"""
        {"version":1,"workflow":{"keywords":{
          "TODO":{"label":null,"icon":null,"color":null,"log":{"enter":null,"leave":null}},
          "DONE":{"log":null}
        }},"capture":{"templates":[{"target":null}]}}
        """#
        var expected = WorkspaceConfiguration.standard
        expected.workflow.keywords = ["TODO": .init(), "DONE": .init()]
        XCTAssertEqual(try ConfigurationDocument(keywordSource).configuration, expected)
    }

    func testInvalidValuesCannotSilentlyTurnIntoDefaults() {
        let invalidSources = [
            #"{}"#,
            #"null"#,
            #"{"version":2}"#,
            #"{"version":null}"#,
            #"{"version":"1"}"#,
            #"{"version":1,"workflow":false}"#,
            #"{"version":1,"workflow":{"sequences":[]}}"#,
            #"{"version":1,"workflow":{"sequences":[{"id":42}]}}"#,
            #"{"version":1,"workflow":{"keywords":{"TODO":{"log":{"enter":"unknown"}}}}}"#,
            #"{"version":1,"workflow":{"keywords":{"TODO":{"color":"unknown"}}}}"#,
            #"{"version":1,"files":{"refile":[null]}}"#,
            #"{"version":1,"reminders":{"repeatMinutes":"5"}}"#,
            #"{"version":1,"capture":{"templates":[]}}"#,
            #"{"version":1,"capture":{"templates":[null]}}"#,
            #"{"version":1,"capture":{"templates":[{"target":{"outline":false}}]}}"#
        ]
        for source in invalidSources {
            XCTAssertThrowsError(try ConfigurationDocument(source), source)
        }
    }
}
