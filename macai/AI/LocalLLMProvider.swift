//
//  LocalLLMProvider.swift
//  SiriClone
//
//  OpenAI-compatible chat-completions backend for SiriClone. Talks to any
//  local server that speaks the OpenAI /v1/chat/completions API:
//    - Ollama (default, http://localhost:11434/v1)
//    - llama.cpp server
//    - vLLM, LM Studio, etc.
//
//  Tools are converted from Foundation Models `Tool` instances to OpenAI's
//  function-calling format. `GenerationSchema` is `Codable` so we encode
//  it directly to JSON Schema — the Foundation Models Codable output
//  already matches the JSON Schema shape OpenAI expects.
//
//  When the model returns `tool_calls`, we decode each call's arguments
//  via `GeneratedContent(json:).value(Arguments.self)`, invoke the tool,
//  and feed the result back as a `role: "tool"` message. The loop
//  continues until the model returns a final assistant message with
//  `finish_reason: "stop"` (or we hit the max-step guard).
//

import Foundation
import FoundationModels

@available(macOS 26.0, *)
@MainActor
final class LocalLLMProvider: ChatProvider {

    // MARK: - Configuration

    private let endpoint: URL
    private let modelName: String
    private let apiKey: String?  // Some servers require a key (LM Studio). Ollama ignores.
    private var personaInstructions: String
    private let toolBoxes: [AnyLocalToolBox]

    /// Maximum tool-call loops per turn. Prevents runaway loops when a
    /// model keeps calling tools without producing a final answer.
    private let maxToolSteps = 6

    /// Per-request timeout (seconds).
    private let requestTimeout: TimeInterval = 300

    init(
        endpoint: URL,
        modelName: String,
        apiKey: String? = nil,
        instructions: String,
        tools: [any Tool]
    ) {
        self.endpoint = endpoint
        self.modelName = modelName
        self.apiKey = apiKey
        self.personaInstructions = instructions
        self.toolBoxes = Self.makeBoxes(from: tools)
    }

    func rebuild(instructions: String) {
        self.personaInstructions = instructions
    }

    func refreshSystemMessageIfNeeded(targetSystemMessage: String) {
        let target = targetSystemMessage
        if target != personaInstructions {
            rebuild(instructions: target)
        }
    }

    // MARK: - Streaming entry points

    func streamTurn(prompt: String) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runTurn(prompt: prompt, continuation: continuation)
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

    func streamText(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runText(prompt: prompt, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Tool-call loop

    private func runTurn(
        prompt: String,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws {
        var messages: [OpenAIMessage] = []

        // System instructions: persona + the same prelude AppleIntelligenceProvider
        // uses (code-fence-first rule, path guidance). Keeps behaviour consistent.
        let prelude = Self.systemPrelude
        let combined = prelude + "\n\n" + personaInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append(.system(content: combined))
        messages.append(.user(content: prompt))

        let tools = toolBoxes.map { $0.openAIToolDefinition() }

        for step in 0..<maxToolSteps {
            if Task.isCancelled { throw CancellationError() }

            let result = try await streamOneStep(messages: messages, tools: tools) { delta in
                if !delta.isEmpty {
                    continuation.yield(.text(delta))
                }
            }

            switch result.outcome {
            case .finished:
                return

            case .toolCalls(let calls):
                // Append the assistant message that contained the tool calls.
                messages.append(.assistant(
                    content: result.assistantText.isEmpty ? nil : result.assistantText,
                    toolCalls: calls
                ))

                // Invoke each tool, append role: "tool" message with output.
                for call in calls {
                    if Task.isCancelled { throw CancellationError() }
                    continuation.yield(.toolCall(name: call.function.name))
                    let output: String
                    do {
                        output = try await invokeTool(call)
                    } catch {
                        output = "Tool error: \(error.localizedDescription)"
                    }
                    messages.append(.tool(toolCallId: call.id, content: output))
                    continuation.yield(.toolResult(name: call.function.name, output: output))
                }

                if step == maxToolSteps - 1 {
                    // Final step — force a no-tools follow-up so we
                    // emit a final text answer instead of looping forever.
                    _ = try await streamOneStep(messages: messages, tools: []) { delta in
                        if !delta.isEmpty {
                            continuation.yield(.text(delta))
                        }
                    }
                    return
                }
            }
        }
    }

    private func runText(
        prompt: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let messages: [OpenAIMessage] = [
            .system(content: "Reply concisely. No preamble, no explanation unless asked."),
            .user(content: prompt)
        ]
        _ = try await streamOneStep(messages: messages, tools: []) { delta in
            if !delta.isEmpty {
                continuation.yield(delta)
            }
        }
    }

    // MARK: - Single-step streaming

    private struct StepResult {
        let outcome: StepOutcome
        let assistantText: String
    }

    private enum StepOutcome {
        case finished
        case toolCalls([OpenAIToolCall])
    }

    /// Streams one OpenAI chat-completion. Yields deltas via the callback.
    /// Returns `.finished` if the model emitted a final answer or
    /// `.toolCalls` if it requested tool invocations.
    private func streamOneStep(
        messages: [OpenAIMessage],
        tools: [OpenAIToolDefinition],
        onDelta: (String) async throws -> Void
    ) async throws -> StepResult {
        let body = OpenAIRequest(
            model: modelName,
            messages: messages,
            tools: tools.isEmpty ? nil : tools,
            stream: true
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

        // Use URLSession.bytes(for:) — gives us the raw SSE byte stream
        // we can parse incrementally without buffering the full response.
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if !(200..<300).contains(http.statusCode) {
            // Drain a few bytes for error body.
            var errBody = ""
            for try await line in bytes.lines {
                errBody += line + "\n"
                if errBody.count > 4096 { break }
            }
            throw NSError(
                domain: "LocalLLMProvider",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server \(http.statusCode): \(errBody.prefix(400))"]
            )
        }

        var assistantText = ""
        var finishReason: String?
        var toolCalls: [OpenAIToolCall] = []

        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            if line.isEmpty { continue }
            if !line.hasPrefix("data:") { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8) else { continue }
            guard let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data) else {
                // Some servers prefix chunks with garbage or vary the format.
                continue
            }

            for choice in chunk.choices {
                if let delta = choice.delta {
                    if let content = delta.content, !content.isEmpty {
                        assistantText += content
                        try await onDelta(content)
                    }
                    if let toolDelta = delta.toolCalls {
                        for td in toolDelta {
                            mergeToolCallDelta(td, into: &toolCalls)
                        }
                    }
                }
                if let fr = choice.finishReason {
                    finishReason = fr
                }
            }
        }

        if let fr = finishReason {
            switch fr {
            case "stop":
                return StepResult(outcome: .finished, assistantText: assistantText)
            case "tool_calls":
                return StepResult(outcome: .toolCalls(toolCalls), assistantText: assistantText)
            case "length":
                if !toolCalls.isEmpty {
                    return StepResult(outcome: .toolCalls(toolCalls), assistantText: assistantText)
                }
                return StepResult(outcome: .finished, assistantText: assistantText)
            default:
                return StepResult(outcome: .finished, assistantText: assistantText)
            }
        }

        // No finish_reason — treat as finished unless we have pending tool calls.
        if !toolCalls.isEmpty {
            return StepResult(outcome: .toolCalls(toolCalls), assistantText: assistantText)
        }
        return StepResult(outcome: .finished, assistantText: assistantText)
    }

    private func mergeToolCallDelta(
        _ delta: OpenAIToolCallDelta,
        into accumulator: inout [OpenAIToolCall]
    ) {
        let index = max(0, delta.index ?? accumulator.count)
        while accumulator.count <= index {
            accumulator.append(OpenAIToolCall(
                id: "",
                type: "function",
                function: .init(name: "", arguments: "")
            ))
        }
        var existing = accumulator[index]
        if let id = delta.id, !id.isEmpty {
            existing.id = id
        }
        if let type = delta.type {
            existing.type = type
        }
        if let fn = delta.function {
            if let name = fn.name, !name.isEmpty {
                existing.function.name = name
            }
            if let args = fn.arguments {
                existing.function.arguments += args
            }
        }
        accumulator[index] = existing
    }

    // MARK: - Tool invocation

    private func invokeTool(_ call: OpenAIToolCall) async throws -> String {
        guard let box = toolBoxes.first(where: { $0.name == call.function.name }) else {
            return "Tool not found: \(call.function.name)"
        }
        let json = call.function.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.isEmpty {
            return try await box.call(argumentsJSON: "{}")
        }
        return try await box.call(argumentsJSON: json)
    }

    private static func makeBoxes(from tools: [any Tool]) -> [AnyLocalToolBox] {
        var boxes: [AnyLocalToolBox] = []
        for tool in tools {
            if let box = Self.makeBox(from: tool) {
                boxes.append(box)
            }
        }
        return boxes
    }

    /// Wrap a `Tool` instance in a type-erased box, capturing its
    /// `generationSchema` as JSON for the OpenAI tool definition.
    private static func makeBox(from tool: any Tool) -> AnyLocalToolBox? {
        // We can't reflect on `tool.Arguments` directly through the
        // `any Tool` existential. Instead we use Foundation Models'
        // `parameters` property (which returns the schema) — that's
        // available on every Tool whose `Arguments: Generable`.
        let parameters = tool.parameters
        let parametersJSON = Self.encodeSchemaAsJSON(parameters)

        return GenericToolBox(
            name: tool.name,
            description: tool.description,
            parametersJSON: parametersJSON,
            invoke: { json in
                let content = try GeneratedContent(json: json)
                // We have to call through the `any Tool` — but the
                // tool's `call(arguments:)` needs a typed `Arguments`
                // value. We use `tool.generatedContent`-style plumbing:
                // each Tool's `call` takes `Self.Arguments` so we have
                // to dispatch via a generic helper.
                return try await Self.invokeTyped(tool: tool, content: content)
            }
        )
    }

    /// Invoke a Tool with a GeneratedContent. The hard part: `tool.call`
    /// is generic over `Self.Arguments`. We can't recover the concrete
    /// type from the existential directly, so we use a small set of
    /// concrete wrappers.
    private static func invokeTyped(
        tool: any Tool,
        content: GeneratedContent
    ) async throws -> String {
        // Concrete dispatch. Order matters: more specific first.
        if let t = tool as? FileWriteTool {
            return try await t.call(arguments: content.value(FileWriteTool.Arguments.self))
        }
        if let t = tool as? FileReadTool {
            return try await t.call(arguments: content.value(FileReadTool.Arguments.self))
        }
        if let t = tool as? ListDirectoryTool {
            return try await t.call(arguments: content.value(ListDirectoryTool.Arguments.self))
        }
        if let t = tool as? ShellTool {
            return try await t.call(arguments: content.value(ShellTool.Arguments.self))
        }
        if let t = tool as? AppleScriptTool {
            return try await t.call(arguments: content.value(AppleScriptTool.Arguments.self))
        }
        if let t = tool as? SystemControlTool {
            return try await t.call(arguments: content.value(SystemControlTool.Arguments.self))
        }
        if let t = tool as? ClipboardTool {
            return try await t.call(arguments: content.value(ClipboardTool.Arguments.self))
        }
        if let t = tool as? OpenAppTool {
            return try await t.call(arguments: content.value(OpenAppTool.Arguments.self))
        }
        if let t = tool as? NotificationTool {
            return try await t.call(arguments: content.value(NotificationTool.Arguments.self))
        }
        if let t = tool as? ExportChatTool {
            return try await t.call(arguments: content.value(ExportChatTool.Arguments.self))
        }
        return "Tool \(tool.name) is not supported by the local LLM backend."
    }

    /// Encode a `GenerationSchema` to a `[String: Any]` JSON Schema-ish
    /// dict. Foundation Models' Codable output is already JSON-Schema
    /// shaped; we just decode and strip the `x-order` key some servers
    /// don't recognize.
    private static func encodeSchemaAsJSON(_ schema: GenerationSchema) -> [String: Any] {
        guard
            let data = try? JSONEncoder().encode(schema),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var sanitized = raw
        sanitized.removeValue(forKey: "x-order")
        return sanitized
    }

    // MARK: - System prelude

    /// Same prelude AppleIntelligenceProvider uses — code-fence-first rule,
    /// path guidance. Keeps behaviour consistent across providers.
    private static let systemPrelude = """
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

        2. Use write_file for short content only: notes under 10 lines, config snippets,
           a JSON blob, a single line. If the content would be more than ~10 lines of code,
           use a code fence in your reply — never write_file.

        3. PATHS: when the user mentions "Desktop", "Documents", "Downloads", or any
           folder name without a full path, the resolved save target is ~/Desktop,
           ~/Documents, ~/Downloads, etc. Use these in your code fence or pass them
           as plain text in your reply — do NOT call write_file with a Linux-style path
           like /home/user/Desktop (it doesn't exist on macOS). The safe forms are:
           ~/Desktop/file.py, /Users/<macuser>/Desktop/file.py, or just the file name
           (the post-processor puts it in the right folder).

        4. NEVER add markdown code fences (```python … ```) inside tool arguments —
           they end up in the file. Code fences belong in your REPLY TEXT only.

        For paths: `~/Desktop/...`, `~/Documents/...`, or absolute paths all work.
        Do not ask follow-up questions when the request is unambiguous. Just do it.
        """
}

// MARK: - Tool box

private protocol AnyLocalToolBox {
    var name: String { get }
    var description: String { get }
    var parametersJSON: [String: Any] { get }
    func call(argumentsJSON: String) async throws -> String
    func openAIToolDefinition() -> OpenAIToolDefinition
}

private struct GenericToolBox: AnyLocalToolBox {
    let name: String
    let description: String
    let parametersJSON: [String: Any]
    let invoke: (String) async throws -> String

    func call(argumentsJSON json: String) async throws -> String {
        try await invoke(json)
    }

    func openAIToolDefinition() -> OpenAIToolDefinition {
        OpenAIToolDefinition(
            type: "function",
            function: OpenAIToolFunction(
                name: name,
                description: description,
                parameters: AnyEncodableJSON(value: parametersJSON)
            )
        )
    }
}

// MARK: - OpenAI wire types

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let tools: [OpenAIToolDefinition]?
    let stream: Bool
}

private indirect enum OpenAIMessage: Encodable {
    case system(content: String)
    case user(content: String)
    case assistant(content: String?, toolCalls: [OpenAIToolCall]?)
    case tool(toolCallId: String, content: String)

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .system(let content):
            try c.encode("system", forKey: .role)
            try c.encode(content, forKey: .content)
        case .user(let content):
            try c.encode("user", forKey: .role)
            try c.encode(content, forKey: .content)
        case .assistant(let content, let toolCalls):
            try c.encode("assistant", forKey: .role)
            try c.encodeIfPresent(content, forKey: .content)
            try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
        case .tool(let id, let content):
            try c.encode("tool", forKey: .role)
            try c.encode(id, forKey: .toolCallId)
            try c.encode(content, forKey: .content)
        }
    }

    enum CodingKeys: String, CodingKey {
        case role, content, toolCalls = "tool_calls", toolCallId = "tool_call_id"
    }
}

private struct OpenAIToolDefinition: Encodable {
    let type: String
    let function: OpenAIToolFunction
}

private struct OpenAIToolFunction: Encodable {
    let name: String
    let description: String
    let parameters: AnyEncodableJSON
}

private struct AnyEncodableJSON: Encodable {
    let value: [String: Any]
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)
        try encodeDict(value, into: &container)
    }

    private func encodeDict(_ dict: [String: Any], into container: inout KeyedEncodingContainer<DynamicCodingKeys>) throws {
        for (k, v) in dict {
            guard let key = DynamicCodingKeys(stringValue: k) else { continue }
            try encodeValue(v, forKey: key, into: &container)
        }
    }

    private func encodeValue(
        _ v: Any,
        forKey key: DynamicCodingKeys,
        into container: inout KeyedEncodingContainer<DynamicCodingKeys>
    ) throws {
        switch v {
        case let s as String: try container.encode(s, forKey: key)
        case let b as Bool: try container.encode(b, forKey: key)
        case let i as Int: try container.encode(i, forKey: key)
        case let d as Double: try container.encode(d, forKey: key)
        case let arr as [Any]:
            var nested = container.nestedUnkeyedContainer(forKey: key)
            try encodeArray(arr, into: &nested)
        case let sub as [String: Any]:
            var nested = container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: key)
            try encodeDict(sub, into: &nested)
        default:
            break
        }
    }

    private func encodeArray(_ arr: [Any], into container: inout UnkeyedEncodingContainer) throws {
        for v in arr {
            switch v {
            case let s as String: try container.encode(s)
            case let b as Bool: try container.encode(b)
            case let i as Int: try container.encode(i)
            case let d as Double: try container.encode(d)
            case let sub as [String: Any]:
                var nested = container.nestedContainer(keyedBy: DynamicCodingKeys.self)
                try encodeDict(sub, into: &nested)
            default:
                break
            }
        }
    }
}

private struct DynamicCodingKeys: CodingKey {
    let stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { return nil }
}

private struct OpenAIToolCall: Codable {
    var id: String
    var type: String
    var function: OpenAIToolCallFunction
}

private struct OpenAIToolCallFunction: Codable {
    var name: String
    var arguments: String
}

private struct OpenAIToolCallDelta: Codable {
    let index: Int?
    let id: String?
    let type: String?
    let function: OpenAIToolCallFunctionDelta?
}

private struct OpenAIToolCallFunctionDelta: Codable {
    let name: String?
    let arguments: String?
}

private struct OpenAIStreamChunk: Codable {
    let choices: [OpenAIStreamChoice]
}

private struct OpenAIStreamChoice: Codable {
    let delta: OpenAIStreamDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

private struct OpenAIStreamDelta: Codable {
    let content: String?
    let toolCalls: [OpenAIToolCallDelta]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}