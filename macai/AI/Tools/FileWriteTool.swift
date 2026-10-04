//
//  FileWriteTool.swift
//  SiriClone
//
//  Foundation Models Tool that writes (or appends) UTF-8 text to a file on
//  disk. Runs unsandboxed; the path is checked against the user's
//  PathGuard allowlist before any I/O.
//

import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct FileWriteTool: Tool {
    let name = "write_file"
    let description = """
    Create or overwrite a UTF-8 text file at the given path. Use for saving notes, code snippets, \
    or any text the user asks you to save. The path may start with ~ for the user's home \
    directory. Will refuse to write to paths the user has not approved via the Tools settings \
    allowlist.
    """

    @Generable(description: "Arguments for write_file")
    struct Arguments {
        @Guide(description: "Absolute path or path starting with ~")
        var path: String
        @Guide(description: "UTF-8 text content to write to the file")
        var content: String
        @Guide(description: "If true, append to the file instead of overwriting")
        var append: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        let resolved = PathGuard.resolve(arguments.path)
        try PathGuard.assertAllowed(resolved)

        let url = URL(fileURLWithPath: resolved)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if arguments.append {
            if !FileManager.default.fileExists(atPath: resolved) {
                FileManager.default.createFile(atPath: resolved, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(arguments.content.utf8))
            return "Appended \(arguments.content.count) bytes to \(resolved)"
        } else {
            try arguments.content.write(to: url, atomically: true, encoding: .utf8)
            return "Wrote \(arguments.content.count) bytes to \(resolved)"
        }
    }
}