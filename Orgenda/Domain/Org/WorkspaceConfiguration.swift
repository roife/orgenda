import Foundation
import MetaCodable

/// Portable configuration. Missing or null fields use defaults except for version; explicit values,
/// including empty arrays, are decoded and validated as supplied.
@Codable
@MemberInit
struct WorkspaceConfiguration: Equatable, Sendable {
    /// Required when decoding; the initializer default only applies to new configurations.
    var version: Int = 1
    // Named defaults defer calls to macro-generated initializers until after attribute checking.
    @Default(ifMissing: Workflow.standard)
    var workflow: Workflow
    @Default(ifMissing: Files.standard)
    var files: Files
    @Default(ifMissing: Logging.standard)
    var logging: Logging
    @Default(ifMissing: Reminders.standard)
    var reminders: Reminders
    @Default(ifMissing: Capture.standard)
    var capture: Capture
    @Default(ifMissing: Agenda.standard)
    var agenda: Agenda

    @Codable
    @MemberInit
    struct Workflow: Equatable, Sendable {
        static let standard: Self = .init()

        @Default(ifMissing: [WorkspaceConfiguration.Sequence.standard])
        var sequences: [WorkspaceConfiguration.Sequence]
        @Default(ifMissing: [String: WorkspaceConfiguration.Keyword]())
        var keywords: [String: WorkspaceConfiguration.Keyword]
        var tokens: [String] { sequences.flatMap { $0.process + $0.terminal } }
        func state(_ token: String) -> OrgWorkflowState? {
            guard let sequence = sequences.first(where: { ($0.process + $0.terminal).contains(token) }) else { return nil }
            let style = keywords[token] ?? Keyword()
            return OrgWorkflowState(token: token, terminal: sequence.terminal.contains(token),
                                    label: style.label, icon: style.icon, color: style.color,
                                    enter: style.log.enter, leave: style.log.leave)
        }
        var states: [OrgWorkflowState] { tokens.compactMap(state) }
        func toggled(_ state: OrgWorkflowState) -> OrgWorkflowState {
            let sequence = sequences.first { ($0.process + $0.terminal).contains(state.rawValue) } ?? sequences[0]
            return self.state(state.isTerminal ? sequence.reopen : sequence.complete)!
        }
        var initial: OrgWorkflowState { state(sequences[0].initial)! }
    }

    @Codable
    @MemberInit
    struct Sequence: Equatable, Identifiable, Sendable {
        static let standard: Self = .init()

        @Default(ifMissing: "tasks")
        var id: String
        @Default(ifMissing: ["TODO"])
        var process: [String]
        @Default(ifMissing: ["DONE"])
        var terminal: [String]
        @Default(ifMissing: "TODO")
        var initial: String
        @Default(ifMissing: "DONE")
        var complete: String
        @Default(ifMissing: "TODO")
        var reopen: String
    }

    @Codable
    @MemberInit
    struct Keyword: Equatable, Sendable {
        @Default(ifMissing: "")
        var label: String
        @Default(ifMissing: "")
        var key: String
        @Default(ifMissing: ConfigurationIcon.default)
        var icon: ConfigurationIcon
        @Default(ifMissing: ConfigurationColor.default)
        var color: ConfigurationColor
        @Default(ifMissing: WorkspaceConfiguration.StateLog.standard)
        var log: WorkspaceConfiguration.StateLog
    }
    @Codable
    @MemberInit
    struct StateLog: Equatable, Sendable {
        static let standard: Self = .init()

        @Default(ifMissing: WorkspaceConfiguration.LogRule.none)
        var enter: WorkspaceConfiguration.LogRule
        @Default(ifMissing: WorkspaceConfiguration.LogRule.none)
        var leave: WorkspaceConfiguration.LogRule
    }
    enum LogRule: String, Codable, CaseIterable, Sendable { case none, time, note }
    @Codable
    @MemberInit
    struct Logging: Equatable, Sendable {
        static let standard: Self = .init()

        @Default(ifMissing: WorkspaceConfiguration.LogRule.none)
        var done: WorkspaceConfiguration.LogRule
        /// Empty means insert logs in the body instead of a drawer.
        @Default(ifMissing: "LOGBOOK")
        var drawer: String
        @Default(ifMissing: WorkspaceConfiguration.LogRule.none)
        var reschedule: WorkspaceConfiguration.LogRule
        @Default(ifMissing: WorkspaceConfiguration.LogRule.none)
        var redeadline: WorkspaceConfiguration.LogRule
    }
    @Codable
    @MemberInit
    struct Files: Equatable, Sendable {
        static let standard: Self = .init()

        @Default(ifMissing: "inbox.org")
        var inbox: String
        @Default(ifMissing: ".attach")
        var attachments: String
        @Default(ifMissing: "journal")
        var journal: String
        @Default(ifMissing: "%s_archive::* Archived")
        var archive: String
        @Default(ifMissing: [String]())
        var refile: [String]
        @Default(ifMissing: 3)
        var refileMaxLevel: Int
    }
    @Codable
    @MemberInit
    struct Reminders: Equatable, Sendable {
        static let standard: Self = .init()

        @Default(ifMissing: 15)
        var advanceMinutes: Int
        @Default(ifMissing: 5)
        var repeatMinutes: Int
        @Default(ifMissing: 14)
        var deadlineWarningDays: Int
    }
    @Codable
    @MemberInit
    struct Capture: Equatable, Sendable {
        static let standard: Self = .init()

        @Default(ifMissing: "inbox")
        var defaultTemplate: String
        @Default(ifMissing: [WorkspaceConfiguration.Template.standard])
        var templates: [WorkspaceConfiguration.Template]
    }
    @Codable
    @MemberInit
    struct Template: Equatable, Identifiable, Sendable {
        static let standard: Self = .init()

        @Default(ifMissing: "inbox")
        var id: String
        @Default(ifMissing: "Inbox task")
        var name: String
        @Default(ifMissing: "t")
        var key: String
        @Default(ifMissing: "")
        var group: String
        @Default(ifMissing: WorkspaceConfiguration.CaptureType.entry)
        var type: WorkspaceConfiguration.CaptureType
        @Default(ifMissing: WorkspaceConfiguration.Target.standard)
        var target: WorkspaceConfiguration.Target
        @Default(ifMissing: "* TODO %^{Title}\n%?")
        var template: String
        @Default(ifMissing: false)
        var prepend: Bool
        @Default(ifMissing: 1)
        var emptyLines: Int
    }
    enum CaptureType: String, Codable, CaseIterable, Sendable { case entry, item, checkitem, plain }
    @Codable
    @MemberInit
    struct Target: Equatable, Sendable {
        static let standard: Self = .init()

        @Default(ifMissing: WorkspaceConfiguration.TargetType.file)
        var type: WorkspaceConfiguration.TargetType
        @Default(ifMissing: "inbox.org")
        var path: String
        @Default(ifMissing: [String]())
        var outline: [String]
    }
    enum TargetType: String, Codable, CaseIterable, Sendable { case file, headline, outline, datetree }
    @Codable
    @MemberInit
    struct Agenda: Equatable, Sendable {
        static let standard: Self = .init()

        /// Empty includes all visible .org files, excluding archives/recovery.
        @Default(ifMissing: [String]())
        var sources: [String]
        @Default(ifMissing: [String]())
        var excluded: [String]
        func includes(_ path: String) -> Bool {
            guard path.hasSuffix(".org"),
                  !path.split(separator: "/").contains(where: {
                      $0.hasPrefix(".") || ["archives", "Unsaved Edits"].contains(String($0))
                  }) else { return false }
            return (sources.isEmpty || sources.contains { Self.matches(path, $0) })
                && !excluded.contains { Self.matches(path, $0) }
        }
        static func matches(_ path: String, _ pattern: String) -> Bool {
            path == pattern || path.hasPrefix(pattern.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/")
        }
    }
    static let standard = WorkspaceConfiguration()
    static let classic: WorkspaceConfiguration = {
        var result = standard
        result.workflow.sequences = [Sequence(process: ["TODO", "NEXT", "WAIT", "SOMEDAY", "URGENT"],
                                             terminal: ["DONE", "CANCELED"])]
        for state in OrgWorkflowState.allCases {
            result.workflow.keywords[state.rawValue] = Keyword(
                log: StateLog(enter: state.enterLog, leave: state.leaveLog))
        }
        result.files.inbox = "agenda/inbox.org"
        result.files.refile = OrgWorkspaceConfiguration.refilePaths
        result.agenda.sources = OrgWorkspaceConfiguration.agendaPaths.sorted()
        result.reminders.deadlineWarningDays = 3
        result.logging = Logging(done: .time, reschedule: .time, redeadline: .time)
        result.capture.templates = OrgCaptureTemplate.allCases.map { legacy in
            let token: String = legacy == .nextAction ? "NEXT" : legacy == .someday ? "SOMEDAY" : "TODO"
            let plain = legacy == .inboxNote || legacy == .calendarEvent
            let tags = legacy.isProject ? " :project:" : legacy == .inboxNote ? " :note:" : ""
            var body = "* " + (plain ? "" : token + " ") + "%^{Title}" + tags + "\n"
            if legacy == .reminder || legacy == .repeatingReminder {
                body += legacy == .repeatingReminder ? "SCHEDULED: %^{First occurrence (Org timestamp with repeater)}\n" : "SCHEDULED: %^{When}T\n"
            }
            body += ":PROPERTIES:\n:CREATED: %U\n"
            if legacy.includesAppointmentWarning { body += ":APPT_WARNTIME: %^{Warn before (minutes)|15}\n" }
            body += ":END:\n"
            if legacy == .calendarEvent { body += "%^{When}T\n" }
            body += "%?\n"
            if legacy.isProject { body += "** NEXT %^{First action}\n" }
            return Template(id: legacy.rawValue, name: legacy.title, key: "",
                            group: legacy.isProject ? "Projects" : "",
                            target: Target(type: legacy.parentHeading == nil ? .file : .headline,
                                           path: legacy.destinationPath, outline: legacy.parentHeading.map { [$0] } ?? []),
                            template: body)
        }
        result.capture.defaultTemplate = OrgCaptureTemplate.inboxTask.rawValue
        return result
    }()

    func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationFailure(message: message) }
        }
        func unique(_ values: [String], _ field: String) throws {
            try require(!values.contains(where: { $0.isEmpty }) && Set(values).count == values.count, "\(field): empty or duplicate value.")
        }
        func check(_ message: String?, field: String) throws {
            if let message { throw ConfigurationFailure(message: field + ": " + message) }
        }
        try require(version == 1, "version: unsupported configuration version \(version).")
        try require(workflow.sequences.count == 1, "workflow.sequences: exactly one default sequence is required.")
        try unique(workflow.sequences.map(\.id), "workflow.sequences.id")
        try unique(workflow.tokens, "workflow keywords")
        for token in workflow.tokens {
            try require(!token.contains(where: { $0.isWhitespace || "()|:".contains($0) }), "workflow: invalid keyword \(token).")
        }
        for sequence in workflow.sequences {
            try require(!sequence.process.isEmpty && !sequence.terminal.isEmpty,
                        "workflow.\(sequence.id): Process and Terminal must both contain states.")
            try require(sequence.process.contains(sequence.initial) && sequence.process.contains(sequence.reopen)
                        && sequence.terminal.contains(sequence.complete), "workflow.\(sequence.id): invalid default state.")
        }
        try require(Set(workflow.keywords.keys).isSubset(of: Set(workflow.tokens)), "workflow.keywords: style refers to an undeclared state.")
        try unique(workflow.keywords.values.map(\.key).filter { !$0.isEmpty }, "workflow shortcuts")
        for (token, keyword) in workflow.keywords {
            try check(ConfigurationValidation.shortcutMessage(keyword.key), field: "workflow.keywords.\(token).key")
        }
        for (field, value) in [("files.inbox", files.inbox), ("files.attachments", files.attachments), ("files.journal", files.journal)] {
            try check(ConfigurationValidation.pathMessage(value, requiresOrgFile: field == "files.inbox"), field: field)
        }
        for value in files.refile {
            try check(ConfigurationValidation.pathMessage(value, requiresOrgFile: true), field: "files.refile")
        }
        for (field, paths) in [("agenda.sources", agenda.sources), ("agenda.excluded", agenda.excluded)] {
            for value in paths { try check(ConfigurationValidation.pathMessage(value), field: field) }
        }
        for (field, value, range) in [
            ("files.refileMaxLevel", files.refileMaxLevel, ConfigurationValidation.refileMaxLevel),
            ("reminders.advanceMinutes", reminders.advanceMinutes, ConfigurationValidation.advanceMinutes),
            ("reminders.repeatMinutes", reminders.repeatMinutes, ConfigurationValidation.repeatMinutes),
            ("reminders.deadlineWarningDays", reminders.deadlineWarningDays, ConfigurationValidation.deadlineWarningDays)
        ] {
            try check(ConfigurationValidation.integerMessage(value, in: range), field: field)
        }
        try check(ConfigurationValidation.drawerMessage(logging.drawer), field: "logging.drawer")
        try unique(capture.templates.map(\.id), "capture.templates.id")
        try unique(capture.templates.map(\.key).filter { !$0.isEmpty }, "capture shortcuts")
        try require(capture.templates.contains { $0.id == capture.defaultTemplate }, "capture.defaultTemplate: missing template.")
        for template in capture.templates {
            try require(!template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        String(localized: "Name: enter a name so you can recognize this template."))
            try check(ConfigurationValidation.pathMessage(template.target.path, requiresOrgFile: true), field: "capture.\(template.id).target.path")
            try check(ConfigurationValidation.shortcutMessage(template.key), field: "capture.\(template.id).key")
            try check(ConfigurationValidation.integerMessage(template.emptyLines, in: ConfigurationValidation.templateEmptyLines), field: "capture.\(template.id).emptyLines")
            try require(template.target.outline.allSatisfy { !$0.isEmpty && !$0.contains(where: \.isNewline) }, "capture.outline: invalid heading.")
            try require(template.target.type == .file || template.target.type == .datetree || !template.target.outline.isEmpty,
                        "capture.target: a heading path is required.")
            try require(!template.template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        String(localized: "Org source: enter the content to insert when using this template."))
            try require(template.type != .entry || template.template.hasPrefix("* "),
                        String(localized: "Org source: a Heading template must begin with an asterisk followed by a space: * ."))
            _ = try ConfiguredCapture.expansions(in: template.template)
        }
        try check(ConfigurationValidation.archiveMessage(files.archive), field: "files.archive")
    }
}

struct ConfigurationFailure: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

enum ConfigurationIcon: String, Codable, CaseIterable, Identifiable, Sendable {
    case `default`, circle, arrow, hourglass, pause, moon, exclamation, flag, star, check, cross
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .default: "arrow.uturn.backward"
        case .circle: "circle"
        case .arrow: "arrow.right.circle"
        case .hourglass: "hourglass"
        case .pause: "pause.circle"
        case .moon: "moon"
        case .exclamation: "exclamationmark.circle.fill"
        case .flag: "flag"
        case .star: "star"
        case .check: "checkmark.circle.fill"
        case .cross: "xmark.circle"
        }
    }
}

enum ConfigurationColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case `default`, gray, red, orange, amber, green, cyan, blue, purple, pink
    var id: String { rawValue }
}

/// Reads and writes only the typed configuration fields.
struct ConfigurationDocument: Sendable {
    var configuration: WorkspaceConfiguration
    init(_ source: String) throws {
        do {
            configuration = try JSONDecoder().decode(WorkspaceConfiguration.self, from: Data(source.utf8))
        } catch let DecodingError.dataCorrupted(context) {
            throw Self.decodingFailure(context)
        } catch let DecodingError.typeMismatch(_, context) {
            throw Self.decodingFailure(context)
        } catch let DecodingError.valueNotFound(_, context) {
            throw Self.decodingFailure(context)
        } catch let DecodingError.keyNotFound(key, context) {
            throw ConfigurationFailure(message: (context.codingPath + [key]).map(\.stringValue).joined(separator: ".") + ": required value is missing.")
        }
        try configuration.validate()
    }
    init(configuration: WorkspaceConfiguration) {
        self.configuration = configuration
    }
    func encoded(_ value: WorkspaceConfiguration) throws -> String {
        try value.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
    private static func decodingFailure(_ context: DecodingError.Context) -> ConfigurationFailure {
        ConfigurationFailure(message: context.codingPath.map(\.stringValue).joined(separator: ".") + ": " + context.debugDescription)
    }
}
