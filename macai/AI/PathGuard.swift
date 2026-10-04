//
//  PathGuard.swift
//  SiriClone
//
//  Path resolution and allowlist enforcement for Tools. By default every
//  path is permitted (SiriClone runs unsandboxed and the user wants full
//  admin). The allowlist remains as an opt-in guardrail that can be turned
//  on from Settings → Tools.
//

import Foundation

enum SiriToolError: LocalizedError {
    case fileNotFound(String)
    case notUTF8(String)
    case notADirectory(String)
    case pathNotAllowed(String)
    case disabledByUser(String)
    case userCancelled(String)
    case invalidArgument(String)
    case ioError(String, underlying: Error)
    case applescriptFailed(String, underlying: Error?)
    case systemError(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "File not found: \(p)"
        case .notUTF8(let p): return "File is not valid UTF-8: \(p)"
        case .notADirectory(let p): return "Not a directory: \(p)"
        case .pathNotAllowed(let p): return "Path not allowed by Tools settings: \(p)"
        case .disabledByUser(let m): return m
        case .userCancelled(let m): return m
        case .invalidArgument(let m): return m
        case .ioError(let p, let u): return "I/O error on \(p): \(u.localizedDescription)"
        case .applescriptFailed(let s, let u): return u.map { "AppleScript failed: \(s) (\($0.localizedDescription))" } ?? "AppleScript failed: \(s)"
        case .systemError(let m): return m
        }
    }
}

enum PathGuard {

    /// Resolve ~, $HOME, etc. into an absolute path. Does NOT follow
    /// symlinks — callers can do that with URL.resolvingSymlinksInPath().
    static func resolve(_ path: String) -> String {
        var p = path
        let home = NSHomeDirectory()
        if p.hasPrefix("~/") {
            p = home + p.dropFirst(1)
        } else if p == "~" {
            p = home
        } else if !p.hasPrefix("/") && !p.hasPrefix("~") {
            p = home + "/" + p
        }
        p = (p as NSString).expandingTildeInPath
        p = NSString(string: p).expandingTildeInPath
        return p
    }

    /// When `tool.path.restrict` is OFF (default) every path is allowed —
    /// full system admin. When ON, only paths inside the default roots
    /// (~/Documents, ~/Desktop, ~/Downloads, iCloud Drive) plus the
    /// user's custom allowlist are permitted.
    static func assertAllowed(_ path: String) throws {
        if !UserDefaults.standard.bool(forKey: "tool.path.restrict") {
            return
        }

        let url = URL(fileURLWithPath: path)
        let resolved = url.resolvingSymlinksInPath().path

        let home = NSHomeDirectory()
        let defaultRoots = [
            home + "/Documents",
            home + "/Desktop",
            home + "/Downloads",
            home + "/Library/Mobile Documents/com~apple~CloudDocs",
        ]

        var customRoots: [String] = []
        if let raw = UserDefaults.standard.string(forKey: "tool.path.allowlist") {
            customRoots = raw
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map(resolve)
        }

        let allRoots = defaultRoots + customRoots
        if allRoots.contains(where: { resolved.hasPrefix($0 + "/") || resolved == $0 }) {
            return
        }

        let parent = (resolved as NSString).deletingLastPathComponent
        if parent != resolved,
           FileManager.default.fileExists(atPath: parent),
           allRoots.contains(where: { parent.hasPrefix($0 + "/") || parent == $0 })
        {
            return
        }

        throw SiriToolError.pathNotAllowed(resolved)
    }
}