//
//  ChatViewModel.swift
//  SiriClone
//
//  Apple Intelligence only — the APIService plumbing is gone. The
//  MessageManager is constructed against the active chat and rebuilt when
//  the persona/system message changes.
//

import Combine
import CoreData
import Foundation
import SwiftUI

struct SearchOccurrence: Equatable {
    let messageID: NSManagedObjectID
    let range: NSRange
    let elementIndex: Int
    let elementType: String

    static func == (lhs: SearchOccurrence, rhs: SearchOccurrence) -> Bool {
        return lhs.messageID == rhs.messageID &&
               NSEqualRanges(lhs.range, rhs.range) &&
               lhs.elementIndex == rhs.elementIndex &&
               lhs.elementType == rhs.elementType
    }

    var scrollTargetID: String {
        let messageIDString = messageID.uriRepresentation().absoluteString
        return "\(messageIDString)_\(elementIndex)_\(range.location)_\(range.length)"
    }
}

final class ChatViewModel: NSObject, ObservableObject, NSFetchedResultsControllerDelegate {
    @Published var searchOccurrences: [SearchOccurrence] = []
    @Published var currentSearchIndex: Int? = nil
    @Published var sortedMessages: [MessageEntity] = []

    var currentSearchOccurrence: SearchOccurrence? {
        if let index = currentSearchIndex, searchOccurrences.indices.contains(index) {
            return searchOccurrences[index]
        }
        return nil
    }

    @Published var messages: NSSet?
    private let chat: ChatEntity
    private let viewContext: NSManagedObjectContext
    private let fetchedResultsController: NSFetchedResultsController<MessageEntity>

    private var _messageManager: MessageManager?
    @MainActor
    private var messageManager: MessageManager {
        if _messageManager == nil {
            _messageManager = createMessageManager()
        }
        return _messageManager!
    }

    private var cancellables = Set<AnyCancellable>()
    private var searchDebounceTimer: Timer?

    init(chat: ChatEntity, viewContext: NSManagedObjectContext) {
        self.chat = chat
        self.messages = chat.messages
        self.viewContext = viewContext

        let fetchRequest = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
        fetchRequest.predicate = NSPredicate(format: "chat == %@", chat)
        fetchRequest.sortDescriptors = chat.messageSortDescriptors

        self.fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        super.init()
        self.fetchedResultsController.delegate = self

        do {
            try fetchedResultsController.performFetch()
            self.sortedMessages = fetchedResultsController.fetchedObjects ?? []
        } catch {
            print("Error performing fetch: \(error)")
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DispatchQueue.main.async {
            self.sortedMessages = self.fetchedResultsController.fetchedObjects ?? []
            self.messages = self.chat.messages
        }
    }

    @MainActor
    func sendMessage(
        _ message: String,
        contextSize: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        messageManager.sendMessageStream(
            message,
            in: chat,
            contextSize: contextSize
        ) { [weak self] result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
            _ = self
        }
    }

    @MainActor
    func sendMessageStream(_ message: String, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        messageManager.sendMessageStream(message, in: chat, contextSize: contextSize) { [weak self] result in
            switch result {
            case .success:
                self?.chat.objectWillChange.send()
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    @MainActor
    func stopInference() {
        messageManager.cancelCurrentRequest()
    }

    @MainActor
    func generateChatNameIfNeeded() {
        messageManager.generateChatNameIfNeeded(chat: chat)
    }

    func reloadMessages() {
        sortedMessages = fetchedResultsController.fetchedObjects ?? []
        messages = chat.messages
    }

    @MainActor
    private func createMessageManager() -> MessageManager {
        MessageManager(viewContext: viewContext, chat: chat)
    }

    @MainActor
    func recreateMessageManager() {
        _messageManager = createMessageManager()
    }

    @MainActor
    func regenerateChatName() {
        messageManager.generateChatNameIfNeeded(chat: chat, force: true)
    }

    // MARK: - Search

    func updateSearchOccurrences(searchText: String) {
        searchDebounceTimer?.invalidate()
        if searchText.isEmpty {
            searchOccurrences = []
            currentSearchIndex = nil
            return
        }
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.searchDebounceTime, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let messagesData = self.sortedMessages.map { (id: $0.objectID, body: $0.body) }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.performSearch(searchText: searchText, messagesData: messagesData)
            }
        }
    }

    private func performSearch(searchText: String, messagesData: [(id: NSManagedObjectID, body: String)]) {
        var occurrences: [SearchOccurrence] = []
        if !searchText.isEmpty {
            let parser = MessageParser(colorScheme: .light)
            for message in messagesData {
                let parsedElements = parser.parseMessageFromString(input: message.body)
                for (elementIndex, element) in parsedElements.enumerated() {
                    if case .table(let header, let data) = element {
                        for (columnIndex, headerCell) in header.enumerated() {
                            var searchStartIndex = headerCell.startIndex
                            while let range = headerCell.range(of: searchText, options: .caseInsensitive, range: searchStartIndex..<headerCell.endIndex) {
                                let nsRange = NSRange(range, in: headerCell)
                                let adjustedRange = NSRange(location: nsRange.location + columnIndex * 10000, length: nsRange.length)
                                occurrences.append(SearchOccurrence(
                                    messageID: message.id, range: adjustedRange,
                                    elementIndex: elementIndex, elementType: "table"
                                ))
                                searchStartIndex = range.upperBound <= searchStartIndex ? headerCell.index(after: searchStartIndex) : range.upperBound
                                if searchStartIndex >= headerCell.endIndex { break }
                            }
                        }
                        for (rowIndex, row) in data.enumerated() {
                            for (columnIndex, cell) in row.enumerated() {
                                var searchStartIndex = cell.startIndex
                                while let range = cell.range(of: searchText, options: .caseInsensitive, range: searchStartIndex..<cell.endIndex) {
                                    let nsRange = NSRange(range, in: cell)
                                    let cellPosition = (rowIndex + 1) * 1000 + columnIndex
                                    let adjustedRange = NSRange(location: nsRange.location + cellPosition * 10000, length: nsRange.length)
                                    occurrences.append(SearchOccurrence(
                                        messageID: message.id, range: adjustedRange,
                                        elementIndex: elementIndex, elementType: "table"
                                    ))
                                    searchStartIndex = range.upperBound <= searchStartIndex ? cell.index(after: searchStartIndex) : range.upperBound
                                    if searchStartIndex >= cell.endIndex { break }
                                }
                            }
                        }
                    } else {
                        let (content, elementType) = extractContentAndType(from: element)
                        var searchStartIndex = content.startIndex
                        while let range = content.range(of: searchText, options: .caseInsensitive, range: searchStartIndex..<content.endIndex) {
                            let nsRange = NSRange(range, in: content)
                            occurrences.append(SearchOccurrence(
                                messageID: message.id, range: nsRange,
                                elementIndex: elementIndex, elementType: elementType
                            ))
                            searchStartIndex = range.upperBound <= searchStartIndex ? content.index(after: searchStartIndex) : range.upperBound
                            if searchStartIndex >= content.endIndex { break }
                        }
                    }
                }
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.searchOccurrences = occurrences
            self?.currentSearchIndex = occurrences.isEmpty ? nil : 0
        }
    }

    private func extractContentAndType(from element: MessageElements) -> (String, String) {
        switch element {
        case .text(let content): return (content, "text")
        case .code(let code, _, _): return (code, "code")
        case .table(let header, let data):
            let headerText = header.joined(separator: " ")
            let dataText = data.map { $0.joined(separator: " ") }.joined(separator: " ")
            return (headerText + " " + dataText, "table")
        case .formula(let content): return (content, "formula")
        case .thinking(let content, _): return (content, "thinking")
        case .image: return ("", "image")
        case .file(let fileInfo): return (fileInfo.filename, "file")
        }
    }

    func goToNextOccurrence() {
        guard let currentIndex = currentSearchIndex, !searchOccurrences.isEmpty else { return }
        let nextIndex = currentIndex + 1
        currentSearchIndex = nextIndex >= searchOccurrences.count ? 0 : nextIndex
    }

    func goToPreviousOccurrence() {
        guard let currentIndex = currentSearchIndex, !searchOccurrences.isEmpty else { return }
        let prevIndex = currentIndex - 1
        currentSearchIndex = prevIndex < 0 ? searchOccurrences.count - 1 : prevIndex
    }

    var canSendMessage: Bool { true }
}