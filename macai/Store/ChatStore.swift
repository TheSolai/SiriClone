//
//  ChatStore.swift
//  SiriClone
//
//  Thin Core Data wrapper for chats. Multi-provider / API service delete
//  paths removed — Apple Intelligence only.
//

import CoreData
import Foundation
import SwiftUI

let migrationKey = "com.example.chatApp.migrationFromJSONCompleted"

class ChatStore: ObservableObject {
    let persistenceController: PersistenceController
    let viewContext: NSManagedObjectContext

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        self.viewContext = persistenceController.container.viewContext
        migrateFromJSONIfNeeded()
    }

    func saveInCoreData() {
        Task { @MainActor in
            self.viewContext.saveWithRetry(attempts: 1)
        }
    }

    func loadFromCoreData(completion: @escaping (Result<[Chat], Error>) -> Void) {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
        do {
            let chatEntities = try self.viewContext.fetch(fetchRequest)
            let chats = chatEntities.map { Chat(chatEntity: $0) }
            DispatchQueue.main.async { completion(.success(chats)) }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }

    func saveToCoreData(chats: [Chat], completion: @escaping (Result<Int, Error>) -> Void) {
        do {
            for oldChat in chats {
                let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
                fetchRequest.predicate = NSPredicate(format: "id == %@", oldChat.id as CVarArg)
                let existingChats = try viewContext.fetch(fetchRequest)
                if existingChats.isEmpty {
                    let chatEntity = ChatEntity(context: viewContext)
                    chatEntity.id = oldChat.id
                    chatEntity.newChat = oldChat.newChat
                    chatEntity.temperature = oldChat.temperature ?? 0.0
                    chatEntity.top_p = oldChat.top_p ?? 0.0
                    chatEntity.behavior = oldChat.behavior
                    chatEntity.draftMessage = oldChat.newMessage ?? ""
                    chatEntity.createdDate = Date()
                    chatEntity.updatedDate = Date()
                    chatEntity.requestMessages = oldChat.requestMessages
                    chatEntity.gptModel = oldChat.gptModel ?? AppConstants.defaultAppleIntelligenceSystemMessage
                    chatEntity.systemMessage = oldChat.systemMessage ?? AppConstants.defaultAppleIntelligenceSystemMessage
                    chatEntity.name = oldChat.name ?? ""

                    if let personaName = oldChat.personaName {
                        let personaFetch = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
                        personaFetch.predicate = NSPredicate(format: "name == %@", personaName)
                        if let existingPersona = try viewContext.fetch(personaFetch).first {
                            chatEntity.persona = existingPersona
                        }
                    }

                    var nextSequence: Int64 = 0
                    for oldMessage in oldChat.messages {
                        nextSequence += 1
                        let messageEntity = MessageEntity(context: viewContext)
                        messageEntity.id = Int64(oldMessage.id)
                        messageEntity.sequence = nextSequence
                        messageEntity.name = oldMessage.name
                        messageEntity.body = oldMessage.body
                        messageEntity.timestamp = oldMessage.timestamp
                        messageEntity.own = oldMessage.own
                        messageEntity.waitingForResponse = oldMessage.waitingForResponse ?? false
                        messageEntity.chat = chatEntity
                        chatEntity.applySequenceIfNeeded(to: messageEntity)
                        chatEntity.addToMessages(messageEntity)
                    }
                    chatEntity.lastSequence = max(chatEntity.lastSequence, nextSequence)
                }
            }
            try viewContext.save()
            DispatchQueue.main.async { completion(.success(chats.count)) }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }

    func deleteAllChats() {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
        do {
            for chat in try viewContext.fetch(fetchRequest) {
                viewContext.delete(chat)
            }
            try viewContext.save()
        } catch {
            print("Error deleting all chats: \(error)")
        }
    }

    func deleteAllPersonas() {
        let fetchRequest = PersonaEntity.fetchRequest()
        do {
            for persona in try viewContext.fetch(fetchRequest) {
                viewContext.delete(persona)
            }
            try viewContext.save()
        } catch {
            print("Error deleting all assistants: \(error)")
        }
    }

    func deleteAllAPIServices() {
        // No-op — SiriClone has no API services. Retained for call-site compatibility.
    }

    private static func fileURL() throws -> URL {
        try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("chats.data")
    }

    private func migrateFromJSONIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        UserDefaults.standard.set(true, forKey: migrationKey)
        // Old macai JSON files are no longer supported. Backups remain under
        // ~/Library/Application Support/<bundle>/Backups/.
    }
}