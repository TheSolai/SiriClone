//
//  ResponsePostProcessor.swift
//  SiriClone
//
//  Scans the Foundation Models stream text for markdown code blocks and
//  auto-saves them to paths the user mentioned. This works around the
//  on-device model's tendency to drop or truncate content passed
//  through write_file's JSON-serialized argument — the model reliably
//  emits long code in ```python``` / ```javascript``` blocks inside
//  its reply text, and we extract + write that.
//

import Foundation

enum ResponsePostProcessor {

    struct DetectedFile {
        let path: String
        let language: String
        let bytes: Int
    }

    /// Inspect the user's prompt for a path hint.
    static func detectSaveTarget(userMessage: String) -> (directory: String, baseName: String)? {
        let lower = userMessage.lowercased()

        // 1) Explicit path like "save to ~/Desktop/tictactoe.py"
        if let explicit = explicitPath(in: userMessage) {
            let expanded = (explicit as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            return (url.deletingLastPathComponent().path, url.lastPathComponent)
        }

        // 2) Folder hint: "Desktop", "Documents", "Downloads", "home"
        let folderHints: [(label: String, dir: String)] = [
            ("desktop", NSHomeDirectory() + "/Desktop"),
            ("documents", NSHomeDirectory() + "/Documents"),
            ("downloads", NSHomeDirectory() + "/Downloads"),
            ("home", NSHomeDirectory()),
        ]

        for (label, dirPath) in folderHints {
            if lower.contains(label) {
                let fname = extractFilenameHint(userMessage) ?? "untitled"
                return (dirPath, fname)
            }
        }

        return nil
    }

    private static func explicitPath(in msg: String) -> String? {
        // Look for "save it to <path>" or "save to <path>" or "write it to <path>"
        // The path starts with / or ~/ and ends with .<ext>
        let patterns = [
            #"(?:save\s+(?:it\s+)?to|write\s+(?:it\s+)?to|put\s+(?:it\s+)?(?:in|on)\s+|at)\s+((?:/|~/?)[^\s]+\.[A-Za-z0-9]+)"#,
            #"\b((?:/|~/?)[^\s]+\.[A-Za-z0-9]+)\b"#,
        ]
        for pat in patterns {
            guard let regex = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) else { continue }
            let ns = msg as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = regex.firstMatch(in: msg, options: [], range: range), m.numberOfRanges >= 2 {
                return ns.substring(with: m.range(at: 1))
            }
        }
        return nil
    }

    /// Look for an explicit filename in the user message.
    static func extractFilenameHint(_ msg: String) -> String? {
        let patterns = [
            // "name the file tictactoe.py", "call it hello.py", "file named foo.py",
            // "filename is_prime.py" — capture the .ext right after the trigger word.
            #"(?:name\s+(?:it|the\s+file)|call\s+it|file\s+named|filename|save\s+as)[`'\"]([^[`'"\s]+)[`'"]"#,
            #"(?:name\s+(?:it|the\s+file)|call\s+it|file\s+named|filename|save\s+as)\s+([A-Za-z0-9_\-]+\.[A-Za-z0-9]+)\b"#,
            // "with filename <X>"
            #"\bwith\s+(?:filename|name)\s+([A-Za-z0-9_\-]+\.[A-Za-z0-9]+)\b"#,
            // "called tictactoe.py"
            #"\bcalled?\s+([A-Za-z0-9_\-]+\.[A-Za-z0-9]+)\b"#,
            // Backtick-wrapped filename anywhere in the message
            #"[`'\"]([A-Za-z0-9_\-]+\.[A-Za-z0-9]+)[`'"]"#,
        ]
        for pat in patterns {
            guard let regex = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) else { continue }
            let ns = msg as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = regex.firstMatch(in: msg, options: [], range: range), m.numberOfRanges >= 2 {
                let candidate = ns.substring(with: m.range(at: 1))
                // Skip if the regex captured just a file extension like ".py".
                if candidate.hasPrefix(".") && candidate.count < 6 { continue }
                return candidate
            }
        }
        return nil
    }

    /// Walk the response text and pull out every fenced code block.
    static func extractCodeBlocks(from text: String) -> [(language: String, content: String)] {
        // Match ```lang\n…\n```  (single-line or multi-line content)
        guard let regex = try? NSRegularExpression(
            pattern: "```([A-Za-z0-9_+\\-]+)?\\n([\\s\\S]*?)\\n```",
            options: []
        ) else { return [] }

        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        var out: [(String, String)] = []
        for m in matches where m.numberOfRanges >= 3 {
            let lang = ns.substring(with: m.range(at: 1)).lowercased()
            let body = ns.substring(with: m.range(at: 2))
            // Skip language-less blocks shorter than 20 chars — likely
            // ASCII art or a one-liner, not a real program.
            if lang.isEmpty && body.count < 20 { continue }
            let normalised = lang.isEmpty ? "python" : lang
            out.append((normalised, body))
        }
        return out
    }

    /// Extension lookup for known languages.
    static func fileExtension(for language: String) -> String {
        switch language.lowercased() {
        case "python", "py": return "py"
        case "javascript", "js": return "js"
        case "typescript", "ts": return "ts"
        case "swift": return "swift"
        case "rust", "rs": return "rs"
        case "go": return "go"
        case "ruby", "rb": return "rb"
        case "shell", "sh", "bash", "zsh": return "sh"
        case "html": return "html"
        case "css": return "css"
        case "json": return "json"
        case "yaml", "yml": return "yml"
        case "markdown", "md": return "md"
        case "sql": return "sql"
        case "c": return "c"
        case "cpp": return "cpp"
        case "c++": return "cpp"
        case "java": return "java"
        case "plaintext", "text": return "txt"
        default: return "txt"
        }
    }
}