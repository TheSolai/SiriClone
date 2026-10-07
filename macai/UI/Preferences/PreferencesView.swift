//
//  PreferencesView.swift
//  SiriClone
//
//  Apple Intelligence only — API Services tab replaced with Tools tab.
//

import SwiftUI

struct PreferencesView: View {
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @State private var lampColor: Color = .gray

    var body: some View {
        TabView {
            TabGeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            TabModelsView()
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }

            TabToolsView()
                .tabItem {
                    Label("Tools", systemImage: "wrench.and.screwdriver")
                }

            TabAIPersonasView()
                .tabItem {
                    Label("AI Assistants", systemImage: "person.2")
                }

            BackupRestoreView(store: store)
                .tabItem {
                    Label("Backup & Restore", systemImage: "externaldrive")
                }

            DangerZoneView(store: store)
                .tabItem {
                    Label("Danger Zone", systemImage: "flame.fill")
                }
        }
        .frame(width: 520)
        .padding()
        .onAppear {
            store.saveInCoreData()
            if let window = NSApp.mainWindow {
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }
        }
    }
}