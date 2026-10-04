//
//  PathGuard.swift
//  SiriClone
//
//  Path resolution and allowlist enforcement for Tools. Resolves ~ and env
//  variables, expands symlinks, and rejects writes to sensitive locations
//  unless the user has explicitly allowed them.
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
        }
    }
}

enum PathGuard {

    /// Resolve ~, $HOME, $ENV and return an absolute path. Does NOT follow
    /// symlinks yet — `assertAllowed` does that.
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
        // Expand $HOME etc.
        p = (p as NSString).expandingTildeInPath
        p = NSString(string: p).expandingTildeInPath
        return p
    }

    /// Expand symlinks and ensure the path is inside an allowed directory.
    /// Allowed list is `~/Documents`, `~/Desktop`, `~/Downloads`, plus anything
    /// the user has explicitly added in Settings → Tools → Path Allowlist.
    static func assertAllowed(_ path: String) throws {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        let resolved = url.resolvingSymlinksInPath().path

        let home = NSHomeDirectory()
        let defaultRoots = [
            home + "/Documents",
            home + "/Desktop",
            home + "/Downloads",
            home + "/Library/Mobile Documents/com~apple~CloudDocs",  // iCloud Drive
        ]

        // Custom allowlist from settings, one path per line.
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

        // If the parent directory exists and is itself inside an allowed root, allow it.
        let parent = (resolved as NSString).deletingLastPathComponent
        if parent != resolved,
           fm.fileExists(atPath: parent),
           allRoots.contains(where: { parent.hasPrefix($0 + "/") || parent == $0 })
        {
            return
        }

        throw SiriToolError.pathNotAllowed(resolved)
    }
}