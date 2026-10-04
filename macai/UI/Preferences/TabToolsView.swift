//
//  TabToolsView.swift
//  SiriClone
//
//  Tools settings: every Foundation Models Tool defaults to ON (full
//  admin). Disable per-tool here. Restrict file paths to a custom
//  allowlist, disable shell, etc.
//

import SwiftUI

struct TabToolsView: View {

    @AppStorage("tool.path.restrict") private var restrictPaths: Bool = false
    @AppStorage("tool.path.allowlist") private var pathAllowlist: String = ""
    @AppStorage("tool.shell.enabled") private var shellEnabled: Bool = true
    @AppStorage("tool.applescript.enabled") private var applescriptEnabled: Bool = true

    private var registry: ToolRegistry { ToolRegistry.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.shield")
                            .foregroundStyle(.purple)
                            .font(.title2)
                        Text("Full system admin")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("All tools ON by default")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    }
                    Text("SiriClone runs unsandboxed. Every tool here defaults to enabled so the model can do anything you can do. Toggle off anything you want restricted.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tools")
                        .font(.headline)
                    Text("Disable a tool to remove it from the available actions. The model won't see disabled tools and won't be able to invoke them.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(ToolRegistry.Category.allCases, id: \.self) { category in
                        let defs = registry.all.filter { $0.category == category }
                        if !defs.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(category.categoryLabel)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.top, 4)
                                ForEach(defs, id: \.id) { def in
                                    toolRow(def)
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $restrictPaths) {
                        VStack(alignment: .leading) {
                            Text("Restrict file tools to a path allowlist")
                            Text("When OFF (default), file tools can read and write anywhere on this Mac. When ON, only ~/Documents, ~/Desktop, ~/Downloads, iCloud Drive, and your custom paths below are allowed.")
                                .foregroundColor(.secondary)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 4)

                    if restrictPaths {
                        Text("Custom allowed paths (one per line, absolute or starting with ~):")
                            .foregroundColor(.secondary)
                            .font(.callout)
                        TextEditor(text: $pathAllowlist)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 80, maxHeight: 140)
                            .border(Color.gray.opacity(0.25))
                    }
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $shellEnabled) {
                        VStack(alignment: .leading) {
                            Text("Allow the model to run shell commands")
                            Text("On by default. When off, run_shell returns 'disabled' and the model can't execute arbitrary commands.")
                                .foregroundColor(.secondary)
                                .font(.callout)
                        }
                    }
                    .toggleStyle(.switch)

                    Toggle(isOn: $applescriptEnabled) {
                        VStack(alignment: .leading) {
                            Text("Allow the model to run AppleScript")
                            Text("On by default. AppleScript can drive any scriptable Mac app — Mail, Messages, Finder, Calendar, Music, Safari.")
                                .foregroundColor(.secondary)
                                .font(.callout)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding(8)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func toolRow(_ def: ToolRegistry.Definition) -> some View {
        let binding = Binding<Bool>(
            get: { registry.isEnabled(def.id) },
            set: { registry.setEnabled($0, for: def.id) }
        )
        HStack(alignment: .top, spacing: 8) {
            Toggle(isOn: binding) { EmptyView() }
                .toggleStyle(.switch)
                .labelsHidden()
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(def.name)
                    .font(.system(size: 13, design: .monospaced))
                    .fontWeight(.medium)
                Text(def.description)
                    .foregroundColor(.secondary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}