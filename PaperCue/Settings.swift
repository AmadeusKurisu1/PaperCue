//
//  Settings.swift
//  PaperCue
//
//  Created by Codex on 2026/5/11.
//

import Combine
import Foundation
import Security

struct LLMModelPreset: Identifiable, Hashable {
    static let customID = "__custom_model__"

    var id: String
    var title: String
}

enum LLMProviderPreset: String, CaseIterable, Identifiable, Hashable {
    case openAI
    case deepSeek
    case kimi
    case dashScope
    case siliconFlow
    case zhipu
    case gemini
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .deepSeek:
            "DeepSeek"
        case .kimi:
            "Kimi / Moonshot"
        case .dashScope:
            "阿里云百炼 DashScope"
        case .siliconFlow:
            "硅基流动 SiliconFlow"
        case .zhipu:
            "智谱 BigModel"
        case .gemini:
            "Google Gemini"
        case .custom:
            "自定义 OpenAI-compatible"
        }
    }

    var baseURLString: String {
        switch self {
        case .openAI:
            "https://api.openai.com/v1"
        case .deepSeek:
            "https://api.deepseek.com"
        case .kimi:
            "https://api.moonshot.cn/v1"
        case .dashScope:
            "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .siliconFlow:
            "https://api.siliconflow.cn/v1"
        case .zhipu:
            "https://open.bigmodel.cn/api/paas/v4"
        case .gemini:
            "https://generativelanguage.googleapis.com/v1beta/openai"
        case .custom:
            ""
        }
    }

    var defaultModel: String {
        modelPresets.first?.id ?? "gpt-5.4-mini"
    }

    var modelPresets: [LLMModelPreset] {
        switch self {
        case .openAI:
            [
                LLMModelPreset(id: "gpt-5.4-mini", title: "GPT-5.4 mini（均衡）"),
                LLMModelPreset(id: "gpt-5.5", title: "GPT-5.5（旗舰）"),
                LLMModelPreset(id: "gpt-5.4", title: "GPT-5.4（专业）"),
                LLMModelPreset(id: "gpt-5.4-nano", title: "GPT-5.4 nano（低成本）"),
                LLMModelPreset(id: "gpt-5.2", title: "GPT-5.2（旧版）")
            ]
        case .deepSeek:
            [
                LLMModelPreset(id: "deepseek-v4-flash", title: "DeepSeek V4 Flash"),
                LLMModelPreset(id: "deepseek-v4-pro", title: "DeepSeek V4 Pro"),
                LLMModelPreset(id: "deepseek-chat", title: "deepseek-chat（兼容旧名）"),
                LLMModelPreset(id: "deepseek-reasoner", title: "deepseek-reasoner（兼容旧名）")
            ]
        case .kimi:
            [
                LLMModelPreset(id: "kimi-k2.6", title: "Kimi K2.6"),
                LLMModelPreset(id: "kimi-k2.5", title: "Kimi K2.5"),
                LLMModelPreset(id: "kimi-k2-0905-preview", title: "Kimi K2 0905 Preview"),
                LLMModelPreset(id: "kimi-k2-0711-preview", title: "Kimi K2 0711 Preview"),
                LLMModelPreset(id: "kimi-k2-thinking", title: "Kimi K2 Thinking"),
                LLMModelPreset(id: "kimi-k2-thinking-turbo", title: "Kimi K2 Thinking Turbo"),
                LLMModelPreset(id: "kimi-k2-turbo-preview", title: "Kimi K2 Turbo Preview"),
                LLMModelPreset(id: "moonshot-v1-32k", title: "Moonshot v1 32k")
            ]
        case .dashScope:
            [
                LLMModelPreset(id: "qwen3.6-plus", title: "Qwen3.6 Plus"),
                LLMModelPreset(id: "qwen3.6-max-preview", title: "Qwen3.6 Max Preview"),
                LLMModelPreset(id: "qwen3.6-flash", title: "Qwen3.6 Flash"),
                LLMModelPreset(id: "qwen3.5-plus", title: "Qwen3.5 Plus"),
                LLMModelPreset(id: "qwen3.5-flash", title: "Qwen3.5 Flash"),
                LLMModelPreset(id: "qwen3-coder-next", title: "Qwen3 Coder Next")
            ]
        case .siliconFlow:
            [
                LLMModelPreset(id: "deepseek-ai/DeepSeek-V3", title: "DeepSeek V3"),
                LLMModelPreset(id: "Pro/deepseek-ai/DeepSeek-V3", title: "DeepSeek V3 Pro"),
                LLMModelPreset(id: "deepseek-ai/DeepSeek-R1", title: "DeepSeek R1"),
                LLMModelPreset(id: "Pro/deepseek-ai/DeepSeek-R1", title: "DeepSeek R1 Pro"),
                LLMModelPreset(id: "Qwen/Qwen2.5-Coder-32B-Instruct", title: "Qwen2.5 Coder 32B")
            ]
        case .zhipu:
            [
                LLMModelPreset(id: "glm-5.1", title: "GLM-5.1"),
                LLMModelPreset(id: "glm-5", title: "GLM-5"),
                LLMModelPreset(id: "glm-4.7", title: "GLM-4.7"),
                LLMModelPreset(id: "glm-4.6", title: "GLM-4.6")
            ]
        case .gemini:
            [
                LLMModelPreset(id: "gemini-2.5-flash", title: "Gemini 2.5 Flash"),
                LLMModelPreset(id: "gemini-2.5-pro", title: "Gemini 2.5 Pro"),
                LLMModelPreset(id: "gemini-2.5-flash-lite", title: "Gemini 2.5 Flash-Lite")
            ]
        case .custom:
            []
        }
    }

    var isCustom: Bool {
        self == .custom
    }

    var prefersResponsesAPI: Bool {
        self == .openAI
    }

    static func matching(baseURLString: String) -> LLMProviderPreset? {
        let normalized = normalize(baseURLString)
        return allCases.first { provider in
            guard !provider.isCustom else { return false }
            return provider.matchableBaseURLs.map(normalize).contains(normalized)
        }
    }

    private var matchableBaseURLs: [String] {
        switch self {
        case .openAI:
            [baseURLString, "https://api.openai.com"]
        case .deepSeek:
            [baseURLString, "https://api.deepseek.com/v1"]
        case .gemini:
            [baseURLString, "https://generativelanguage.googleapis.com/v1beta/openai/"]
        default:
            [baseURLString]
        }
    }

    private nonisolated static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}

struct LLMConfiguration: Equatable {
    var baseURL: URL
    var apiKey: String
    var model: String
    var maxOutputTokens: Int
    var prefersResponsesAPI: Bool
    var generationTimeoutSeconds: TimeInterval
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var providerID: String {
        didSet { UserDefaults.standard.set(providerID, forKey: Self.providerKey) }
    }

    @Published var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Self.baseURLKey) }
    }

    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Self.modelKey) }
    }

    @Published var modelPresetID: String {
        didSet { UserDefaults.standard.set(modelPresetID, forKey: Self.modelPresetKey) }
    }

    @Published var maxOutputTokens: Int {
        didSet { UserDefaults.standard.set(maxOutputTokens, forKey: Self.maxOutputTokensKey) }
    }

    @Published var apiKey: String {
        didSet {
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                KeychainStorage.shared.delete(key: Self.apiKeyKey)
            } else {
                try? KeychainStorage.shared.save(apiKey, key: Self.apiKeyKey)
            }
        }
    }

    private static let providerKey = "llmProvider"
    private static let baseURLKey = "llmBaseURL"
    private static let modelKey = "llmModel"
    private static let modelPresetKey = "llmModelPreset"
    private static let maxOutputTokensKey = "llmMaxOutputTokens"
    private static let apiKeyKey = "llmAPIKey"

    init() {
        let storedBaseURLString = UserDefaults.standard.string(forKey: Self.baseURLKey) ?? LLMProviderPreset.openAI.baseURLString
        let storedModel = UserDefaults.standard.string(forKey: Self.modelKey)
        baseURLString = storedBaseURLString

        let resolvedProvider: LLMProviderPreset
        if let storedProviderID = UserDefaults.standard.string(forKey: Self.providerKey),
           let storedProvider = LLMProviderPreset(rawValue: storedProviderID) {
            resolvedProvider = storedProvider
        } else {
            resolvedProvider = LLMProviderPreset.matching(baseURLString: storedBaseURLString) ?? .custom
        }

        let resolvedModel = storedModel ?? resolvedProvider.defaultModel
        providerID = resolvedProvider.rawValue
        model = resolvedModel

        if let storedModelPresetID = UserDefaults.standard.string(forKey: Self.modelPresetKey),
           storedModelPresetID == LLMModelPreset.customID || resolvedProvider.modelPresets.contains(where: { $0.id == storedModelPresetID }) {
            modelPresetID = storedModelPresetID
        } else if resolvedProvider.modelPresets.contains(where: { $0.id == resolvedModel }) {
            modelPresetID = resolvedModel
        } else {
            modelPresetID = LLMModelPreset.customID
        }

        let storedMaxTokens = UserDefaults.standard.integer(forKey: Self.maxOutputTokensKey)
        maxOutputTokens = storedMaxTokens == 0 ? 3500 : storedMaxTokens
        apiKey = KeychainStorage.shared.read(key: Self.apiKeyKey) ?? ""
    }

    var selectedProvider: LLMProviderPreset {
        LLMProviderPreset(rawValue: providerID) ?? .custom
    }

    var selectedModelPresetID: String {
        if modelPresetID == LLMModelPreset.customID || selectedProvider.modelPresets.isEmpty {
            return LLMModelPreset.customID
        }

        guard selectedProvider.modelPresets.contains(where: { $0.id == modelPresetID }) else {
            return selectedProvider.modelPresets.contains(where: { $0.id == model }) ? model : LLMModelPreset.customID
        }

        return modelPresetID
    }

    func selectProvider(_ provider: LLMProviderPreset) {
        providerID = provider.rawValue

        guard !provider.isCustom else {
            return
        }

        baseURLString = provider.baseURLString
        model = provider.defaultModel
        modelPresetID = provider.defaultModel
    }

    func selectModelPreset(id: String) {
        modelPresetID = id

        guard id != LLMModelPreset.customID else {
            return
        }

        model = id
    }

    func llmConfiguration() throws -> LLMConfiguration {
        guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              baseURL.scheme != nil,
              baseURL.host != nil else {
            throw PaperCueError.invalidBaseURL
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw PaperCueError.missingAPIKey
        }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return LLMConfiguration(
            baseURL: baseURL,
            apiKey: trimmedKey,
            model: trimmedModel.isEmpty ? selectedProvider.defaultModel : trimmedModel,
            maxOutputTokens: max(800, maxOutputTokens),
            prefersResponsesAPI: selectedProvider.prefersResponsesAPI || baseURL.host?.lowercased() == "api.openai.com",
            generationTimeoutSeconds: 240
        )
    }
}

final class KeychainStorage {
    static let shared = KeychainStorage()

    private let service = "cloud.hfutsh.PaperCue"

    private init() {}

    func save(_ value: String, key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
            throw PaperCueError.exportFailed
        }
    }

    func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
