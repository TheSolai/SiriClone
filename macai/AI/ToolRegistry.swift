//
//  ToolRegistry.swift
//  SiriClone
//
//  Holds the set of Foundation Models `Tool` instances the on-device model
//  can invoke. Full system admin: every tool defaults to ON. Per-tool
//  disable flags live in UserDefaults.
//

import Foundation
import FoundationModels

/// Registry of available tools.
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()

    private static let enabledKeyPrefix = "tool.enabled."
    private var defaults: UserDefaults { .standard }

    private init() {}

    struct Definition {
        let id: String
        let name: String  // Foundation Models Tool name
        let description: String
        let category: Category
        let make: @MainActor (ChatEntity) -> any Tool
    }

    enum Category: String, CaseIterable {
        case filesystem
        case shell
        case system
        case apple
        case export
    }

    let all: [Definition] = [
        // Files
        Definition(
            id: "file.write",
            name: "write_file",
            description: "Create or overwrite a text file at any path on this Mac.",
            category: .filesystem,
            make: { _ in FileWriteTool() }
        ),
        Definition(
            id: "file.read",
            name: "read_file",
            description: "Read a text file from disk (truncated to 32 KB).",
            category: .filesystem,
            make: { _ in FileReadTool() }
        ),
        Definition(
            id: "file.list",
            name: "list_directory",
            description: "List files in a directory (non-recursive).",
            category: .filesystem,
            make: { _ in ListDirectoryTool() }
        ),
        // Shell
        Definition(
            id: "shell.run",
            name: "run_shell",
            description: "Run a shell command. No confirmation prompt by default.",
            category: .shell,
            make: { _ in ShellTool() }
        ),
        Definition(
            id: "shell.applescript",
            name: "run_applescript",
            description: "Run an AppleScript to control any Mac app (Finder, Mail, Messages, Calendar, Music, Safari, …).",
            category: .apple,
            make: { _ in AppleScriptTool() }
        ),
        // System
        Definition(
            id: "system.control",
            name: "system_control",
            description: "Volume, dark mode, Do Not Disturb, sleep, lock, logout, quit apps.",
            category: .system,
            make: { _ in SystemControlTool() }
        ),
        Definition(
            id: "system.clipboard",
            name: "clipboard",
            description: "Get or set the system clipboard text.",
            category: .system,
            make: { _ in ClipboardTool() }
        ),
        Definition(
            id: "system.open",
            name: "open",
            description: "Launch an app by name, open a file path, or open a URL.",
            category: .system,
            make: { _ in OpenAppTool() }
        ),
        Definition(
            id: "system.notify",
            name: "notify",
            description: "Post a macOS user notification to Notification Center.",
            category: .system,
            make: { _ in NotificationTool() }
        ),
        // Export
        Definition(
            id: "export.chat",
            name: "export_chat",
            description: "Export the current chat as Markdown, plain text, or JSON.",
            category: .export,
            make: { chat in ExportChatTool(chat: chat) }
        ),
    ]

    func isEnabled(_ id: String) -> Bool {
        // All tools default to ON (full admin).
        if defaults.object(forKey: Self.enabledKeyPrefix + id) == nil { return true }
        return defaults.bool(forKey: Self.enabledKeyPrefix + id)
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        defaults.set(enabled, forKey: Self.enabledKeyPrefix + id)
    }

    func activeTools(for chat: ChatEntity) -> [any Tool] {
        all.filter { isEnabled($0.id) }.map { $0.make(chat) }
    }
}

extension ToolRegistry.Category {
    var categoryLabel: String {
        switch self {
        case .filesystem: return "Files"
        case .shell: return "Shell"
        case .system: return "System"
        case .apple: return "AppleScript"
        case .export: return "Export"
        }
    }
}