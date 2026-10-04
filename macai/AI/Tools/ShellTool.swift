//
//  ShellTool.swift
//  SiriClone
//
//  Runs a shell command via /bin/sh -c. No confirmation prompt — full
//  admin mode. Disabled by default in Settings → Tools; turn it on to
//  let the model run shell commands directly.
//

import AppKit
import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct ShellTool: Tool {
    let name = "run_shell"
    let description = """
    Run a shell command and return its combined stdout/stderr. Default state is ON, \
    no confirmation prompt — SiriClone has full system admin by design. Truncates \
    output to 64 KB. Timeout 30s (max 300s).
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
        guard Self.isEnabledInSettings() else {
            throw SiriToolError.disabledByUser(
                "Shell commands are disabled in Settings → Tools. Enable 'Allow the model to run shell commands' to use run_shell."
            )
        }

        let trimmed = arguments.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SiriToolError.invalidArgument("Empty command.")
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
        // ON by default — SiriClone is a full-admin tool. Toggle off in Settings → Tools.
        UserDefaults.standard.object(forKey: "tool.shell.enabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "tool.shell.enabled")
    }
}