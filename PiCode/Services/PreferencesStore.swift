//
//  PreferencesStore.swift
//  PiCode
//
//  PiCode-owned preferences. Nothing here changes Pi configuration: Pi settings
//  stay in `~/.pi/agent`.
//

import Foundation
import Observation

@Observable
@MainActor
final class PreferencesStore {
    enum Appearance: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    enum SendKey: String, CaseIterable, Identifiable {
        case returnKey
        case commandReturn

        var id: String { rawValue }
        var label: String {
            switch self {
            case .returnKey: return "Return sends, Shift-Return adds a line"
            case .commandReturn: return "Command-Return sends, Return adds a line"
            }
        }
    }

    var appearance: Appearance
    var sendKey: SendKey
    var showInspector: Bool
    var showSidebar: Bool
    /// Whether the embedded terminal panel is open under the conversation.
    /// A window-level layout fact, so it is remembered like the two panels above.
    var showTerminal: Bool
    var defaultThinkingLevel: String?
    var defaultModelQualifiedID: String?
    var confirmBeforeDeletingSessions: Bool
    var notificationsEnabled: Bool
    var recordRPCPayloads: Bool
    var extraLaunchArguments: String
    var pinnedProjects: Set<String>
    var pinnedSessions: Set<String>
    /// Session ids whose sidebar entry was dismissed. Never deletes the file.
    var hiddenSessions: Set<String>
    /// Projects whose chats are folded away in the sidebar. A decoration like a
    /// pin: it hides rows, it never touches a session file.
    var collapsedProjects: Set<String>
    var lastProjectPath: String?
    var reducedMotionOverride: Bool?
    /// PiCode-only per-project settings (name, launch folder, system prompt),
    /// keyed by canonical project path. Stored as JSON in `UserDefaults` rather
    /// than as three parallel arrays so the three fields can never drift apart.
    private(set) var projectSettingsByPath: [String: ProjectSettings]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        sendKey = SendKey(rawValue: defaults.string(forKey: Keys.sendKey) ?? "") ?? .returnKey
        showInspector = defaults.object(forKey: Keys.showInspector) as? Bool ?? true
        showSidebar = defaults.object(forKey: Keys.showSidebar) as? Bool ?? true
        showTerminal = defaults.object(forKey: Keys.showTerminal) as? Bool ?? false
        defaultThinkingLevel = defaults.string(forKey: Keys.defaultThinkingLevel)
        defaultModelQualifiedID = defaults.string(forKey: Keys.defaultModel)
        confirmBeforeDeletingSessions = defaults.object(forKey: Keys.confirmDelete) as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? false
        recordRPCPayloads = defaults.bool(forKey: Keys.recordPayloads)
        extraLaunchArguments = defaults.string(forKey: Keys.extraArguments) ?? ""
        pinnedProjects = Set(defaults.stringArray(forKey: Keys.pinnedProjects) ?? [])
        pinnedSessions = Set(defaults.stringArray(forKey: Keys.pinnedSessions) ?? [])
        hiddenSessions = Set(defaults.stringArray(forKey: Keys.hiddenSessions) ?? [])
        collapsedProjects = Set(defaults.stringArray(forKey: Keys.collapsedProjects) ?? [])
        lastProjectPath = defaults.string(forKey: Keys.lastProject)
        reducedMotionOverride = defaults.object(forKey: Keys.reducedMotion) as? Bool
        if let data = defaults.data(forKey: Keys.projectSettings) {
            projectSettingsByPath = (try? JSONDecoder.piCode.decode([String: ProjectSettings].self, from: data)) ?? [:]
        } else {
            projectSettingsByPath = [:]
        }
    }

    func persist() {
        defaults.set(appearance.rawValue, forKey: Keys.appearance)
        defaults.set(sendKey.rawValue, forKey: Keys.sendKey)
        defaults.set(showInspector, forKey: Keys.showInspector)
        defaults.set(showSidebar, forKey: Keys.showSidebar)
        defaults.set(showTerminal, forKey: Keys.showTerminal)
        defaults.set(defaultThinkingLevel, forKey: Keys.defaultThinkingLevel)
        defaults.set(defaultModelQualifiedID, forKey: Keys.defaultModel)
        defaults.set(confirmBeforeDeletingSessions, forKey: Keys.confirmDelete)
        defaults.set(notificationsEnabled, forKey: Keys.notifications)
        defaults.set(recordRPCPayloads, forKey: Keys.recordPayloads)
        defaults.set(extraLaunchArguments, forKey: Keys.extraArguments)
        defaults.set(Array(pinnedProjects), forKey: Keys.pinnedProjects)
        defaults.set(Array(pinnedSessions), forKey: Keys.pinnedSessions)
        defaults.set(Array(hiddenSessions), forKey: Keys.hiddenSessions)
        defaults.set(Array(collapsedProjects), forKey: Keys.collapsedProjects)
        defaults.set(lastProjectPath, forKey: Keys.lastProject)
        defaults.set(reducedMotionOverride, forKey: Keys.reducedMotion)
        if projectSettingsByPath.isEmpty {
            defaults.removeObject(forKey: Keys.projectSettings)
        } else if let data = try? JSONEncoder.piCode.encode(projectSettingsByPath) {
            defaults.set(data, forKey: Keys.projectSettings)
        }
    }

    // MARK: - Per-project settings

    func projectSettings(for path: String) -> ProjectSettings {
        projectSettingsByPath[path] ?? ProjectSettings()
    }

    /// Replaces a project's settings. Empty settings are removed rather than
    /// stored as blanks, so “no settings” has one representation.
    func setProjectSettings(_ settings: ProjectSettings, for path: String) {
        if settings.isEmpty {
            projectSettingsByPath.removeValue(forKey: path)
        } else {
            projectSettingsByPath[path] = settings
        }
        persist()
    }

    func persistAppearance() {
        defaults.set(appearance.rawValue, forKey: Keys.appearance)
    }

    private enum Keys {
        static let appearance = "appearance"
        static let sendKey = "sendKey"
        static let showInspector = "showInspector"
        static let showSidebar = "showSidebar"
        static let showTerminal = "showTerminal"
        static let defaultThinkingLevel = "defaultThinkingLevel"
        static let defaultModel = "defaultModel"
        static let confirmDelete = "confirmBeforeDeletingSessions"
        static let notifications = "notificationsEnabled"
        static let recordPayloads = "recordRPCPayloads"
        static let extraArguments = "extraLaunchArguments"
        static let pinnedProjects = "pinnedProjects"
        static let pinnedSessions = "pinnedSessions"
        static let hiddenSessions = "hiddenSessions"
        static let collapsedProjects = "collapsedProjects"
        static let lastProject = "lastProjectPath"
        static let reducedMotion = "reducedMotionOverride"
        static let projectSettings = "projectSettings"
    }
}
