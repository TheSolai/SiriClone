//
//  NotificationTool.swift
//  SiriClone
//
//  Post a macOS user notification. Default state is ON. Uses the system's
//  UserNotifications framework so notifications appear in Notification
//  Center alongside system notifications.
//

import Foundation
import FoundationModels
import UserNotifications

@available(macOS 26.0, *)
struct NotificationTool: Tool {
    let name = "notify"
    let description = """
    Post a macOS user notification with a title and body. Default state is ON. \
    Notifications appear in Notification Center.
    """

    @Generable(description: "Arguments for notify")
    struct Arguments {
        @Guide(description: "Notification title (short, capitalized).")
        var title: String
        @Guide(description: "Notification body text.")
        var body: String
        @Guide(description: "Optional subtitle.")
        var subtitle: String
    }

    func call(arguments: Arguments) async throws -> String {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = arguments.body
        let subtitle = arguments.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw SiriToolError.invalidArgument("notify requires non-empty 'title'.")
        }
        guard !body.isEmpty else {
            throw SiriToolError.invalidArgument("notify requires non-empty 'body'.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: SiriToolError.systemError(
                        "notification authorization failed: \(error.localizedDescription)"
                    ))
                    return
                }
                guard granted else {
                    continuation.resume(throwing: SiriToolError.disabledByUser(
                        "Notification permission denied. Enable in System Settings → Notifications → SiriClone."
                    ))
                    return
                }

                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                if !subtitle.isEmpty { content.subtitle = subtitle }
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
                UNUserNotificationCenter.current().add(request) { err in
                    if let err {
                        continuation.resume(throwing: SiriToolError.systemError(
                            "could not post notification: \(err.localizedDescription)"
                        ))
                    } else {
                        continuation.resume(returning: "Notification posted: \(title)")
                    }
                }
            }
        }
    }
}