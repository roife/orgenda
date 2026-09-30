import Foundation

enum OrgItemKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case event
    case task
    case project
    case habit
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .event: String(localized: "Event")
        case .task: String(localized: "Task")
        case .project: String(localized: "Project")
        case .habit: String(localized: "Habit")
        case .note: String(localized: "Note")
        }
    }

    var systemImage: String {
        switch self {
        case .event: "calendar"
        case .task: "checkmark.circle"
        case .project: "square.stack.3d.up"
        case .habit: "repeat.circle"
        case .note: "note.text"
        }
    }
}

struct OrgWorkflowState: Codable, Identifiable, Hashable, Sendable {
    let rawValue: String
    var isTerminal: Bool
    var label: String
    var icon: ConfigurationIcon
    var color: ConfigurationColor
    var enterLog: WorkspaceConfiguration.LogRule
    var leaveLog: WorkspaceConfiguration.LogRule
    var title: String {
        guard label.isEmpty else { return label }
        switch rawValue {
        case "TODO": return String(localized: "TODO")
        case "NEXT": return String(localized: "NEXT")
        case "WAIT": return String(localized: "WAIT")
        case "SOMEDAY": return String(localized: "SOMEDAY")
        case "URGENT": return String(localized: "URGENT")
        case "DONE": return String(localized: "DONE")
        case "CANCELED": return String(localized: "CANCELED")
        default: return rawValue
        }
    }
    var id: String { rawValue }

    init(token: String, terminal: Bool = false, label: String = "",
         icon: ConfigurationIcon = .default, color: ConfigurationColor = .default,
         enter: WorkspaceConfiguration.LogRule = .none, leave: WorkspaceConfiguration.LogRule = .none) {
        rawValue = token
        isTerminal = terminal
        self.label = label
        self.icon = icon == .default ? Self.defaultIcon(for: token, terminal: terminal) : icon
        self.color = color
        enterLog = enter
        leaveLog = leave
    }
    /// Legacy token lookup is retained for unconfigured previews and fixtures.
    /// Configured behavior resolves states against a per-document workflow.
    init?(rawValue: String) {
        guard let value = Self.allCases.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = value
    }
    static let todo = Self(token: "TODO")
    static let next = Self(token: "NEXT")
    static let wait = Self(token: "WAIT", enter: .note, leave: .time)
    static let someday = Self(token: "SOMEDAY")
    static let urgent = Self(token: "URGENT", enter: .time)
    static let done = Self(token: "DONE", terminal: true, enter: .time)
    static let canceled = Self(token: "CANCELED", terminal: true, enter: .note)
    static let allCases: [Self] = [.todo, .next, .wait, .someday, .urgent, .done, .canceled]

    static func defaultIcon(for token: String, terminal: Bool) -> ConfigurationIcon {
        switch token {
        case "TODO": .circle
        case "NEXT": .arrow
        case "WAIT": .hourglass
        case "SOMEDAY": .moon
        case "URGENT": .exclamation
        case "DONE": .check
        case "CANCELED": .cross
        default: terminal ? .check : .circle
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue == rhs.rawValue }
    func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let token = try container.decode(String.self)
        self = Self(rawValue: token) ?? Self(token: token)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum OrgPriority: String, CaseIterable, Codable, Identifiable, Sendable {
    case none = ""
    case high = "A"
    case medium = "B"
    case low = "C"

    var id: String { rawValue }
    var displayName: String { self == .none ? String(localized: "None") : rawValue }
}
