//
//  OpenAppTool.swift
//  SiriClone
//
//  Launch an application by name or by `file://` / `https://` URL. Default
//  state is ON — the model can open anything on this Mac.
//

import AppKit
import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct OpenAppTool: Tool {
    let name = "open"
    let description = """
    Open an application, file, or URL. If target looks like a URL scheme (http, https, file, etc.) \
    or absolute path, open it directly. Otherwise treat it as an app name and launch via 'open -a'. \
    Default state is ON.
    """

    @Generable(description: "Arguments for open")
    struct Arguments {
        @Guide(description: "App name, file path, or URL to open.")
        var target: String
    }

    func call(arguments: Arguments) async throws -> String {
        let target = arguments.target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            throw SiriToolError.invalidArgument("open requires non-empty 'target'.")
        }

        let resolved: String
        let useAppFlag: Bool

        if target.hasPrefix("/") {
            // Absolute path
            resolved = PathGuard.resolve(target)
            useAppFlag = false
        } else if target.contains("://") {
            // URL
            resolved = target
            useAppFlag = false
        } else if let url = URL(string: target), url.scheme != nil {
            resolved = target
            useAppFlag = false
        } else {
            // App name → use `open -a`
            resolved = target
            useAppFlag = true
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = useAppFlag ? ["-a", resolved] : [resolved]
        let err = Pipe()
        task.standardError = err
        do { try task.run() } catch {
            throw SiriToolError.systemError("could not launch /usr/bin/open: \(error.localizedDescription)")
        }
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SiriToolError.systemError("open exit \(task.terminationStatus): \(errStr)")
        }
        return "Opened \(target)"
    }
}