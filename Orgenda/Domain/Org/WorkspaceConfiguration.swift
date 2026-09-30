import Foundation

/// Portable configuration. Decoding overlays defaults before decoding this
/// model, so omitted fields and explicit empty arrays have different meanings.
struct WorkspaceConfiguration: Codable, Equatable, Sendable {
    var version = 1
    var workflow = Workflow()
    var files = Files()
    var logging = Logging()
    var reminders = Reminders()
    var capture = Capture()
    var agenda = Agenda()

    struct Workflow: Codable, Equatable, Sendable {
        var sequences = [Sequence()]
        var keywords: [String: Keyword] = [:]
        var tokens: [String] { sequences.flatMap { $0.process + $0.terminal } }
        func state(_ token: String) -> OrgWorkflowState? {
            guard let sequence = sequences.first(where: { ($0.process + $0.terminal).contains(token) }) else { return nil }
            let style = keywords[token] ?? Keyword()
            let terminal = sequence.terminal.contains(token)
            let icon = style.icon == .default ? OrgWorkflowState.defaultIcon(for: token, terminal: terminal) : style.icon
            return OrgWorkflowState(token: token, terminal: sequence.terminal.contains(token),
                                    label: style.label, icon: icon, color: style.color,
                                    enter: style.log.enter, leave: style.log.leave)
        }
        var states: [OrgWorkflowState] { tokens.compactMap(state) }
        func toggled(_ state: OrgWorkflowState) -> OrgWorkflowState {
            let sequence = sequences.first { ($0.process + $0.terminal).contains(state.rawValue) } ?? sequences[0]
            return self.state(state.isTerminal ? sequence.reopen : sequence.complete)!
        }
        var initial: OrgWorkflowState { state(sequences[0].initial)! }
    }

    struct Sequence: Codable, Equatable, Identifiable, Sendable {
        var id = "tasks"
        var process = ["TODO"]
        var terminal = ["DONE"]
        var initial = "TODO"
        var complete = "DONE"
        var reopen = "TODO"
    }

    struct Keyword: Codable, Equatable, Sendable {
        var label = ""
        var key = ""
        var icon: ConfigurationIcon = .default
        var color: ConfigurationColor = .default
        var log = StateLog()
    }
    struct StateLog: Codable, Equatable, Sendable {
        var enter: LogRule = .none
        var leave: LogRule = .none
    }
    enum LogRule: String, Codable, CaseIterable, Sendable { case none, time, note }
    struct Logging: Codable, Equatable, Sendable {
        var done: LogRule = .none
        /// Empty means insert logs in the body instead of a drawer.
        var drawer = "LOGBOOK"
        var reschedule: LogRule = .none
        var redeadline: LogRule = .none
    }
    struct Files: Codable, Equatable, Sendable {
        var inbox = "inbox.org"
        var attachments = ".attach"
        var journal = "journal"
        var archive = "%s_archive::* Archived"
        var refile: [String] = []
        var refileMaxLevel = 3
    }
    struct Reminders: Codable, Equatable, Sendable {
        var advanceMinutes = 15
        var repeatMinutes = 5
        var deadlineWarningDays = 14
    }
    struct Capture: Codable, Equatable, Sendable {
        var defaultTemplate = "inbox"
        var templates = [Template()]
    }
    struct Template: Codable, Equatable, Identifiable, Sendable {
        var id = "inbox"
        var name = "Inbox task"
        var key = "t"
        var group = ""
        var type: CaptureType = .entry
        var target = Target()
        var template = "* TODO %^{Title}\n%?"
        var prepend = false
        var emptyLines = 1
    }
    enum CaptureType: String, Codable, CaseIterable, Sendable { case entry, item, checkitem, plain }
    struct Target: Codable, Equatable, Sendable {
        var type: TargetType = .file
        var path = "inbox.org"
        var outline: [String] = []
    }
    enum TargetType: String, Codable, CaseIterable, Sendable { case file, headline, outline, datetree }
    struct Agenda: Codable, Equatable, Sendable {
        /// Empty includes all visible .org files, excluding archives/recovery.
        var sources: [String] = []
        var excluded: [String] = []
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
        result.capture.templates[0].target.path = result.files.inbox
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
        func path(_ value: String, _ field: String) throws {
            try require(!value.isEmpty && !value.hasPrefix("/") && !value.hasPrefix("~")
                        && !value.contains("\\") && !value.contains(":")
                        && !value.contains(where: { $0.isNewline || $0 == "\0" })
                        && !value.split(separator: "/").contains(".."), "\(field): path must stay inside the workspace.")
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
        try require(workflow.keywords.values.allSatisfy { $0.key.count <= 1 }, "workflow shortcuts: use a single key.")
        for (field, value) in [("files.inbox", files.inbox), ("files.attachments", files.attachments), ("files.journal", files.journal)] {
            try path(value, field)
        }
        try require(files.inbox.hasSuffix(".org"), "files.inbox: expected an .org file.")
        for value in files.refile + agenda.sources + agenda.excluded { try path(value, "file selection") }
        try require((1...99).contains(files.refileMaxLevel), "files.refileMaxLevel: expected 1–99.")
        try require((0...1440).contains(reminders.advanceMinutes) && (1...1440).contains(reminders.repeatMinutes)
                    && (0...365).contains(reminders.deadlineWarningDays), "reminders: invalid interval.")
        try require(logging.drawer.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }, "logging.drawer: invalid drawer name.")
        try unique(capture.templates.map(\.id), "capture.templates.id")
        try unique(capture.templates.map(\.key).filter { !$0.isEmpty }, "capture shortcuts")
        try require(capture.templates.contains { $0.id == capture.defaultTemplate }, "capture.defaultTemplate: missing template.")
        for template in capture.templates {
            try path(template.target.path, "capture.\(template.id).target")
            try require(template.target.path.hasSuffix(".org"), "capture: target must be an .org file.")
            try require((0...10).contains(template.emptyLines), "capture.emptyLines: expected 0–10.")
            try require(template.target.outline.allSatisfy { !$0.isEmpty && !$0.contains(where: \.isNewline) }, "capture.outline: invalid heading.")
            try require(template.target.type == .file || template.target.type == .datetree || !template.target.outline.isEmpty,
                        "capture.target: a heading path is required.")
            _ = try ConfiguredCapture.expansions(in: template.template)
        }
        let archiveParts = files.archive.components(separatedBy: "::")
        try require(archiveParts.count == 2, "files.archive: expected relative-file::heading.")
        if let archive = archiveParts.first {
            try path(archive.replacingOccurrences(of: "%s", with: "example.org"), "files.archive")
        }
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

/// Retains unknown members at every object level when a known field is edited.
/// Arrays are replaced, but members of identifiable array elements are retained.
struct ConfigurationDocument: Sendable {
    var configuration: WorkspaceConfiguration
    var warnings: [String] = []
    private var original: Data
    init(_ source: String) throws {
        let data = Data(source.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["version"] != nil else { throw ConfigurationFailure(message: "version: a version is required.") }
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WorkspaceConfiguration.standard))
        let merged = Self.fillCollectionDefaults(Self.merge(defaults, object, preserveArrayMembers: false))
        do {
            configuration = try JSONDecoder().decode(WorkspaceConfiguration.self, from: JSONSerialization.data(withJSONObject: merged))
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
        let known = try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration))
        warnings = Self.unknownFields(object, known: known, path: "").map { "Unknown field \($0) is preserved but not applied." }
        original = data
    }
    init(configuration: WorkspaceConfiguration) {
        self.configuration = configuration
        original = Data("{}".utf8)
    }
    func encoded(_ value: WorkspaceConfiguration) throws -> String {
        try value.validate()
        var old = try JSONSerialization.jsonObject(with: original) as? [String: Any] ?? [:]
        if var workflow = old["workflow"] as? [String: Any],
           let keywords = workflow["keywords"] as? [String: Any] {
            workflow["keywords"] = keywords.filter { value.workflow.keywords[$0.key] != nil }
            old["workflow"] = workflow
        }
        let new = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        let result = Self.merge(old, new, preserveArrayMembers: true)
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }
    private static func merge(_ old: Any, _ new: Any, preserveArrayMembers: Bool) -> Any {
        if let lhs = old as? [String: Any], let rhs = new as? [String: Any] {
            return rhs.reduce(into: lhs) { result, pair in
                result[pair.key] = lhs[pair.key].map { merge($0, pair.value, preserveArrayMembers: preserveArrayMembers) } ?? pair.value
            }
        }
        if preserveArrayMembers, let lhs = old as? [[String: Any]], let rhs = new as? [[String: Any]] {
            return rhs.map { item -> Any in
                guard let id = item["id"] as? String, let prior = lhs.first(where: { $0["id"] as? String == id }) else { return item }
                return merge(prior, item, preserveArrayMembers: true)
            }
        }
        return new
    }
    private static func unknownFields(_ source: Any, known: Any, path: String) -> [String] {
        if let source = source as? [String: Any], let known = known as? [String: Any] {
            return source.keys.sorted().flatMap { key -> [String] in
                let next = path.isEmpty ? key : path + "." + key
                guard let value = known[key] else { return [next] }
                return unknownFields(source[key]!, known: value, path: next)
            }
        }
        if let source = source as? [Any], let known = known as? [Any] {
            return source.enumerated().flatMap { index, value in
                index < known.count ? unknownFields(value, known: known[index], path: path + "[\(index)]") : []
            }
        }
        return []
    }
    private static func decodingFailure(_ context: DecodingError.Context) -> ConfigurationFailure {
        ConfigurationFailure(message: context.codingPath.map(\.stringValue).joined(separator: ".") + ": " + context.debugDescription)
    }
    private static func fillCollectionDefaults(_ input: Any) -> Any {
        guard var object = input as? [String: Any] else { return input }
        func defaults<T: Encodable>(_ value: T) -> Any {
            (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(value))) ?? [:]
        }
        func fillArray(_ items: Any?, _ fallback: Any) -> Any? {
            guard let items = items as? [Any] else { return items }
            return items.map { merge(fallback, $0, preserveArrayMembers: false) }
        }
        if var workflow = object["workflow"] as? [String: Any] {
            workflow["sequences"] = fillArray(workflow["sequences"], defaults(WorkspaceConfiguration.Sequence()))
            if let keywords = workflow["keywords"] as? [String: Any] {
                workflow["keywords"] = keywords.reduce(into: [String: Any]()) { result, entry in
                    let fallback = WorkspaceConfiguration.Keyword()
                    result[entry.key] = merge(defaults(fallback), entry.value, preserveArrayMembers: false)
                }
            }
            object["workflow"] = workflow
        }
        if var capture = object["capture"] as? [String: Any] {
            capture["templates"] = fillArray(capture["templates"], defaults(WorkspaceConfiguration.Template()))
            object["capture"] = capture
        }
        return object
    }
}
