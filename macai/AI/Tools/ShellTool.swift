//
//  ShellTool.swift
//  SiriClone
//
//  Runs a shell command via /bin/sh -c. Always prompts the user via NSAlert
//  for confirmation before execution. Disabled by default in Settings.
//

import AppKit
import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct ShellTool: Tool {
    let name = "run_shell"
    let description = """
    Run a shell command and return its combined stdout/stderr. ALWAYS prompts the user \
    for confirmation before running. Truncates output to 64 KB. Use sparingly — only \
    when the user explicitly asks you to run a command.
    """

    @Generable(description: "Arguments for run_shell")
    struct Arguments {
        @Guide(description: "Shell command line (passed to /bin/sh -c)")
        var command: String
        @Guide(description: "Working directory. Defaults to $HOME.")
        var cwd: String
        @Guide(description: "Timeout in seconds (default 30, max 300)")
        var timeout: Int
    }

    func call(arguments: Arguments) async throws -> String {
        guard ShellTool.isEnabledInSettings() else {
            throw SiriToolError.disabledByUser("Shell commands are disabled in Settings → Tools.")
        }

        let trimmed = arguments.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SiriToolError.invalidArgument("Empty command.")
        }

        let approved = await ShellTool.confirmWithUser(command: trimmed)
        guard approved else {
            throw SiriToolError.userCancelled("User cancelled the shell command.")
        }

        let workDir = arguments.cwd.isEmpty ? NSHomeDirectory() : PathGuard.resolve(arguments.cwd)
        let cappedTimeout = min(max(arguments.timeout, 1), 300)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", trimmed]
        process.currentDirectoryURL = URL(fileURLWithPath: workDir)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        let timedOut = (try? await Task.detached {
            try await Task.sleep(nanoseconds: UInt64(cappedTimeout) * 1_000_000_000)
            if process.isRunning {
                process.terminate()
                return true
            }
            return false
        }.value) ?? false

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let truncated = output.count > 65_536
        let body = truncated ? String(output.prefix(65_536)) + "\n[truncated]" : output

        let prefix = timedOut ? "[timed out after \(cappedTimeout)s] " : ""
        let suffix = (process.terminationStatus == 0) ? "" : "\n[exit \(process.terminationStatus)]"
        return prefix + body + suffix
    }

    private static func isEnabledInSettings() -> Bool {
        UserDefaults.standard.bool(forKey: "tool.shell.enabled")
    }

    private static func confirmWithUser(command: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Run shell command?"
                alert.informativeText = "The model wants to run:\n\n\(command.prefix(2000))\n\nAllow this command to execute?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Allow")
                alert.addButton(withTitle: "Deny")
                let response = alert.runModal()
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }
}