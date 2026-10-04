//
//  ContentView.swift
//  SiriClone
//
//  Apple Intelligence only — API service picker and logo images removed.
//

import AppKit
import Combine
import CoreData
import Foundation
import SwiftUI

struct ContentView: View {
    private static var handledStartChatRequestIds = Set<String>()
    private static var handledResponseIds = Set<String>()

    @State private var window: NSWindow?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        entity: ChatEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)]
    )
    private var chats: FetchedResults<ChatEntity>

    @State var selectedChat: ChatEntity?
    @AppStorage("systemMessage") var systemMessage = AppConstants.defaultAppleIntelligenceSystemMessage
    @AppStorage("lastOpenedChatId") var lastOpenedChatId = ""
    @AppStorage(SettingsIndicatorKeys.generalSeen) private var generalSettingsSeen: Bool = false
    @StateObject private var previewStateManager = PreviewStateManager()
    @StateObject private var attentionStore = ChatAttentionStore.shared

    @State private var windowRef: NSWindow?
    @State private var openedChatId: String? = nil
    @AppStorage("isSidebarVisible") var isSidebarVisible = true
    @State private var lastChatCount: Int? = nil
    @State private var searchText = ""
    @State private var isSearchPresented = false

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { isSidebarVisible ? .all : .detailOnly },
            set: { isSidebarVisible = $0 != .detailOnly }
        )) {
            ChatListView(selectedChat: $selectedChat, searchText: $searchText)
                .environmentObject(attentionStore)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 400)
        } detail: {
            HSplitView {
                if selectedChat != nil {
                    ChatView(viewContext: viewContext, chat: selectedChat!, searchText: $searchText)
                        .frame(minWidth: 400)
                        .id(openedChatId)
                } else {
                    EmptyChatsView(chatsCount: chats.count, newChat: newChat)
                }

                if previewStateManager.isPreviewVisible {
                    PreviewPane(stateManager: previewStateManager)
                }
            }
            .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .toolbar, prompt: "Search in chat…")
            .onSubmit(of: .search) {
                NotificationCenter.default.post(name: NSNotification.Name("FindNext"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ActivateSearch"))) { _ in
                NSApp.keyWindow?.makeFirstResponder(nil)
                isSearchPresented = true
            }
            .onAppear {
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 36 && event.modifierFlags.contains(.shift) && isSearchPresented && !searchText.isEmpty {
                        if let firstResponder = NSApp.keyWindow?.firstResponder as? NSView,
                           String(describing: type(of: firstResponder)).contains("Search") {
                            NotificationCenter.default.post(name: NSNotification.Name("FindPrevious"), object: nil)
                            return nil
                        }
                    }
                    if event.keyCode == 51 && event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift) {
                        if selectedChat != nil {
                            clearSelectedChat()
                            return nil
                        }
                    }
                    return event
                }
            }
        }
        .onAppear {
            if chats.count == 0 { isSidebarVisible = false }
            lastChatCount = chats.count
            if let lastOpenedChatId = UUID(uuidString: lastOpenedChatId),
               let lastOpenedChat = chats.first(where: { $0.id == lastOpenedChatId }) {
                selectedChat = lastOpenedChat
            }
        }
        .onChange(of: chats.count) { newCount in
            if let prev = lastChatCount {
                updateSidebarVisibilityForChatCount(previousCount: prev, newCount: newCount)
            }
            lastChatCount = newCount
        }
        .background(WindowAccessor(window: $window))
        .onAppear {
            NotificationCenter.default.addObserver(
                forName: AppConstants.newChatNotification,
                object: nil,
                queue: .main
            ) { _ in
                guard !ContentView.handledStartChatRequestIds.contains(UUID().uuidString) else { return }
                newChat()
            }
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                if let selectedId = selectedChat?.id { attentionStore.clear(selectedId) }
            }
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ExportChatMarkdown"),
                object: nil, queue: .main
            ) { _ in exportSelectedChat(format: .markdown) }
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ExportChatText"),
                object: nil, queue: .main
            ) { _ in exportSelectedChat(format: .text) }
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ExportChatJSON"),
                object: nil, queue: .main
            ) { _ in exportSelectedChat(format: .json) }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { newChat() }) {
                    Image(systemName: "square.and.pencil")
                }
                .help("New chat (⌘N)")

                if #available(macOS 14.0, *) {
                    SettingsLink { settingsGearIcon }
                } else {
                    Button(action: { openPreferencesView() }) { settingsGearIcon }
                }
            }
        }
        .onChange(of: scenePhase) { _ in }
        .onChange(of: selectedChat) { newValue in
            if self.openedChatId != newValue?.id.uuidString {
                self.openedChatId = newValue?.id.uuidString
                previewStateManager.hidePreview()
            }
            if let selectedId = newValue?.id { attentionStore.clear(selectedId) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ChatResponseCompleted"))) { notification in
            if let responseId = notification.userInfo?["responseId"] as? String {
                if ContentView.handledResponseIds.contains(responseId) { return }
                ContentView.handledResponseIds.insert(responseId)
            }
            guard let chatId = notification.userInfo?["chatId"] as? UUID else { return }
            let isKeyWindow = window?.isKeyWindow ?? false
            let isActiveChat = selectedChat?.id == chatId
            let appIsActive = scenePhase == .active && NSApp.isActive
            if appIsActive && !isKeyWindow { return }
            if !isActiveChat || !appIsActive {
                attentionStore.mark(chatId)
                let chatName = chatDisplayName(
                    for: chatId,
                    fallback: notification.userInfo?["chatName"] as? String
                )
                let message = notification.userInfo?["message"] as? String ?? ""
                let body = notificationBody(from: message)
                NotificationPresenter.shared.scheduleNotification(
                    identifier: "chat-response-\(chatId.uuidString)-\(Date().timeIntervalSince1970)",
                    title: chatName,
                    body: body
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ClearChat"))) { _ in
            if selectedChat != nil { clearSelectedChat() }
        }
        .environmentObject(previewStateManager)
    }

    private var settingsGearIcon: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "gear")
            if SettingsIndicatorState.needsAttention(generalSeen: generalSettingsSeen) {
                SettingsIndicatorDot().offset(x: 1, y: -1)
            }
        }
    }

    func newChat() {
        let uuid = UUID()
        let chat = ChatEntity(context: viewContext)
        chat.id = uuid
        chat.newChat = true
        chat.temperature = 1
        chat.top_p = 1.0
        chat.behavior = "default"
        chat.draftMessage = ""
        chat.createdDate = Date()
        chat.updatedDate = Date()
        chat.systemMessage = systemMessage
        chat.gptModel = "apple-intelligence"
        chat.lastSequence = 0

        do {
            try viewContext.save()
            selectedChat = chat
        } catch {
            print("Error saving new chat: \(error.localizedDescription)")
            viewContext.rollback()
        }
    }

    func openPreferencesView() {
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    func clearSelectedChat() {
        guard let chat = selectedChat else { return }
        let alert = NSAlert()
        alert.messageText = "Clear chat \(chat.name)?"
        alert.informativeText = "Are you sure you want to delete all messages from this chat? Chat parameters will not be deleted. This action cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                chat.clearMessages()
                do { try viewContext.save() }
                catch { print("Error clearing chat: \(error.localizedDescription)") }
            }
        }
    }

    private func updateSidebarVisibilityForChatCount(previousCount: Int, newCount: Int) {
        if newCount == 0 { isSidebarVisible = false; return }
        if previousCount == 0 && newCount > 0 { isSidebarVisible = true }
    }

    private func exportSelectedChat(format: ExportFormat) {
        guard let chat = selectedChat else { return }
        let body: String
        switch format {
        case .markdown: body = ExportChatTool.asMarkdown(chat: chat)
        case .text: body = ExportChatTool.asText(chat: chat)
        case .json: body = ExportChatTool.asJSON(chat: chat)
        }
        let panel = NSSavePanel()
        let ext = format.rawValue
        panel.allowedContentTypes = [.init(filenameExtension: ext)].compactMap { $0 }
        panel.nameFieldStringValue = "\(chat.name.isEmpty ? "chat" : chat.name).\(ext)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }
}

private extension ContentView {
    enum ExportFormat: String { case markdown, text, json }

    func chatDisplayName(for chatId: UUID, fallback: String?) -> String {
        if let chat = chats.first(where: { $0.id == chatId }) {
            if !chat.name.isEmpty { return chat.name }
            if let persona = chat.persona?.name, !persona.isEmpty { return persona }
        }
        if let fallback, !fallback.isEmpty { return fallback }
        return "Chat"
    }

    func notificationBody(from message: String) -> String {
        if message.isEmpty { return "Response finished" }
        let messageWithoutNewlines = message.replacingOccurrences(of: "\n", with: " ")
        let messageWithoutThinking = messageWithoutNewlines.replacingOccurrences(
            of: "<think>.*?</think>",
            with: "",
            options: .regularExpression
        )
        let trimmed = messageWithoutThinking.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 160
        if trimmed.count > maxLength {
            let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
            return String(trimmed[..<index]) + "…"
        }
        return trimmed
    }
}

struct PreviewPane: View {
    @ObservedObject var stateManager: PreviewStateManager
    var body: some View {
        // Stub — preview pane from upstream not ported. Empty placeholder
        // so references in the existing split view still compile.
        EmptyView()
    }
}

private struct EmptyChatsView: View {
    let chatsCount: Int
    let newChat: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 56))
                .foregroundStyle(.purple)
            Text("Ask Siri with Apple Intelligence")
                .font(.title2)
                .fontWeight(.semibold)
            Text("This chat runs on-device with Foundation Models. Tools are configurable in Settings → Tools.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: newChat) {
                Label("Start a new chat", systemImage: "square.and.pencil")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}