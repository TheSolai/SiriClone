//
//  TabToolsView.swift
//  SiriClone
//
//  Tools settings: enable/disable each Foundation Models Tool that the
//  on-device model can invoke, manage the path allowlist for file tools,
//  and toggle shell-command confirmation.
//

import SwiftUI

struct TabToolsView: View {

    @AppStorage("tool.shell.enabled") private var shellEnabled: Bool = false
    @AppStorage("tool.path.allowlist") private var pathAllowlist: String = ""

    private var registry: ToolRegistry { ToolRegistry.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tools available to the model")
                        .font(.headline)
                    Text("Apple Intelligence can invoke these Tools while chatting. Disable anything you don't want it to use.")
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
                    Text("Path allowlist")
                        .font(.headline)
                    Text("File tools can always read and write inside ~/Documents, ~/Desktop, ~/Downloads, and iCloud Drive. Add more absolute paths (one per line) if you want the model to access other folders.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: $pathAllowlist)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 80, maxHeight: 140)
                        .border(Color.gray.opacity(0.25))
                }
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $shellEnabled) {
                        VStack(alignment: .leading) {
                            Text("Allow the model to run shell commands")
                            Text("Off by default. Even when on, every command prompts you before it runs.")
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

extension ToolRegistry.Category {
    var categoryLabel: String {
        switch self {
        case .filesystem: return "Files"
        case .shell: return "Shell"
        case .export: return "Export"
        }
    }
}