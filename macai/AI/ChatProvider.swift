//
//  ChatProvider.swift
//  SiriClone
//
//  Provider-agnostic chat backend interface. Both AppleIntelligenceProvider
//  (on-device Foundation Models) and LocalLLMProvider (OpenAI-compatible
//  HTTP backend, e.g. Ollama) conform to this. MessageManager picks one
//  based on the user's "ai.provider" preference.
//
//  Why not implement a custom `FoundationModels.LanguageModel`? Apple's
//  LanguageModel protocol requires a LanguageModelExecutor associatedtype
//  with prewarm/init/sample methods plus full Transcript state management.
//  That's a lot of code that re-implements Apple's session internals. By
//  exposing a parallel `ChatProvider` API we reuse the existing Apple
//  Foundation Models path verbatim AND we can talk to any OpenAI-
//  compatible server with a much smaller adapter.
//

import Foundation
import FoundationModels

/// Stream element yielded by any ChatProvider. The chat UI consumes these
/// to update bubbles, render tool-call badges, and surface file-save events.
enum ChatStreamEvent: Equatable {
    /// A chunk of assistant text. Concatenated in arrival order.
    case text(String)
    /// Model requested invocation of `name`.
    case toolCall(name: String)
    /// Tool invocation `name` returned `output`.
    case toolResult(name: String, output: String)
    /// A post-processor detected a code block and saved it to `path`.
    case fileSaved(path: String, language: String, lines: Int)
}

/// Provider-agnostic chat backend.
@available(macOS 26.0, *)
@MainActor
protocol ChatProvider: AnyObject {
    /// Rebuild the underlying session with a new system message. Called
    /// when the user changes the persona or edits the system prompt.
    func rebuild(instructions: String)

    /// Rebuild iff the supplied system message has changed since the last
    /// call. Used by MessageManager at the start of each turn.
    func refreshSystemMessageIfNeeded(targetSystemMessage: String)

    /// Stream a single user turn. Yields text chunks plus optional
    /// tool-call/tool-result markers. Cancellation propagates via the
    /// enclosing `Task`. Providers with native multimodal support (Local LLM
    /// with vision models) include images from the attachments; text-only
    /// providers (Apple Intelligence) ignore them since MessageManager has
    /// already prepended extracted PDF content to the prompt.
    func streamTurn(
        prompt: String,
        attachments: AttachmentContext
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>

    /// Stream plain text only (no tool events). Used by chat-name
    /// generation.
    func streamText(prompt: String) -> AsyncThrowingStream<String, Error>
}

/// Identifies the active provider. Used by Settings → Model tab and by
/// MessageManager to construct the right `ChatProvider`.
enum AIProviderID: String, CaseIterable, Identifiable {
    case appleIntelligence = "apple-intelligence"
    case localOpenAI = "local-openai"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence (on-device)"
        case .localOpenAI: return "Local OpenAI-compatible (Ollama / llama.cpp / vLLM)"
        }
    }
}