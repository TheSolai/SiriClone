//
//  DatabasePatcher.swift
//  SiriClone
//
//  SiriClone uses Apple Intelligence only — every multi-provider patch in
//  the original DatabasePatcher is now a no-op. We only seed the default
//  persona presets on first launch and patch any chat messages that lack
//  identifiers.
//

import CoreData
import Foundation

enum DatabasePatcher {

    /// Add the default persona presets if the user has none yet.
    static func initializeDatabaseIfNeeded(context: NSManagedObjectContext, persistence: PersistenceController) {
        let initializationKey = "DB_INITIALIZED"
        if persistence.getMetadata(forKey: initializationKey) as? Bool == true { return }

        addDefaultPersonasIfNeeded(context: context)
        persistence.setMetadata(value: true, forKey: initializationKey)
    }

    /// Force-add the default persona presets (e.g. user clicked "Add presets" in
    /// the AI Assistants settings page).
    static func addDefaultPersonasIfNeeded(context: NSManagedObjectContext, force: Bool = false) {
        addDefaultPersonas(context: context, force: force)
    }

    /// Apply post-init patches. All multi-provider patches are no-ops now.
    static func applyPatches(context: NSManagedObjectContext, persistence: PersistenceController) {
        addDefaultPersonasIfNeeded(context: context)
        patchMissingIDs(context: context, persistence: persistence)
    }

    static func migrateExistingConfiguration(context: NSManagedObjectContext, persistence: PersistenceController) {
        // No-op. Legacy api service / model migration no longer applies.
    }

    // MARK: - Default personas

    private static func addDefaultPersonas(context: NSManagedObjectContext, force: Bool = false) {
        let defaults = UserDefaults.standard
        if !force && defaults.bool(forKey: AppConstants.defaultPersonasFlag) { return }

        let request = PersonaEntity.fetchRequest()
        let existing = (try? context.fetch(request)) ?? []
        let existingNames = Set(existing.compactMap { $0.name })

        var added = false
        for preset in AppConstants.PersonaPresets.allPersonas where !existingNames.contains(preset.name) {
            let persona = PersonaEntity(context: context)
            persona.id = UUID()
            persona.name = preset.name
            persona.color = preset.color
            persona.systemMessage = preset.message
            persona.temperature = preset.temperature
            persona.order = Int16(AppConstants.PersonaPresets.allPersonas.firstIndex(of: preset) ?? 0)
            persona.addedDate = Date()
            persona.editedDate = Date()
            added = true
        }

        if added {
            do {
                try context.save()
                defaults.set(true, forKey: AppConstants.defaultPersonasFlag)
            } catch {
                print("DatabasePatcher: failed to seed personas: \(error)")
            }
        } else if !force {
            defaults.set(true, forKey: AppConstants.defaultPersonasFlag)
        }
    }

    private static func patchMissingIDs(context: NSManagedObjectContext, persistence: PersistenceController) {
        let key = "EntityIDBackfillCompleted"
        if persistence.getMetadata(forKey: key) as? Bool == true { return }

        let chatRequest: NSFetchRequest<ChatEntity> = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
        chatRequest.predicate = NSPredicate(format: "id == nil")
        if let chats = try? context.fetch(chatRequest) {
            for chat in chats { chat.id = UUID() }
        }

        do { try context.save() } catch { /* non-fatal */ }
        persistence.setMetadata(value: true, forKey: key)
    }
}