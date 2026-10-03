import Foundation

/// Settings navigation and search share this inventory so results always open
/// the page they describe.
enum SettingsDestination: String, CaseIterable, Hashable, Sendable {
    case workspace
    case appearance
    case reminders
    case workflow
    case capture
    case files
    case configuration

    var title: String {
        switch self {
        case .workspace: String(localized: "Workspace & Sync")
        case .appearance: String(localized: "Appearance")
        case .reminders: String(localized: "Reminders")
        case .workflow: String(localized: "Workflow")
        case .capture: String(localized: "Capture templates")
        case .files: String(localized: "Files & agenda")
        case .configuration: String(localized: "Configuration file")
        }
    }

    var subtitle: String {
        switch self {
        case .workspace: String(localized: "Workspace folder, saving, and sync")
        case .appearance: String(localized: "Theme on this device")
        case .reminders: String(localized: "Device notifications and shared timing")
        case .workflow: String(localized: "States and history · Workspace")
        case .capture: String(localized: "Templates and destinations · Workspace")
        case .files: String(localized: "File locations and agenda · Workspace")
        case .configuration: String(localized: "Shared config.json, import and presets")
        }
    }

    var searchTerms: [String] {
        var terms = [title, subtitle]
        if self == .configuration {
            // The Emacs section remains discoverable after its standalone page is removed.
            terms += [
                "Extract from Emacs", "Copy prompt", "Full conversion prompt",
                "Convert, review and import your settings",
                String(localized: "Extract from Emacs"), String(localized: "Copy prompt"),
                String(localized: "Full conversion prompt"),
                "从 Emacs 提取", "從 Emacs 擷取", "复制提示词", "複製提示詞",
                "查看完整转换提示词", "檢視完整轉換提示詞",
                "转换、检查并导入设置", "轉換、檢查並匯入設定"
            ]
        }
        return terms
    }
}
