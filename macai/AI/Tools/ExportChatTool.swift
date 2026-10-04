//
//  ExportChatTool.swift
//  SiriClone
//
//  Exports the current chat to a user-chosen Markdown, plain text, or JSON
//  file via NSSavePanel. The format argument is required by the Tool
//  protocol but is mostly for the LLM's understanding; the user picks the
//  file extension via NSSavePanel.
//

import AppKit
import Foundation
import FoundationModels
import UniformTypeIdentifiers

@available(macOS 26.0, *)
struct ExportChatTool: Tool {
    let name = "export_chat"
    let description = """
    Export the current chat as a Markdown, plain text, or JSON file the user picks \
    via save panel. The format argument tells the model which format you want; the \
    user always gets a save dialog to confirm the destination.
    """

    @Generable(description: "Arguments for export_chat")
    struct Arguments {
        @Guide(description: "File format to export. One of: markdown, text, json")
        var format: String
        @Guide(description: "Optional filename (without extension). Defaults to the chat name + format extension.")
        var filename: String
    }

    /// The chat this tool was created for. Captured at init time so the
    /// LLM can invoke export without us having to thread the chat through
    /// the arguments.
    private let chat: ChatEntity

    init(chat: ChatEntity) {
        self.chat = chat
    }

    func call(arguments: Arguments) async throws -> String {
        let formatRaw = arguments.format.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let format = Format(rawValue: formatRaw) else {
            throw SiriToolError.invalidArgument(
                "Unknown export format '\(arguments.format)'. Use markdown, text, or json."
            )
        }

        let body = formatBody(format: format)
        let defaultName = defaultName(format: format, fallback: arguments.filename)

        let saveURL: URL? = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSSavePanel()
                if let type = UTType(filenameExtension: format.rawValue) {
                    panel.allowedContentTypes = [type]
                }
                panel.nameFieldStringValue = defaultName
                panel.canCreateDirectories = true
                panel.title = "Export Chat"
                panel.message = "Save the current chat as \(format.rawValue.uppercased())."
                let result = panel.runModal()
                continuation.resume(returning: result == .OK ? panel.url : nil)
            }
        }

        guard let url = saveURL else {
            throw SiriToolError.userCancelled("User cancelled the save panel.")
        }

        try body.data(using: .utf8)?.write(to: url, options: .atomic)
        return "Exported \(body.count) bytes to \(url.path)"
    }

    enum Format: String { case markdown, text, json }

    private func formatBody(format: Format) -> String {
        switch format {
        case .markdown: return Self.asMarkdown(chat: chat)
        case .text: return Self.asText(chat: chat)
        case .json: return Self.asJSON(chat: chat)
        }
    }

    private func defaultName(format: Format, fallback: String) -> String {
        let stem = fallback.isEmpty
            ? (chat.name.isEmpty ? "chat" : chat.name)
            : fallback
        return stem + "." + format.rawValue
    }

    static func asMarkdown(chat: ChatEntity) -> String {
        var out = "# \(chat.name.isEmpty ? "Chat" : chat.name)\n\n"
        if let persona = chat.persona?.name, !persona.isEmpty {
            out += "_Persona: \(persona)_\n\n"
        }
        for message in chat.messagesArray {
            let role = message.own ? "**You**" : "**Assistant**"
            out += "\(role):\n\n\(message.body)\n\n---\n\n"
        }
        return out
    }

    static func asText(chat: ChatEntity) -> String {
        var out = ""
        for message in chat.messagesArray {
            let role = message.own ? "You" : "Assistant"
            out += "\(role): \(message.body)\n\n"
        }
        return out
    }

    static func asJSON(chat: ChatEntity) -> String {
        struct ExportMessage: Codable {
            let role: String
            let body: String
            let timestamp: Date
        }
        struct ExportChat: Codable {
            let name: String
            let createdDate: Date
            let updatedDate: Date
            let messages: [ExportMessage]
        }
        let payload = ExportChat(
            name: chat.name,
            createdDate: chat.createdDate ?? Date(),
            updatedDate: chat.updatedDate ?? Date(),
            messages: chat.messagesArray.map {
                ExportMessage(
                    role: $0.own ? "user" : "assistant",
                    body: $0.body,
                    timestamp: $0.timestamp ?? Date()
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}