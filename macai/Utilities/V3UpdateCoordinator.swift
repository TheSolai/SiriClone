//
//  V3UpdateCoordinator.swift
//  SiriClone
//
//  Stubbed Sparkle update coordinator. SiriClone doesn't surface an in-app
//  update flow — Sparkle is left wired up via the bundle but never
//  instantiated here.
//

import AppKit
import Combine
import Foundation

final class V3UpdateCoordinator: ObservableObject {
    static let shared = V3UpdateCoordinator()

    @Published var availableV3Version: String? = nil

    private init() {}

    func checkForUpdates() {
        // No-op. Users update via the App Store or direct download.
    }

    func checkForUpdatesInBackground() {
        // No-op.
    }

    func showAvailableV3Upgrade() {
        // No-op — SiriClone has no v2→v3 upgrade flow.
    }

    func previewV3UpgradeNotice() {
        // No-op.
    }

    /// Backwards-compat shim. The original `updater.automaticallyChecksForUpdates`
    /// setter on SPUUpdater — we keep the same name so callers compile, but
    /// route to UserDefaults since we never instantiate an SPUUpdater.
    var updater: StubUpdater { StubUpdater.shared }
}

final class StubUpdater {
    static let shared = StubUpdater()
    private init() {}

    var automaticallyChecksForUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: "autoCheckForUpdates") }
        set { UserDefaults.standard.set(newValue, forKey: "autoCheckForUpdates") }
    }
}