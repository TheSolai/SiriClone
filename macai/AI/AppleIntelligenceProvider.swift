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

/// Stream element yielded by AppleIntelligenceProvider. Foundation Models
/// drives tool invocation internally; we surface plain text chunks plus
/// optional tool-call summaries the chat UI can render.
enum AppleIntelligenceStreamEvent: Equatable {
    case text(String)
    case toolCall(name: String)
    case toolResult(name: String, output: String)
}

/// On-device Apple Intelligence provider.
@available(macOS 26.0, *)
@MainActor
final class AppleIntelligenceProvider {

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
    func streamTurn(prompt: String) -> AsyncThrowingStream<AppleIntelligenceStreamEvent, Error> {
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
            open, notify, export_chat. Chain them when a task needs several.

            WRITING FILES — the on-device model often drops or truncates long content passed as
            JSON. Use this pattern for any non-trivial file (>10 lines):

            1. Put the source in a single `cat <<'__EOF__' > ~/Desktop/file.py` heredoc
               passed to run_shell. Heredocs avoid JSON escaping entirely and the shell
               writes the literal bytes. Example:
               run_shell(command="cat <<'__EOF__' > ~/Desktop/hello.py\\nprint('hi')\\n__EOF__")

            2. For very long files use multiple run_shell calls each appending one section
               (use `>> file` instead of `> file` for the appends).

            3. write_file is fine for short content (a few lines, config snippets, notes).
               Don't use it for full programs.

            4. NEVER put markdown code fences (```python … ```) inside tool arguments — they
               end up in the file.

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
    func refreshSystemMessageIfNeeded(for chat: ChatEntity) {
        let target = chat.persona?.systemMessage ?? chat.systemMessage ?? ""
        if target != personaInstructions {
            rebuild(instructions: target)
        }
    }
}