//
//  ToolRegistry.swift
//  SiriClone
//
//  Holds the set of Foundation Models `Tool` instances the on-device model
//  can invoke. Per-chat tools come from settings (enabled flags), not from
//  the chat itself.
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

    /// Tool metadata the user can enable/disable in Settings. Concrete
    /// instances are built fresh per chat so they can capture the active
    /// Core Data context.
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
        case export
    }

    let all: [Definition] = [
        Definition(
            id: "file.write",
            name: "write_file",
            description: "Create or overwrite a text file at a path the user chooses.",
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
        Definition(
            id: "shell.run",
            name: "run_shell",
            description: "Run a shell command (requires user confirmation each time).",
            category: .shell,
            make: { _ in ShellTool() }
        ),
        Definition(
            id: "export.chat",
            name: "export_chat",
            description: "Export the current chat as Markdown, plain text, or JSON.",
            category: .export,
            make: { chat in ExportChatTool(chat: chat) }
        ),
    ]

    func isEnabled(_ id: String) -> Bool {
        // Default: all tools enabled. Set false explicitly to disable.
        if defaults.object(forKey: Self.enabledKeyPrefix + id) == nil { return true }
        return defaults.bool(forKey: Self.enabledKeyPrefix + id)
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        defaults.set(enabled, forKey: Self.enabledKeyPrefix + id)
    }

    /// Build the enabled Tool instances for a chat.
    func activeTools(for chat: ChatEntity) -> [any Tool] {
        all.filter { isEnabled($0.id) }.map { $0.make(chat) }
    }
}

extension ToolRegistry.Category {
    var label: String {
        switch self {
        case .filesystem: return "Files"
        case .shell: return "Shell"
        case .export: return "Export"
        }
    }
}