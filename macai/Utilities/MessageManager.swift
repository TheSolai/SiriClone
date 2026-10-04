//
//  MessageManager.swift
//  SiriClone
//
//  Drives one chat turn against an on-device Apple Intelligence session.
//  Builds a fresh `LanguageModelSession` (rebuilds on system message change)
//  and streams tokens into Core Data while the user watches.
//
//  Replaces the old multi-provider APIService-based MessageManager.
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
                return "Apple Intelligence requires macOS 15 or later on Apple Silicon."
            case .emptyResponse:
                return "Apple Intelligence returned no content."
            case .sessionFailed(let inner):
                return "Apple Intelligence session failed: \(inner.localizedDescription)"
            }
        }
    }

    private let viewContext: NSManagedObjectContext
    private let chat: ChatEntity
    private var provider: AppleIntelligenceProvider
    private var streamTask: Task<Void, Never>?
    private var cancelRequested = false
    private var lastUpdateTime = Date()
    private let updateInterval = AppConstants.streamedResponseUpdateUIInterval

    init(viewContext: NSManagedObjectContext, chat: ChatEntity) {
        self.viewContext = viewContext
        self.chat = chat
        self.provider = AppleIntelligenceProvider.makeForChat(chat)
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

        // Rebuild session if the persona/system message changed since last turn.
        provider.refreshSystemMessageIfNeeded(for: chat)

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

        let stream = provider.streamTurn(prompt: message)
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
                        // Tool call visibility in the UI is Phase 2. For now we
                        // just let the model resume generation silently.
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