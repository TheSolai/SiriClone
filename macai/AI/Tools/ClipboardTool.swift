//
//  ClipboardTool.swift
//  SiriClone
//
//  Read or write text on the system clipboard. Default state is ON.
//

import AppKit
import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct ClipboardTool: Tool {
    let name = "clipboard"
    let description = """
    Get or set the system clipboard text. Pass action='get' to read, action='set' \
    with content=... to write. Default state is ON.
    """

    @Generable(description: "Arguments for clipboard")
    struct Arguments {
        @Guide(description: "'get' reads the clipboard, 'set' writes text to it.")
        var action: String
        @Guide(description: "Text to write (required when action is 'set').")
        var content: String
    }

    func call(arguments: Arguments) async throws -> String {
        let action = arguments.action.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let pasteboard = NSPasteboard.general
        switch action {
        case "get":
            if let text = pasteboard.string(forType: .string) {
                return text
            }
            return "(clipboard is empty or contains non-text content)"
        case "set":
            let trimmed = arguments.content
            guard !trimmed.isEmpty else {
                throw SiriToolError.invalidArgument("set action requires non-empty 'content'.")
            }
            pasteboard.clearContents()
            pasteboard.setString(trimmed, forType: .string)
            return "Wrote \(trimmed.count) chars to clipboard."
        default:
            throw SiriToolError.invalidArgument("Unknown action '\(action)'. Use 'get' or 'set'.")
        }
    }
}