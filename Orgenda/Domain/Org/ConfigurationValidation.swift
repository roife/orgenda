import Foundation

/// Shared rules for configuration decoding, saving and field-level feedback.
enum ConfigurationValidation {
    static let refileMaxLevel = 1...99
    static let advanceMinutes = 0...1440
    static let repeatMinutes = 1...1440
    static let deadlineWarningDays = 0...365
    static let templateEmptyLines = 0...10

    static func integerMessage(_ value: Int, in range: ClosedRange<Int>) -> String? {
        range.contains(value) ? nil
            : String(localized: "Enter a whole number from \(range.lowerBound) to \(range.upperBound).")
    }

    static func pathMessage(_ path: String, requiresOrgFile: Bool = false) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"),
              !path.contains("\\"), !path.contains(":"),
              !path.contains(where: { $0.isNewline || $0 == "\0" }),
              !components.contains(".."),
              !requiresOrgFile || components.allSatisfy({ !$0.isEmpty && $0 != "." }) else {
            return String(localized: "Use a relative path inside this workspace, without empty components, ., .., ~, or an absolute path.")
        }
        if requiresOrgFile && !path.hasSuffix(".org") {
            return String(localized: "Choose an Org file or enter a path ending in .org.")
        }
        return nil
    }

    static func archiveMessage(_ rule: String) -> String? {
        let parts = rule.components(separatedBy: "::")
        guard parts.count == 2 else {
            return String(localized: "Separate the archive file and heading with ::, for example %s_archive::* Archived.")
        }
        let path = parts[0].replacingOccurrences(of: "%s", with: "example.org")
            .trimmingCharacters(in: .whitespaces)
        if let message = pathMessage(path) { return message }
        guard !path.contains("%"), path.hasSuffix(".org") || path.hasSuffix(".org_archive") else {
            return String(localized: "The archive file must end in .org or .org_archive. Only %s is supported as a filename placeholder.")
        }
        let heading = parts[1].trimmingCharacters(in: .whitespaces)
        if !heading.isEmpty && (heading.contains(where: \.isNewline)
            || heading.range(of: #"^\*+[ \t]+\S[^\r\n]*$"#, options: .regularExpression) == nil) {
            return String(localized: "Start the archive heading with stars and a space, or leave it empty to append at the end of the file.")
        }
        return nil
    }

    static func drawerMessage(_ name: String) -> String? {
        guard name.isEmpty || (OrgDrawerName.isSupported(name)
            && !["END", "PROPERTIES"].contains(name.uppercased())) else {
            return String(localized: "Use letters, numbers, underscores or hyphens for the log drawer, or leave it empty. END and PROPERTIES are reserved.")
        }
        return nil
    }

    static func shortcutMessage(_ key: String) -> String? {
        key.count <= 1 && !key.contains(where: \.isWhitespace) ? nil
            : String(localized: "Quick selection key: use one character, or leave it empty.")
    }
}
