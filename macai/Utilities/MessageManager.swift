//
//  MessageManager.swift
//  SiriClone
//
//  Drives one chat turn against an on-device Apple Intelligence session.
//  Builds a fresh `LanguageModelSession` (rebuilds on system message change)
//  and streams tokens into Core Data while the user watches.
//
//  On top of the live stream we run a `ResponsePostProcessor` that detects
//  code blocks the model emits in markdown fences and writes them to paths
//  the user mentioned. This works around the on-device model's tendency
//  to drop or truncate long content passed through write_file's JSON-
//  serialized argument — the model reliably puts long code into fenced
//  blocks inside its reply text, and we extract + persist that.
//

import CoreData
import Foundation
import FoundationModels

@MainActor
final class MessageManager: ObservableObject {

    enum StreamingError: LocalizedError {
        case unsupported
        case emptyResponse
        case sessionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "Selected AI provider requires macOS 26 or later on Apple Silicon."
            case .emptyResponse:
                return "Model returned no content."
            case .sessionFailed(let inner):
                return "Provider session failed: \(inner.localizedDescription)"
            }
        }
    }

    private let viewContext: NSManagedObjectContext
    private let chat: ChatEntity
    private var provider: any ChatProvider
    private var streamTask: Task<Void, Never>?
    private var cancelRequested = false
    private var lastUpdateTime = Date()
    private let updateInterval = AppConstants.streamedResponseUpdateUIInterval

    init(viewContext: NSManagedObjectContext, chat: ChatEntity) {
        self.viewContext = viewContext
        self.chat = chat
        self.provider = Self.makeProvider(for: chat)
    }

    /// Build the active `ChatProvider` based on the user's settings. Apple
    /// Intelligence is the default. If the user picked the OpenAI-
    /// compatible backend, we instantiate `LocalLLMProvider` against the
    /// configured base URL + model name.
    @available(macOS 26.0, *)
    static func makeProvider(for chat: ChatEntity) -> any ChatProvider {
        let id = UserDefaults.standard.string(forKey: "ai.provider") ?? AIProviderID.appleIntelligence.rawValue
        let providerID = AIProviderID(rawValue: id) ?? .appleIntelligence
        let instructions = (chat.persona?.systemMessage ?? chat.systemMessage ?? "")

        switch providerID {
        case .appleIntelligence:
            return AppleIntelligenceProvider(instructions: instructions, tools: ToolRegistry.shared.activeTools(for: chat))
        case .localOpenAI:
            let baseURLString = UserDefaults.standard.string(forKey: "ai.local.base_url")
                ?? "http://localhost:11434/v1/chat/completions"
            let model = UserDefaults.standard.string(forKey: "ai.local.model")
                ?? "qwen2.5-coder:7b"
            let apiKey = UserDefaults.standard.string(forKey: "ai.local.api_key")
            let url = URL(string: baseURLString) ?? URL(string: "http://localhost:11434/v1/chat/completions")!
            return LocalLLMProvider(
                endpoint: url,
                modelName: model,
                apiKey: apiKey,
                instructions: instructions,
                tools: ToolRegistry.shared.activeTools(for: chat)
            )
        }
    }

    // MARK: - Streaming

    func sendMessageStream(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        cancelRequested = false
        streamTask?.cancel()

        guard #available(macOS 26.0, *) else {
            completion(.failure(StreamingError.unsupported))
            return
        }

        provider.refreshSystemMessageIfNeeded(targetSystemMessage: chat.persona?.systemMessage ?? chat.systemMessage ?? "")

        // Build attachment context (PDF text + image base64 for vision models).
        let attachmentContext = self.makeAttachmentContext()

        // Compose the actual prompt: user's words + attachment context.
        let composedPrompt: String
        if attachmentContext.textContext.isEmpty {
            composedPrompt = message
        } else {
            composedPrompt = attachmentContext.formattedPrefix() + message
        }

        // Persist the user message immediately.
        let userMessage = MessageEntity(context: viewContext)
        userMessage.id = chat.nextSequence()
        userMessage.sequence = userMessage.id
        userMessage.body = message
        userMessage.timestamp = Date()
        userMessage.own = true
        userMessage.waitingForResponse = false
        userMessage.chat = chat
        chat.addToMessages(userMessage)
        chat.updatedDate = Date()
        chat.objectWillChange.send()

        do { try viewContext.save() } catch {
            print("MessageManager: failed to persist user message: \(error)")
        }

        // Pre-create the assistant bubble we'll mutate as tokens arrive.
        let assistantMessage = MessageEntity(context: viewContext)
        assistantMessage.id = chat.nextSequence()
        assistantMessage.sequence = assistantMessage.id
        assistantMessage.body = ""
        assistantMessage.timestamp = Date()
        assistantMessage.own = false
        assistantMessage.waitingForResponse = true
        assistantMessage.chat = chat
        chat.addToMessages(assistantMessage)
        chat.waitingForResponse = true
        chat.objectWillChange.send()

        // Remember the prompt so the post-processor can infer a save target
        // after streaming finishes.
        let promptForPostProcess = message
        let stream = provider.streamTurn(
            prompt: composedPrompt,
            attachments: attachmentContext
        )
        streamTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.streamTask = nil
                    chat.waitingForResponse = false
                    chat.objectWillChange.send()
                }
            }

            var accumulated = ""
            do {
                for try await event in stream {
                    if Task.isCancelled || self.cancelRequested { break }
                    switch event {
                    case .text(let chunk):
                        guard !chunk.isEmpty else { continue }
                        accumulated += chunk
                        self.commitChunkIfNeeded(
                            to: assistantMessage,
                            accumulated: accumulated
                        )
                    case .toolCall, .toolResult:
                        continue
                    case .fileSaved:
                        // Surfaced by post-processor below, not by the
                        // live stream.
                        continue
                    }
                }
            } catch is CancellationError {
                Task { @MainActor in
                    assistantMessage.waitingForResponse = false
                    if accumulated.isEmpty { self.viewContext.delete(assistantMessage) }
                    self.collapseIfEmpty(assistantMessage: assistantMessage, accumulated: accumulated)
                    completion(.failure(CancellationError()))
                }
                return
            } catch {
                Task { @MainActor in
                    assistantMessage.body = accumulated.isEmpty
                        ? "[error: \(error.localizedDescription)]"
                        : accumulated + "\n\n[error: \(error.localizedDescription)]"
                    assistantMessage.waitingForResponse = false
                    self.save()
                    completion(.failure(StreamingError.sessionFailed(error)))
                }
                return
            }

            Task { @MainActor in
                self.collapseIfEmpty(assistantMessage: assistantMessage, accumulated: accumulated)
                self.save()

                // After streaming, scan the model's text for code blocks
                // and auto-save to the path the user mentioned. The 3B
                // Foundation Model reliably emits long code in markdown
                // fences inside its reply, so this is the durable
                // instruction-following path for file creation.
                if !accumulated.isEmpty {
                    let blocks = ResponsePostProcessor.extractCodeBlocks(from: accumulated)
                    if !blocks.isEmpty,
                       let target = ResponsePostProcessor.detectSaveTarget(userMessage: promptForPostProcess)
                    {
                        let fm = FileManager.default
                        for (i, block) in blocks.enumerated() {
                            let ext = ResponsePostProcessor.fileExtension(for: block.language)
                            let baseStem: String
                            if let explicit = ResponsePostProcessor.extractFilenameHint(promptForPostProcess) {
                                baseStem = (explicit as NSString).deletingPathExtension
                            } else if i == 0 {
                                baseStem = "untitled"
                            } else {
                                baseStem = "untitled_\(i + 1)"
                            }
                            let fileName = blocks.count > 1
                                ? "\(baseStem)_\(i + 1).\(ext)"
                                : "\(baseStem).\(ext)"
                            let path = (target.directory as NSString)
                                .appendingPathComponent(fileName)
                            do {
                                try fm.createDirectory(
                                    at: URL(fileURLWithPath: target.directory),
                                    withIntermediateDirectories: true
                                )
                                try block.content.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
                                UserDefaults.standard.set(fileName, forKey: "tool.last_saved_filename")
                                // Append a small auto-save note to the bubble
                                // body so the user sees what happened.
                                let note = "\n\n_📄 auto-saved to `\(path)`_"
                                assistantMessage.body = (assistantMessage.body ?? "") + note
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("SiriCloneFileSaved"),
                                    object: nil,
                                    userInfo: ["path": path, "bytes": block.content.utf8.count]
                                )
                                print("[chunk saved] \(path) (\(block.content.utf8.count) bytes)")
                            } catch {
                                assistantMessage.body = (assistantMessage.body ?? "")
                                    + "\n\n_save failed: \(error.localizedDescription)_"
                            }
                        }
                        self.save()
                    }
                }

                self.postCompletionNotification(for: chat, body: accumulated)
                completion(.success(()))
            }
        }
    }

    private func collapseIfEmpty(assistantMessage: MessageEntity, accumulated: String) {
        if accumulated.isEmpty {
            viewContext.delete(assistantMessage)
            chat.objectWillChange.send()
        } else {
            assistantMessage.body = accumulated
            assistantMessage.waitingForResponse = false
        }
    }

    private func commitChunkIfNeeded(
        to message: MessageEntity,
        accumulated: String
    ) {
        let now = Date()
        // Throttle Core Data saves to avoid UI thrash during streaming.
        if now.timeIntervalSince(lastUpdateTime) >= updateInterval || accumulated.count < 64 {
            Task { @MainActor in
                message.body = accumulated
                message.timestamp = now
                message.waitingForResponse = false
                self.chat.objectWillChange.send()
            }
            lastUpdateTime = now
        }
    }

    func cancelCurrentRequest() {
        cancelRequested = true
        streamTask?.cancel()
    }

    // MARK: - Chat name generation

    func generateChatNameIfNeeded(chat: ChatEntity, force: Bool = false) {
        guard force || chat.name.isEmpty, !chat.messagesArray.isEmpty else { return }
        guard #available(macOS 26.0, *) else { return }

        let firstUserMessage = chat.messagesArray.first(where: { $0.own })?.body ?? "Chat"
        let prompt = "Suggest a short chat name (max 5 words, no emoji) summarizing: \(firstUserMessage.prefix(500)). Respond with just the name."

        Task { [weak self] in
            guard let self else { return }
            do {
                var collected = ""
                for try await event in self.provider.streamText(prompt: prompt) {
                    if Task.isCancelled { break }
                    collected += event
                    if collected.count > 80 { break }
                }
                await MainActor.run {
                    let trimmed = collected
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\n", with: " ")
                    chat.name = String(trimmed.prefix(60))
                    self.save()
                }
            } catch {
                // ignore — chat will just have no name
            }
        }
    }

    // MARK: - Helpers

    /// Build the AttachmentContext from the chat's currently-attached drafts.
    /// The actual attachment objects live on the ChatView's @State; we receive
    /// them through `currentAttachments`, which ChatView sets on the
    /// MessageManager right before each send.
    var currentAttachments: (images: [ImageAttachment], files: [DocumentAttachment]) = ([], [])

    private func makeAttachmentContext() -> AttachmentContext {
        AttachmentContext.build(
            attachedFiles: currentAttachments.files,
            attachedImages: currentAttachments.images
        )
    }

    private func save() {
        do { try viewContext.save() } catch {
            print("MessageManager.save failed: \(error)")
        }
    }

    private func postCompletionNotification(for chat: ChatEntity, body: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("ChatResponseCompleted"),
            object: chat,
            userInfo: [
                "responseId": UUID().uuidString,
                "chatId": chat.id,
                "message": body,
                "chatName": chat.name,
            ]
        )
    }
}