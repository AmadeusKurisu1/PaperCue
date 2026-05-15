//
//  SettingsView.swift
//  PaperCue
//
//  Created by Codex on 2026/5/11.
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    @State private var isTestingConnection = false
    @State private var connectionMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("接口厂商", selection: providerSelection) {
                        ForEach(LLMProviderPreset.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("providerPicker")

                    TextField("Base URL", text: $settings.baseURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(!settings.selectedProvider.isCustom)
                        .accessibilityIdentifier("baseURLTextField")

                    HStack {
                        SecureField("API Key", text: $settings.apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("apiKeySecureField")

                        Button {
                            pasteAPIKey()
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("粘贴 API Key")
                        .accessibilityIdentifier("pasteAPIKeyButton")
                    }

                    Picker("模型", selection: modelSelection) {
                        ForEach(settings.selectedProvider.modelPresets) { modelPreset in
                            Text(modelPreset.title).tag(modelPreset.id)
                        }
                        Text("自定义模型").tag(LLMModelPreset.customID)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("modelPicker")

                    TextField("Model", text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(settings.selectedModelPresetID != LLMModelPreset.customID)
                        .accessibilityIdentifier("modelTextField")

                    Stepper("最大输出 tokens：\(settings.maxOutputTokens)", value: $settings.maxOutputTokens, in: 800...12000, step: 100)
                } header: {
                    Text("模型服务")
                } footer: {
                    Text(settings.selectedProvider.isCustom ? "自定义接口需要兼容 OpenAI Chat Completions，Base URL 和模型名都可手动填写。" : "选择厂商后会自动使用该厂商的 OpenAI-compatible API 根地址，并提供常用模型选项；未列出的模型可选“自定义模型”。")
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        Label(isTestingConnection ? "测试中" : "测试连接", systemImage: "network")
                    }
                    .disabled(isTestingConnection)
                    .accessibilityIdentifier("testConnectionButton")

                    if let connectionMessage {
                        Text(connectionMessage)
                            .font(.footnote)
                            .foregroundStyle(connectionMessage == "连接可用" ? .green : .red)
                    }
                } footer: {
                    Text("API key 只保存在本机 Keychain。PaperCue 不提供默认密钥，生成时会把提取文本直接发送到你配置的模型服务，费用和额度由你的账号承担。")
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var providerSelection: Binding<LLMProviderPreset> {
        Binding(
            get: { settings.selectedProvider },
            set: { settings.selectProvider($0) }
        )
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { settings.selectedModelPresetID },
            set: { settings.selectModelPreset(id: $0) }
        )
    }

    private func testConnection() {
        Task {
            isTestingConnection = true
            defer { isTestingConnection = false }

            do {
                let configuration = try settings.llmConfiguration()
                try await OpenAICompatibleLLMClient(configuration: configuration).validateConnection()
                connectionMessage = "连接可用"
            } catch {
                connectionMessage = error.paperCueMessage
            }
        }
    }

    private func pasteAPIKey() {
        guard let value = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return
        }

        settings.apiKey = value
    }
}
