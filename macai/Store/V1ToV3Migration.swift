//
//  V1ToV3Migration.swift
//  SiriClone
//
//  No-op stub. The Core Data schema is unchanged for SiriClone — the only
//  store open path is via the standard NSPersistentContainer load. If a
//  user's existing store happens to be on the macai v3 model it will load
//  as-is; older stores will fail to open cleanly and the user will be
//  prompted to start fresh (their data is still under
//  ~/Library/Application Support/<bundle>/Backups/).
//

import AppKit
import CoreData
import Foundation

struct MigrationState {
    let needsMigration: Bool
    let exportedData: MigrationDataExport?
    let progressWindow: MigrationProgressWindow?
}

final class ProgrammaticMigrator {
    private let containerName: String

    init(containerName: String) {
        self.containerName = containerName
    }

    func prepareIfNeeded() -> MigrationState {
        MigrationState(needsMigration: false, exportedData: nil, progressWindow: nil)
    }

    func handleStoreLoadError(_ error: Error?, state: MigrationState) {
        guard let error = error else { return }
        let alert = NSAlert()
        alert.messageText = "Database Error"
        alert.informativeText = """
        Failed to load the database. This usually means the data was created
        by an older SiriClone build. Your backups are in:
        ~/Library/Application Support/\(Bundle.main.bundleIdentifier ?? "SiriClone")/Backups/

        Error: \(error.localizedDescription)
        """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func importIfNeeded(state: MigrationState, into container: NSPersistentContainer) {
        // No-op.
    }

    func recoverFromLoadFailure(container: NSPersistentContainer) -> Bool { false }

    private static func storeURL(for containerName: String) -> URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("\(containerName).sqlite")
    }
}

final class MigrationDataExport {
    static func exportFromStore(at url: URL, progressWindow: MigrationProgressWindow?) -> MigrationDataExport? {
        nil
    }
    func importIntoContext(_ context: NSManagedObjectContext, progressWindow: MigrationProgressWindow?) -> Bool {
        false
    }
}

final class MigrationProgressWindow {
    static let totalSteps = 1
    func show() {}
    func close() {}
    func setTotalSteps(_ steps: Int, initialMessage: String) {}
    func showSuccessAndClose(after seconds: TimeInterval) {}
}

final class CoreDataBackupManager {
    static func needsMigrationBackup(containerName: String) -> Bool { false }
    static func createPreMigrationBackup(containerName: String) {}
    static func markMigrationCompleted() {}
    static func clearMigrationRetrySkipBackupFlag() {}
    static func shouldAttemptProgrammaticRecovery(containerName: String) -> Bool { false }
    static func createRecoveryBackup(containerName: String, reason: String) {}
    static func deleteLegacyStores(for containerName: String) {}
}