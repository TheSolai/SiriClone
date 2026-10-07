//
//  TabModelsView.swift
//  SiriClone
//
//  Model provider settings. Pick between Apple Intelligence (on-device)
//  and a local OpenAI-compatible backend (Ollama, llama.cpp, vLLM, …).
//  For the local backend, configure the base URL, model name, and
//  optional API key. Defaults assume Ollama at localhost:11434 with
//  qwen2.5-coder:7b.
//

import SwiftUI

struct TabModelsView: View {

    @AppStorage("ai.provider") private var providerID: String = AIProviderID.appleIntelligence.rawValue

    // Local LLM fields
    @AppStorage("ai.local.base_url") private var baseURL: String = "http://localhost:11434/v1/chat/completions"
    @AppStorage("ai.local.model") private var modelName: String = "qwen2.5-coder:7b"
    @AppStorage("ai.local.api_key") private var apiKey: String = ""

    @State private var connectionStatus: String? = nil
    @State private var testing = false

    private var selectedProvider: AIProviderID {
        AIProviderID(rawValue: providerID) ?? .appleIntelligence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .foregroundStyle(.blue)
                            .font(.title2)
                        Text("Model provider")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    Text("SiriClone can use Apple's on-device Foundation Models, or any local server that speaks the OpenAI /v1/chat/completions API (Ollama, llama.cpp, vLLM, LM Studio).")
                        .foregroundColor(.secondary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("Provider", selection: $providerID) {
                        ForEach(AIProviderID.allCases) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
                .padding(8)
            }

            if selectedProvider == .appleIntelligence {
                appleIntelligenceBox
            } else {
                localLLMBox
            }
        }
        .padding()
    }

    private var appleIntelligenceBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(.green)
                    Text("Apple Intelligence")
                        .fontWeight(.semibold)
                }
                Text("Runs entirely on this Mac using the Apple Foundation Models framework. No network calls. Tools still work — file, shell, AppleScript, system, clipboard, etc.")
                    .foregroundColor(.secondary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text("If long code drops or truncates, switch to the Local LLM backend below — Ollama with qwen2.5-coder is more reliable for code generation.")
                    .foregroundColor(.secondary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
        }
    }

    private var localLLMBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.orange)
                    Text("Local OpenAI-compatible backend")
                        .fontWeight(.semibold)
                }
                Text("Configure your local server's chat-completions URL, the model to serve, and an optional API key (Ollama ignores keys; llama.cpp / vLLM / LM Studio accept anything).")
                    .foregroundColor(.secondary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField(
                        "http://localhost:11434/v1/chat/completions",
                        text: $baseURL
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Model name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField(
                        "qwen2.5-coder:7b",
                        text: $modelName
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("API key (optional)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    SecureField("leave blank for Ollama", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }

                HStack {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if testing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Test connection")
                        }
                    }
                    .disabled(testing)

                    if let status = connectionStatus {
                        Text(status)
                            .foregroundColor(status.hasPrefix("✓") ? .green : .red)
                            .font(.callout)
                    }
                    Spacer()
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quick-start with Ollama")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Ollama already runs on this Mac at the default URL above. Recommended for reliable code generation:")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Text("• qwen2.5-coder:7b — small, fast, good code")
                            .font(.system(size: 12, design: .monospaced))
                        Text("• qwen2.5-coder:14b — larger, more reliable")
                            .font(.system(size: 12, design: .monospaced))
                        Text("• qwen3:14b — good reasoning, larger")
                            .font(.system(size: 12, design: .monospaced))
                        Text("Pull with: ollama pull qwen2.5-coder:7b")
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.top, 4)
                    }
                    .padding(8)
                }
                .background(Color.secondary.opacity(0.05))
            }
            .padding(8)
        }
    }

    private func testConnection() async {
        testing = true
        connectionStatus = nil
        defer { testing = false }

        guard let url = URL(string: baseURL) else {
            connectionStatus = "✗ Invalid URL"
            return
        }

        // Hit a minimal request — just list models.
        let modelsURL = URL(string: "/v1/models", relativeTo: url.deletingLastPathComponent()) ?? url
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                connectionStatus = "✗ Bad response"
                return
            }
            if (200..<300).contains(http.statusCode) {
                connectionStatus = "✓ Server reachable (\(http.statusCode))"
            } else {
                connectionStatus = "✗ Server returned \(http.statusCode)"
            }
        } catch {
            connectionStatus = "✗ \(error.localizedDescription)"
        }
    }
}