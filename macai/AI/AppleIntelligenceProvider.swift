//
//  AppleIntelligenceProvider.swift
//  SiriClone
//
//  On-device Apple Intelligence provider using Apple's Foundation Models framework.
//  Wraps `LanguageModelSession` to expose an `AsyncThrowingStream<String, Error>`
//  so the rest of the app can stream tokens into Core Data without caring
//  about Foundation Models internals.
//

import Foundation
import FoundationModels

/// On-device Apple Intelligence provider.
@available(macOS 26.0, *)
@MainActor
final class AppleIntelligenceProvider: ChatProvider {

    private var session: LanguageModelSession
    private let tools: [any Tool]
    private var personaInstructions: String

    init(instructions: String, tools: [any Tool] = []) {
        self.personaInstructions = instructions
        self.tools = tools
        self.session = Self.makeSession(instructions: instructions, tools: tools)
    }

    /// Rebuild the session with a new system message. Use when the user
    /// changes personas or edits the system message in the chat.
    func rebuild(instructions: String) {
        self.personaInstructions = instructions
        self.session = Self.makeSession(instructions: instructions, tools: tools)
    }

    /// Streams a single user turn. Yields text chunks (and tool-call /
    /// tool-result markers) as the model generates them. Cancellation
    /// propagates via Task cancellation.
    func streamTurn(prompt: String) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = session.streamResponse(to: prompt)
                    for try await snapshot in stream {
                        if Task.isCancelled {
                            continuation.finish(throwing: CancellationError())
                            return
                        }
                        let text = snapshot.content
                        if !text.isEmpty {
                            continuation.yield(.text(text))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Plain text-only stream — used for chat-name generation, where we
    /// don't want to surface tool events.
    func streamText(prompt: String) -> AsyncThrowingStream<String, Error> {
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = session.streamResponse(to: prompt)
                    var lastText = ""
                    for try await snapshot in stream {
                        if Task.isCancelled {
                            continuation.finish(throwing: CancellationError())
                            return
                        }
                        let text = snapshot.content
                        let delta = text.count > lastText.count
                            ? String(text.dropFirst(lastText.count))
                            : text
                        if !delta.isEmpty {
                            continuation.yield(delta)
                        }
                        lastText = text
                        if lastText.count > 80 { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func makeSession(instructions: String, tools: [any Tool]) -> LanguageModelSession {
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let prelude = """
            You are Siri with Apple Intelligence, running on this Mac with full system admin.

            Tools: file write/read/list, run_shell, run_applescript, system_control, clipboard,
            open, notify, export_chat. Use them when needed.

            ════════════════════════════════════════════════════════════════════
            FILE CREATION — STRICT RULES, READ CAREFULLY
            ════════════════════════════════════════════════════════════════════

            When the user says "create a Python/JS/etc. file" or "make a tic-tac-toe game":

            1. ALWAYS write the full source inside a fenced ```python (or ```js, ```swift,
               ```rust, ```bash, etc.) block in your reply text. The fence IS the deliverable.
               SiriClone watches your reply and auto-saves the fenced code block to the path
               the user mentioned.

            2. NEVER call write_file with a full program as its `content` argument. The 3B
               on-device model often drops, truncates, or escapes long content when passed
               as JSON. Code fences in your reply text are reliable; write_file is not.

            3. write_file is reserved for SHORT content only: notes under 10 lines, config
               snippets, a JSON blob, a single line. If the content would be more than
               about 10 lines of code, use a code fence in your reply — never write_file.

            4. PATHS: when the user mentions "Desktop", "Documents", "Downloads", or any
               folder name without a full path, the resolved save target is ~/Desktop,
               ~/Documents, ~/Downloads, etc. Use these in your code fence or pass them
               as plain text in your reply — do NOT call write_file with a Linux-style path
               like /home/user/Desktop (it doesn't exist on macOS). The safe forms are:
               ~/Desktop/file.py, /Users/<macuser>/Desktop/file.py, or just the file name
               (the post-processor puts it in the right folder).

            5. NEVER add markdown code fences (```python … ```) inside tool arguments —
               they end up in the file. Code fences belong in your REPLY TEXT only.

            For paths: `~/Desktop/...`, `~/Documents/...`, or absolute paths all work.
            Do not ask follow-up questions when the request is unambiguous. Just do it.
            """
        let combined = prelude + "\n\n" + trimmed
        return LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: tools,
            instructions: combined
        )
    }
}

@available(macOS 26.0, *)
extension AppleIntelligenceProvider {

    /// Convenience initializer that pulls the system message from a chat and
    /// the active tool set from the registry.
    static func makeForChat(_ chat: ChatEntity) -> AppleIntelligenceProvider {
        let instructions = (chat.persona?.systemMessage ?? chat.systemMessage ?? "")
        let tools = ToolRegistry.shared.activeTools(for: chat)
        return AppleIntelligenceProvider(instructions: instructions, tools: tools)
    }

    /// Rebuild the session if the chat's persona/system message has changed
    /// since the last call.
    func refreshSystemMessageIfNeeded(targetSystemMessage: String) {
        let target = targetSystemMessage
        if target != personaInstructions {
            rebuild(instructions: target)
        }
    }
}