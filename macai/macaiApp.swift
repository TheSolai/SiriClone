//
//  macaiApp.swift
//  SiriClone
//
//  Siri with Apple Intelligence. iCloud sync, API services, multi-provider
//  plumbing — all removed. Foundation Models on-device is the only backend.
//

import AppKit
import CoreData
import Foundation
import SwiftUI
import UserNotifications

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates: Bool = true
    init() {}
}

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel = CheckForUpdatesViewModel()
    private let updateCoordinator: V3UpdateCoordinator
    init(updateCoordinator: V3UpdateCoordinator) {
        self.updateCoordinator = updateCoordinator
    }
    var body: some View {
        Button("Check for Updates…", action: updateCoordinator.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer
    private let migrator = ProgrammaticMigrator(containerName: "macaiDataModel")
    private var historyToken: NSPersistentHistoryToken?

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "macaiDataModel")

        for description in container.persistentStoreDescriptions {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        }

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

        let migrationState = migrator.prepareIfNeeded()

        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)

        if let error = loadError {
            migrator.handleStoreLoadError(error, state: migrationState)
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        migrator.importIfNeeded(state: migrationState, into: container)

        DatabasePatcher.initializeDatabaseIfNeeded(context: container.viewContext, persistence: self)
        DatabasePatcher.applyPatches(context: container.viewContext, persistence: self)
    }

    /// Lightweight key/value metadata on the persistent store. Used by
    /// DatabasePatcher to remember which one-shot migrations have run.
    func getMetadata(forKey key: String) -> Any? {
        guard let store = container.persistentStoreCoordinator.persistentStores.first else { return nil }
        return container.persistentStoreCoordinator.metadata(for: store)[key]
    }

    func setMetadata(value: Any?, forKey key: String) {
        guard let store = container.persistentStoreCoordinator.persistentStores.first else { return }
        if store.isReadOnly { return }
        var md = container.persistentStoreCoordinator.metadata(for: store)
        md[key] = value
        container.persistentStoreCoordinator.setMetadata(md, for: store)
        if container.viewContext.hasChanges { try? container.viewContext.save() }
    }
}

@main
struct macaiApp: App {
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: Int = 0
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)

    var preferredColorScheme: ColorScheme? {
        switch preferredColorSchemeRaw {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    private let updateCoordinator = V3UpdateCoordinator.shared
    let persistenceController = PersistenceController.shared

    init() {
        ValueTransformer.setValueTransformer(
            RequestMessagesTransformer(),
            forName: RequestMessagesTransformer.name
        )
        NotificationPresenter.shared.configure()
        NotificationPresenter.shared.requestAuthorizationIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .preferredColorScheme(preferredColorScheme)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active, UserDefaults.standard.bool(forKey: "autoCheckForUpdates") {
                updateCoordinator.checkForUpdatesInBackground()
            }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updateCoordinator: updateCoordinator)
            }

            CommandMenu("Chat") {
                Button("Find in Chat") {
                    NotificationCenter.default.post(name: NSNotification.Name("ActivateSearch"), object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Clear Chat") {
                    NotificationCenter.default.post(name: NSNotification.Name("ClearChat"), object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])

                Button("Retry Last Message") {
                    NotificationCenter.default.post(name: NSNotification.Name("RetryMessage"), object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Stop Response") {
                    NotificationCenter.default.post(name: NSNotification.Name("StopInference"), object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()

                Button("Export Chat as Markdown…") {
                    NotificationCenter.default.post(name: NSNotification.Name("ExportChatMarkdown"), object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .option])

                Button("Export Chat as Plain Text…") {
                    NotificationCenter.default.post(name: NSNotification.Name("ExportChatText"), object: nil)
                }

                Button("Export Chat as JSON…") {
                    NotificationCenter.default.post(name: NSNotification.Name("ExportChatJSON"), object: nil)
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(
                        name: AppConstants.newChatNotification,
                        object: nil,
                        userInfo: ["windowId": NSApp.keyWindow?.windowNumber ?? 0]
                    )
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Window") {
                    NSApplication.shared.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        with: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
        }

        Settings {
            PreferencesView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .preferredColorScheme(preferredColorScheme)
        }
    }
}