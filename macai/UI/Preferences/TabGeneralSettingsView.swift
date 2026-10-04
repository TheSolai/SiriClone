//
//  TabGeneralSettingsView.swift
//  SiriClone
//
//  General settings: theme, font size, code font, sidebar, updates.
//  Removed: iCloud sync, API key config, cloud sync log.
//

import AppKit
import AttributedText
import SwiftUI

struct TabGeneralSettingsView: View {
    private let previewCode = """
    func bar() -> Int {
        var 🍺: Double = 0
        var 🧑‍🔬: Double = 1
        while 🧑‍🔬 > 0 {
            🍺 += 1/🧑‍🔬
            🧑‍🔬 *= 2
            if 🍺 >= 2 {
                break
            }
        }
        return Int(🍺)
    }
    """
    @AppStorage("autoCheckForUpdates") var autoCheckForUpdates = true
    @AppStorage("chatFontSize") var chatFontSize: Double = 14.0
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: Int = 0
    @AppStorage("codeFont") private var codeFont: String = AppConstants.firaCode
    @AppStorage("showAssistantNameInSidebar") private var showAssistantNameInSidebar: Bool = true
    @AppStorage(SettingsIndicatorKeys.generalSeen) private var generalSettingsSeen: Bool = false
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject private var updateCoordinator = V3UpdateCoordinator.shared
    @State private var selectedColorSchemeRaw: Int = 0
    @State private var codeResult: String = ""

    private var preferredColorScheme: Binding<ColorScheme?> {
        Binding(
            get: {
                switch preferredColorSchemeRaw {
                case 1: return .light
                case 2: return .dark
                default: return nil
                }
            },
            set: { newValue in
                if newValue == nil {
                    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    preferredColorSchemeRaw = isDark ? 2 : 1
                    selectedColorSchemeRaw = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        preferredColorSchemeRaw = 0
                    }
                } else {
                    switch newValue {
                    case .light: preferredColorSchemeRaw = 1
                    case .dark: preferredColorSchemeRaw = 2
                    case .none: preferredColorSchemeRaw = 0
                    case .some(_): preferredColorSchemeRaw = 0
                    }
                    selectedColorSchemeRaw = preferredColorSchemeRaw
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
                        GridRow {
                            HStack {
                                Text("Chat Font Size")
                                Spacer()
                            }
                            .frame(width: 120)
                            .gridCellAnchor(.top)

                            VStack(spacing: 4) {
                                HStack {
                                    Text("A").foregroundColor(.secondary).font(.system(size: 12))
                                    Slider(value: $chatFontSize, in: 10...24, step: 1).frame(width: 200)
                                    Text("A").foregroundColor(.secondary).font(.system(size: 20))
                                }
                                Text("Example \(Int(chatFontSize))pt")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: chatFontSize))
                            }
                            .frame(maxWidth: .infinity)
                        }

                        Divider()

                        GridRow {
                            HStack {
                                Text("Code Font")
                                Spacer()
                            }
                            .frame(width: 120)
                            .gridCellAnchor(.top)

                            VStack(alignment: .leading, spacing: 4) {
                                ScrollView {
                                    if let highlighted = HighlighterManager.shared.highlight(
                                        code: previewCode,
                                        language: "swift",
                                        theme: systemColorScheme == .dark ? "monokai-sublime" : "code-brewer",
                                        fontSize: chatFontSize
                                    ) {
                                        AttributedText(highlighted)
                                    } else {
                                        Text(previewCode).font(.custom(codeFont, size: chatFontSize))
                                    }
                                }
                                Picker("", selection: $codeFont) {
                                    Text("Fira Code").tag(AppConstants.firaCode)
                                    Text("PT Mono").tag(AppConstants.ptMono)
                                }
                                .pickerStyle(.segmented)
                            }
                            .padding(8)
                            .background(systemColorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.96, green: 0.96, blue: 0.96))
                            .cornerRadius(6)
                            .frame(maxWidth: .infinity)
                            .frame(height: 140)
                        }

                        Divider()

                        GridRow {
                            HStack {
                                Text("Theme")
                                Spacer()
                            }
                            .frame(width: 120)
                            .gridCellAnchor(.top)

                            HStack(spacing: 12) {
                                ThemeButton(title: "macOS", isSelected: selectedColorSchemeRaw == 0, mode: .system) {
                                    preferredColorScheme.wrappedValue = nil
                                }
                                ThemeButton(title: "Light", isSelected: selectedColorSchemeRaw == 1, mode: .light) {
                                    preferredColorScheme.wrappedValue = .light
                                }
                                ThemeButton(title: "Dark", isSelected: selectedColorSchemeRaw == 2, mode: .dark) {
                                    preferredColorScheme.wrappedValue = .dark
                                }
                            }
                            .gridColumnAlignment(.trailing)
                            .frame(maxWidth: .infinity)
                        }

                        Divider()

                        GridRow {
                            HStack {
                                Text("Sidebar")
                                Spacer()
                            }
                            .frame(width: 120)
                            .gridCellAnchor(.top)

                            Toggle("Show assistant name", isOn: $showAssistantNameInSidebar)
                                .toggleStyle(.switch)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.intelligence")
                                .foregroundStyle(.purple)
                                .font(.title2)
                            Text("Apple Intelligence")
                                .fontWeight(.medium)
                            Spacer()
                        }
                        Text("All chats run on Apple Intelligence (Foundation Models) on this Mac. Nothing leaves your device unless you explicitly send a chat over Shortcuts.")
                            .foregroundColor(.secondary)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Toggle("Automatically check for updates", isOn: $autoCheckForUpdates)
                    .onChange(of: autoCheckForUpdates) {
                        updateCoordinator.updater.automaticallyChecksForUpdates = autoCheckForUpdates
                    }
                Spacer()
                Button("Check for Updates Now") {
                    updateCoordinator.checkForUpdates()
                }
            }
        }
        .padding()
        .onAppear {
            self.selectedColorSchemeRaw = self.preferredColorSchemeRaw
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                generalSettingsSeen = true
            }
        }
    }
}

/// Local copy of SettingsIndicatorKeys was here — removed; the canonical
/// definition lives in `UI/Preferences/SettingsIndicators.swift`.