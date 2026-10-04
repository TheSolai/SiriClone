//
//  TabDangerZoneView.swift
//  SiriClone
//
//  Apple Intelligence only — no API services section.
//

import SwiftUI

struct DangerZoneView: View {
    @ObservedObject var store: ChatStore
    @State private var currentAlert: AlertType?

    enum AlertType: Identifiable {
        case deleteChats, deletePersonas
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(
                    "Here you can remove all chats and AI Assistants. Use with caution: this action cannot be undone."
                )
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.bottom, 16)

            VStack(alignment: .leading) {
                Button(
                    action: { currentAlert = .deleteChats },
                    label: { Text("Delete all chats") }
                )
                Button(action: { currentAlert = .deletePersonas }) {
                    Text("Delete all AI Assistants")
                }
            }
        }
        .padding(32)
        .alert(item: $currentAlert) { alertType in
            switch alertType {
            case .deleteChats:
                return Alert(
                    title: Text("Delete All Chats"),
                    message: Text("Are you sure you want to delete all chats? This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) { store.deleteAllChats() },
                    secondaryButton: .cancel()
                )
            case .deletePersonas:
                return Alert(
                    title: Text("Delete All AI Assistants"),
                    message: Text("Are you sure you want to delete all AI Assistants?"),
                    primaryButton: .destructive(Text("Delete")) { store.deleteAllPersonas() },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}