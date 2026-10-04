//
//  SystemControlTool.swift
//  SiriClone
//
//  System-level controls: volume, dark/light mode, Do Not Disturb, sleep,
//  logout, screen lock. Implemented via osascript (System Events) and
//  /usr/bin/commands. Default state is ON — full system admin.
//

import AppKit
import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct SystemControlTool: Tool {
    let name = "system_control"
    let description = """
    Run a system-level control action. Supported actions:
    - volume_up / volume_down / volume_set(value)
    - mute / unmute
    - dark_mode / light_mode
    - do_not_disturb_on / do_not_disturb_off
    - sleep / lock_screen / logout
    - quit_app(name)
    Default state is ON.
    """

    @Generable(description: "Arguments for system_control")
    struct Arguments {
        @Guide(description: "Action to perform (see description for supported values)")
        var action: String
        @Guide(description: "Optional numeric argument (e.g. volume level 0-100). Ignored unless the action requires it.")
        var value: Int
        @Guide(description: "Optional argument (e.g. app name for quit_app).")
        var argument: String
    }

    func call(arguments: Arguments) async throws -> String {
        let action = arguments.action.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case "volume_up":
            return try Self.runScript("set volume output volume ((output volume of (get volume settings)) + 5)")
        case "volume_down":
            return try Self.runScript("set volume output volume ((output volume of (get volume settings)) - 5)")
        case "volume_set":
            let clamped = max(0, min(100, arguments.value))
            return try Self.runScript("set volume output volume \(clamped)")
        case "mute":
            return try Self.runScript("set volume output muted true")
        case "unmute":
            return try Self.runScript("set volume output muted false")
        case "dark_mode":
            NSApp.appearance = NSAppearance(named: .darkAqua)
            return "Dark mode enabled."
        case "light_mode":
            NSApp.appearance = NSAppearance(named: .aqua)
            return "Light mode enabled."
        case "do_not_disturb_on":
            return try Self.runShell("defaults -currentHost write ~/Library/Preferences/ByHost/com.apple.notificationcenterui.plist doNotDisturb -bool true; killall usernoted 2>/dev/null; echo on")
        case "do_not_disturb_off":
            return try Self.runShell("defaults -currentHost delete ~/Library/Preferences/ByHost/com.apple.notificationcenterui.plist doNotDisturb 2>/dev/null; killall usernoted 2>/dev/null; echo off")
        case "sleep":
            // Run async so we don't deadlock the caller.
            DispatchQueue.global().async {
                _ = try? Self.runShell("pmset sleepnow")
            }
            return "Going to sleep."
        case "lock_screen":
            DispatchQueue.global().async {
                _ = try? Self.runScript("tell application \"System Events\" to keystroke \"q\" using {command down, control down}")
            }
            return "Locking screen."
        case "logout":
            DispatchQueue.global().async {
                _ = try? Self.runShell("osascript -e 'tell application \"loginwindow\" to «event aevtlogo»'")
            }
            return "Logging out."
        case "quit_app":
            let name = arguments.argument.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw SiriToolError.invalidArgument("quit_app requires 'argument' to be set to the app name.") }
            return try Self.runScript("tell application \"\(name)\" to quit")
        default:
            throw SiriToolError.invalidArgument("Unknown action '\(action)'.")
        }
    }

    /// Run an AppleScript via osascript, returning stdout or a thrown error.
    private static func runScript(_ source: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        let out = Pipe(); let err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do { try task.run() } catch {
            throw SiriToolError.systemError("could not launch osascript: \(error.localizedDescription)")
        }
        task.waitUntilExit()
        let outStr = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if task.terminationStatus != 0 {
            throw SiriToolError.systemError("osascript exit \(task.terminationStatus): \(errStr)")
        }
        return outStr.isEmpty ? "OK" : outStr
    }

    private static func runShell(_ command: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]
        let out = Pipe(); let err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do { try task.run() } catch {
            throw SiriToolError.systemError("could not launch /bin/sh: \(error.localizedDescription)")
        }
        task.waitUntilExit()
        let outStr = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if task.terminationStatus != 0 {
            throw SiriToolError.systemError("shell exit \(task.terminationStatus): \(errStr)")
        }
        return outStr.isEmpty ? "OK" : outStr
    }
}