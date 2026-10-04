//
//  AppleScriptTool.swift
//  SiriClone
//
//  Runs an arbitrary AppleScript. Gives the AI the same surface Siri uses
//  to control any Mac app: Messages, Mail, Finder, Calendar, Music, etc.
//  Runs unsandboxed; the user is trusting the model with their whole Mac.
//

import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct AppleScriptTool: Tool {
    let name = "run_applescript"
    let description = """
    Run an AppleScript and return its result. AppleScript can control every \
    scriptable Mac app (Finder, Mail, Messages, Calendar, Music, Safari, System \
    Editor, …) — anything Siri can do via System Events. Default state is ON.
    """

    @Generable(description: "Arguments for run_applescript")
    struct Arguments {
        @Guide(description: "AppleScript source code to execute. Use 'on ... end' blocks for handlers.")
        var source: String
        @Guide(description: "Timeout in seconds (default 30, max 300)")
        var timeout: Int
    }

    func call(arguments: Arguments) async throws -> String {
        guard Self.isEnabledInSettings() else {
            throw SiriToolError.disabledByUser(
                "AppleScript is disabled in Settings → Tools."
            )
        }

        let trimmed = arguments.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SiriToolError.invalidArgument("Empty AppleScript source.")
        }

        let cappedTimeout = min(max(arguments.timeout, 1), 300)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                task.arguments = ["-e", trimmed]
                let stdout = Pipe()
                let stderr = Pipe()
                task.standardOutput = stdout
                task.standardError = stderr

                // Hard timeout via kill.
                let killTimer = DispatchSource.makeTimerSource(queue: .global())
                killTimer.schedule(deadline: .now() + .seconds(cappedTimeout))
                killTimer.setEventHandler {
                    if task.isRunning { task.terminate() }
                }
                killTimer.resume()

                task.terminationHandler = { _ in
                    killTimer.cancel()
                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let outStr = String(data: outData, encoding: .utf8) ?? ""
                    let errStr = String(data: errData, encoding: .utf8) ?? ""

                    if task.terminationStatus == 0 {
                        let body = outStr.isEmpty ? "(no output)" : outStr
                        continuation.resume(returning: body)
                    } else {
                        let reason = task.terminationReason == .uncaughtSignal ? "timed out" : "exit \(task.terminationStatus)"
                        let err = SiriToolError.applescriptFailed(
                            "\(reason): \(errStr.isEmpty ? outStr : errStr)",
                            underlying: nil
                        )
                        continuation.resume(throwing: err)
                    }
                }

                do {
                    try task.run()
                } catch {
                    killTimer.cancel()
                    continuation.resume(throwing: SiriToolError.applescriptFailed(
                        "could not launch osascript: \(error.localizedDescription)",
                        underlying: error
                    ))
                }
            }
        }
    }

    private static func isEnabledInSettings() -> Bool {
        UserDefaults.standard.object(forKey: "tool.applescript.enabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "tool.applescript.enabled")
    }
}