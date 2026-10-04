//
//  FileReadTool.swift
//  SiriClone
//

import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct FileReadTool: Tool {
    let name = "read_file"
    let description = """
    Read a UTF-8 text file from disk. Returns the file contents (truncated to \
    32 KB) or an error message if the file is missing or unreadable. Use when \
    the user asks you to open or quote a file. Path may start with ~ for home.
    """

    @Generable(description: "Arguments for read_file")
    struct Arguments {
        @Guide(description: "Absolute path or path starting with ~")
        var path: String
        @Guide(description: "Maximum number of bytes to read (default 32768)")
        var maxBytes: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let resolved = PathGuard.resolve(arguments.path)
        try PathGuard.assertAllowed(resolved)

        let url = URL(fileURLWithPath: resolved)
        guard FileManager.default.fileExists(atPath: resolved) else {
            throw SiriToolError.fileNotFound(resolved)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let cap = arguments.maxBytes > 0 ? arguments.maxBytes : 32_768
        let data: Data
        do {
            data = try handle.read(upToCount: cap) ?? Data()
        } catch {
            throw SiriToolError.ioError(resolved, underlying: error)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw SiriToolError.notUTF8(resolved)
        }

        if data.count >= cap {
            return text + "\n\n[truncated at \(cap) bytes]"
        }
        return text
    }
}