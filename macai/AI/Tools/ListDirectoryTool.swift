//
//  ListDirectoryTool.swift
//  SiriClone
//

import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct ListDirectoryTool: Tool {
    let name = "list_directory"
    let description = """
    List files and folders in a directory (non-recursive). Returns a newline-separated \
    list of names with [D] / [F] prefix for directories and files. Use to discover what \
    the user has on disk before opening a file.
    """

    @Generable(description: "Arguments for list_directory")
    struct Arguments {
        @Guide(description: "Absolute path or path starting with ~")
        var path: String
    }

    func call(arguments: Arguments) async throws -> String {
        let resolved = PathGuard.resolve(arguments.path)
        try PathGuard.assertAllowed(resolved)

        let url = URL(fileURLWithPath: resolved, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue else {
            throw SiriToolError.notADirectory(resolved)
        }

        let items = try FileManager.default.contentsOfDirectory(atPath: resolved)
        let sorted = items.sorted()
        let fm = FileManager.default
        let lines = sorted.map { name -> String in
            let full = (resolved as NSString).appendingPathComponent(name)
            var localIsDir: ObjCBool = false
            fm.fileExists(atPath: full, isDirectory: &localIsDir)
            let marker = localIsDir.boolValue ? "[D] " : "[F] "
            return marker + name
        }
        return lines.joined(separator: "\n")
    }
}