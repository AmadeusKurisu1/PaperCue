//
//  LLMClient.swift
//  PaperCue
//
//  Created by Codex on 2026/5/11.
//

import Foundation

protocol LLMClient {
    func generateStudyPack(input: GenerateStudyPackInput) async throws -> GeneratedStudyPackPayload
    func generateStudyPackContextBrief(input: GenerateStudyPackInput) async throws -> String
}

extension LLMClient {
    func generateStudyPackContextBrief(input: GenerateStudyPackInput) async throws -> String {
        ""
    }
}

struct LLMRequestDiagnostic: Equatable {
    var providerHost: String?
    var model: String
    var endpointPath: String
    var statusCode: Int?
    var usedFallback: Bool
}

enum LLMRequestBodyBuilder {
    static func responsesBody(
        configuration: LLMConfiguration,
        systemPrompt: String,
        userPrompt: String,
        studyPackSchema: [String: Any],
        useJSONSchema: Bool,
        schemaName: String = "study_pack"
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": configuration.model,
            "instructions": systemPrompt,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": userPrompt
                        ]
                    ]
                ]
            ],
            "max_output_tokens": configuration.maxOutputTokens
        ]

        body["text"] = [
            "format": useJSONSchema
                ? [
                    "type": "json_schema",
                    "name": schemaName,
                    "strict": true,
                    "schema": studyPackSchema
                ]
                : ["type": "json_object"]
        ]

        return body
    }

    static func chatCompletionsBody(
        configuration: LLMConfiguration,
        systemPrompt: String,
        userPrompt: String,
        useResponseFormat: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": userPrompt
                ]
            ],
            "max_tokens": configuration.maxOutputTokens
        ]

        if useResponseFormat {
            body["response_format"] = ["type": "json_object"]
        }

        return body
    }
}

struct OpenAICompatibleLLMClient: LLMClient {
    var configuration: LLMConfiguration
    var urlSession: URLSession = .shared
    var diagnosticsSink: ((LLMRequestDiagnostic) -> Void)?

    func validateConnection() async throws {
        var request = URLRequest(url: endpoint("models"))
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PaperCueError.unsupportedResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw PaperCueError.serverError(
                statusCode: httpResponse.statusCode,
                message: extractServerMessage(from: data)
            )
        }
    }

    func generateStudyPack(input: GenerateStudyPackInput) async throws -> GeneratedStudyPackPayload {
        guard configuration.prefersResponsesAPI else {
            return try await generateWithChatCompletionsWithFallback(input: input)
        }

        do {
            return try await generateWithResponsesAPI(input: input, useJSONSchema: true)
        } catch {
            guard shouldFallbackFromResponsesAPI(error) else {
                throw error
            }

            do {
                return try await generateWithResponsesAPI(input: input, useJSONSchema: false, usedFallback: true)
            } catch {
                guard shouldFallbackFromResponsesAPI(error) else {
                    throw error
                }

                return try await generateWithChatCompletionsWithFallback(input: input, usedFallback: true)
            }
        }
    }

    func generateStudyPackContextBrief(input: GenerateStudyPackInput) async throws -> String {
        guard configuration.prefersResponsesAPI else {
            return try await generateContextBriefWithChatCompletionsWithFallback(input: input)
        }

        do {
            return try await generateContextBriefWithResponsesAPI(input: input, useJSONSchema: true)
        } catch {
            guard shouldFallbackFromResponsesAPI(error) else {
                throw error
            }

            do {
                return try await generateContextBriefWithResponsesAPI(input: input, useJSONSchema: false, usedFallback: true)
            } catch {
                guard shouldFallbackFromResponsesAPI(error) else {
                    throw error
                }

                return try await generateContextBriefWithChatCompletionsWithFallback(input: input, usedFallback: true)
            }
        }
    }

    private func generateWithResponsesAPI(
        input: GenerateStudyPackInput,
        useJSONSchema: Bool,
        usedFallback: Bool = false
    ) async throws -> GeneratedStudyPackPayload {
        let body = LLMRequestBodyBuilder.responsesBody(
            configuration: configuration,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt(for: input, requireJSONWord: !useJSONSchema),
            studyPackSchema: studyPackSchema,
            useJSONSchema: useJSONSchema
        )

        let data = try await performJSONRequest(
            endpoint: endpoint("responses"),
            endpointPath: "responses",
            body: body,
            usedFallback: usedFallback
        )
        guard let text = extractResponsesText(from: data) else {
            throw PaperCueError.unsupportedResponse
        }
        return try decodePayload(from: text)
    }

    private func generateWithChatCompletionsWithFallback(input: GenerateStudyPackInput, usedFallback: Bool = false) async throws -> GeneratedStudyPackPayload {
        do {
            return try await generateWithChatCompletions(input: input, useResponseFormat: true, usedFallback: usedFallback)
        } catch {
            guard shouldFallbackFromChatResponseFormat(error) else {
                throw error
            }

            return try await generateWithChatCompletions(input: input, useResponseFormat: false, usedFallback: true)
        }
    }

    private func generateWithChatCompletions(
        input: GenerateStudyPackInput,
        useResponseFormat: Bool,
        usedFallback: Bool = false
    ) async throws -> GeneratedStudyPackPayload {
        let body = LLMRequestBodyBuilder.chatCompletionsBody(
            configuration: configuration,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt(for: input, requireJSONWord: true),
            useResponseFormat: useResponseFormat
        )

        let data = try await performJSONRequest(
            endpoint: endpoint("chat/completions"),
            endpointPath: "chat/completions",
            body: body,
            usedFallback: usedFallback
        )
        guard let text = extractChatCompletionsText(from: data) else {
            throw PaperCueError.unsupportedResponse
        }
        return try decodePayload(from: text)
    }

    private func generateContextBriefWithResponsesAPI(
        input: GenerateStudyPackInput,
        useJSONSchema: Bool,
        usedFallback: Bool = false
    ) async throws -> String {
        let body = LLMRequestBodyBuilder.responsesBody(
            configuration: contextBriefConfiguration,
            systemPrompt: contextBriefSystemPrompt,
            userPrompt: contextBriefPrompt(for: input, requireJSONWord: !useJSONSchema),
            studyPackSchema: contextBriefSchema,
            useJSONSchema: useJSONSchema,
            schemaName: "document_context"
        )

        let data = try await performJSONRequest(
            endpoint: endpoint("responses"),
            endpointPath: "responses",
            body: body,
            usedFallback: usedFallback
        )
        guard let text = extractResponsesText(from: data) else {
            throw PaperCueError.unsupportedResponse
        }
        return try decodeContextBrief(from: text)
    }

    private func generateContextBriefWithChatCompletionsWithFallback(input: GenerateStudyPackInput, usedFallback: Bool = false) async throws -> String {
        do {
            return try await generateContextBriefWithChatCompletions(input: input, useResponseFormat: true, usedFallback: usedFallback)
        } catch {
            guard shouldFallbackFromChatResponseFormat(error) else {
                throw error
            }

            return try await generateContextBriefWithChatCompletions(input: input, useResponseFormat: false, usedFallback: true)
        }
    }

    private func generateContextBriefWithChatCompletions(
        input: GenerateStudyPackInput,
        useResponseFormat: Bool,
        usedFallback: Bool = false
    ) async throws -> String {
        let body = LLMRequestBodyBuilder.chatCompletionsBody(
            configuration: contextBriefConfiguration,
            systemPrompt: contextBriefSystemPrompt,
            userPrompt: contextBriefPrompt(for: input, requireJSONWord: true),
            useResponseFormat: useResponseFormat
        )

        let data = try await performJSONRequest(
            endpoint: endpoint("chat/completions"),
            endpointPath: "chat/completions",
            body: body,
            usedFallback: usedFallback
        )
        guard let text = extractChatCompletionsText(from: data) else {
            throw PaperCueError.unsupportedResponse
        }
        return try decodeContextBrief(from: text)
    }

    private func performJSONRequest(endpoint: URL, endpointPath: String, body: [String: Any], usedFallback: Bool) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.generationTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw PaperCueError.requestTimedOut(seconds: Int(configuration.generationTimeoutSeconds))
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw PaperCueError.networkUnavailable(message: error.localizedDescription)
            default:
                throw error
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PaperCueError.unsupportedResponse
        }

        diagnosticsSink?(
            LLMRequestDiagnostic(
                providerHost: configuration.baseURL.host,
                model: configuration.model,
                endpointPath: endpointPath,
                statusCode: httpResponse.statusCode,
                usedFallback: usedFallback
            )
        )

        guard (200...299).contains(httpResponse.statusCode) else {
            throw PaperCueError.serverError(
                statusCode: httpResponse.statusCode,
                message: extractServerMessage(from: data)
            )
        }

        return data
    }

    private func endpoint(_ path: String) -> URL {
        var url = configuration.baseURL
        let trimmedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if trimmedPath.isEmpty && url.host?.lowercased() == "api.openai.com" {
            url.appendPathComponent("v1")
        }

        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }

        return url
    }

    private func shouldFallbackFromResponsesAPI(_ error: Error) -> Bool {
        guard let paperCueError = error as? PaperCueError else {
            return false
        }

        switch paperCueError {
        case .serverError(let statusCode, _):
            return [400, 404, 405, 422].contains(statusCode)
        case .unsupportedResponse:
            return true
        default:
            return false
        }
    }

    private func shouldFallbackFromChatResponseFormat(_ error: Error) -> Bool {
        guard let paperCueError = error as? PaperCueError,
              case let .serverError(statusCode, message) = paperCueError else {
            return false
        }

        let normalizedMessage = message.lowercased()
        return [400, 422].contains(statusCode)
            && (normalizedMessage.contains("response_format")
                || normalizedMessage.contains("json_object")
                || normalizedMessage.contains("json schema"))
    }

    private var contextBriefConfiguration: LLMConfiguration {
        var briefConfiguration = configuration
        briefConfiguration.maxOutputTokens = min(configuration.maxOutputTokens, 1_200)
        return briefConfiguration
    }

    private var systemPrompt: String {
        """
        你是 PaperCue 的学术阅读助手。请只根据用户提供的文本生成学习材料，不编造文中没有的信息。输出必须是 JSON，字段必须与 schema 完全一致。默认使用中文；专业术语保留英文原词，并给出中文解释。卡片要适合导入 Anki，正面是可主动回忆的问题，背面是简洁答案。
        """
    }

    private var contextBriefSystemPrompt: String {
        """
        你是 PaperCue 的学术阅读助手。请为后续分片生成提取简短的全文上下文，只根据用户提供的文本，不补充外部知识。输出必须是 JSON。
        """
    }

    private func contextBriefPrompt(for input: GenerateStudyPackInput, requireJSONWord: Bool) -> String {
        let clippedText = contextBriefSourceText(from: input.text)
        let jsonInstruction = requireJSONWord
            ? "请只返回 JSON 对象，不要输出 Markdown、代码块或额外说明。"
            : "请严格遵守结构化输出 schema，不要输出额外说明。"

        return """
        标题：\(input.title)
        来源类型：\(input.sourceKind.title)
        来源地址：\(input.sourceURL?.absoluteString ?? "无")
        输出语言：\(input.outputLanguage)

        任务：生成一个用于后续分片处理的全局上下文 brief，帮助理解术语、缩写、研究对象、方法、章节主线和跨段指代。
        要求：
        - 5 到 8 条，合计尽量不超过 900 个中文字符。
        - 只写文中可见的信息；看不清或原文未给出的内容不要猜。
        - 如果原文选段包含摘要、引言、结论或章节标题，优先保留这些线索。
        - brief 只用于辅助后续分片理解；不要生成摘要卡片、术语表或复习题。
        \(jsonInstruction)

        输出 JSON 的英文 key 必须使用以下结构：
        {
          "contextBrief": "string"
        }

        原文选段：
        \(clippedText)
        """
    }

    private func contextBriefSourceText(from text: String) -> String {
        let normalized = normalizeText(text)
        guard normalized.count > 42_000 else {
            return normalized
        }

        let opening = String(normalized.prefix(28_000))
        let ending = String(normalized.suffix(12_000))
        return """
        \(opening)

        [...中间内容省略以控制请求长度...]

        \(ending)
        """
    }

    private func userPrompt(for input: GenerateStudyPackInput, requireJSONWord: Bool) -> String {
        let clippedText = String(input.text.prefix(42_000))
        let jsonInstruction = requireJSONWord
            ? "请只返回 JSON 对象，不要输出 Markdown、代码块或额外说明。"
            : "请严格遵守结构化输出 schema，不要输出额外说明。"
        let profileInstruction = """
        生成模式：\(input.generationProfile.title)
        模式要求：\(input.generationProfile.promptInstruction)
        """
        let moduleInstruction = generationModuleInstruction(for: input.options)
        let customPrompt = input.options.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let customPromptInstruction = customPrompt.isEmpty
            ? ""
            : "\n用户自定义要求：\n\(customPrompt)\n"
        let taskInstruction = input.taskInstruction.map { "\n任务说明：\($0)\n" } ?? ""

        return """
        标题：\(input.title)
        来源类型：\(input.sourceKind.title)
        来源地址：\(input.sourceURL?.absoluteString ?? "无")
        输出语言：\(input.outputLanguage)
        \(profileInstruction)
        \(moduleInstruction)
        \(customPromptInstruction)
        \(taskInstruction)

        来源回溯要求：如果原文包含 [Page n] 页码标记，请在术语 context、卡片 sourceQuote、问题 relatedSection 中尽量保留对应页码和短引文；如果没有页码，请使用原文中的章节名、段落关键词或短引文，不要编造页码。
        \(jsonInstruction)
        \(jsonOutputContract)

        原文：
        \(clippedText)
        """
    }

    private func generationModuleInstruction(for options: StudyPackGenerationOptions) -> String {
        let enabled = options.orderedEnabledModules
        let disabled = StudyPackModule.allCases.filter { !options.includes($0) }
        let enabledLines = enabled.map { module in
            switch module {
            case .summary:
                "- 摘要：一句话概括、关键点、方法或论证、局限。"
            case .glossary:
                "- 术语表：优先提取对理解全文有帮助的概念。"
            case .flashcards:
                "- Anki 卡片：8 到 16 张，避免只问定义，优先覆盖机制、比较、证据和结论。"
            case .questions:
                "- 提问清单：用于课堂讨论、组会或精读复盘。"
            }
        }
        let disabledLine = disabled.isEmpty
            ? ""
            : "\n未选择模块：\(disabled.map(\.title).joined(separator: "、"))。这些模块必须返回空字段或空数组，不要生成内容。"

        return """
        已选择生成模块：
        \(enabledLines.joined(separator: "\n"))\(disabledLine)
        """
    }

    private var jsonOutputContract: String {
        """
        输出 JSON 的英文 key 必须使用以下结构，字符串内容可以使用中文：
        {
          "summary": {
            "oneSentence": "string",
            "keyPoints": ["string"],
            "methodOrArgument": "string",
            "limitations": "string"
          },
          "glossary": [
            {
              "term": "string",
              "originalTerm": "string",
              "explanation": "string",
              "context": "string"
            }
          ],
          "flashcards": [
            {
              "front": "string",
              "back": "string",
              "tags": ["string"],
              "sourceQuote": "string"
            }
          ],
          "questions": [
            {
              "question": "string",
              "purpose": "string",
              "relatedSection": "string"
            }
          ]
        }
        未选择的模块仍然要保留顶层字段：summary 使用空字符串和空 keyPoints，glossary/flashcards/questions 使用空数组。如果原文没有可引用短句，sourceQuote 使用空字符串；不要省略任何顶层字段。
        """
    }

    private var contextBriefSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "contextBrief": ["type": "string"]
            ],
            "required": ["contextBrief"],
            "additionalProperties": false
        ]
    }

    private var studyPackSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "summary": [
                    "type": "object",
                    "properties": [
                        "oneSentence": ["type": "string"],
                        "keyPoints": [
                            "type": "array",
                            "items": ["type": "string"]
                        ],
                        "methodOrArgument": ["type": "string"],
                        "limitations": ["type": "string"]
                    ],
                    "required": ["oneSentence", "keyPoints", "methodOrArgument", "limitations"],
                    "additionalProperties": false
                ],
                "glossary": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "term": ["type": "string"],
                            "originalTerm": ["type": "string"],
                            "explanation": ["type": "string"],
                            "context": ["type": "string"]
                        ],
                        "required": ["term", "originalTerm", "explanation", "context"],
                        "additionalProperties": false
                    ]
                ],
                "flashcards": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "front": ["type": "string"],
                            "back": ["type": "string"],
                            "tags": [
                                "type": "array",
                                "items": ["type": "string"]
                            ],
                            "sourceQuote": ["type": "string"]
                        ],
                        "required": ["front", "back", "tags", "sourceQuote"],
                        "additionalProperties": false
                    ]
                ],
                "questions": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "question": ["type": "string"],
                            "purpose": ["type": "string"],
                            "relatedSection": ["type": "string"]
                        ],
                        "required": ["question", "purpose", "relatedSection"],
                        "additionalProperties": false
                    ]
                ]
            ],
            "required": ["summary", "glossary", "flashcards", "questions"],
            "additionalProperties": false
        ]
    }
}

func decodePayload(from text: String) throws -> GeneratedStudyPackPayload {
    let trimmed = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"^```json\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: #"^```\s*"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)

    guard let firstBrace = trimmed.firstIndex(of: "{"),
          let lastBrace = trimmed.lastIndex(of: "}") else {
        throw PaperCueError.invalidGeneratedPayload(message: "模型没有返回 JSON 对象。")
    }

    let jsonText = String(trimmed[firstBrace...lastBrace])
    guard let data = jsonText.data(using: .utf8) else {
        throw PaperCueError.invalidGeneratedPayload(message: "JSON 文本无法编码。")
    }

    do {
        return try JSONDecoder().decode(GeneratedStudyPackPayload.self, from: data)
    } catch {
        throw PaperCueError.invalidGeneratedPayload(message: "JSON 字段缺失或类型不正确。")
    }
}

private struct ContextBriefResponse: Decodable {
    var contextBrief: String
}

private func decodeContextBrief(from text: String) throws -> String {
    let trimmed = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"^```json\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: #"^```\s*"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)

    guard let firstBrace = trimmed.firstIndex(of: "{"),
          let lastBrace = trimmed.lastIndex(of: "}") else {
        throw PaperCueError.invalidGeneratedPayload(message: "模型没有返回全局上下文 JSON。")
    }

    let jsonText = String(trimmed[firstBrace...lastBrace])
    guard let data = jsonText.data(using: .utf8) else {
        throw PaperCueError.invalidGeneratedPayload(message: "全局上下文 JSON 无法编码。")
    }

    do {
        let response = try JSONDecoder().decode(ContextBriefResponse.self, from: data)
        let brief = response.contextBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty else {
            throw PaperCueError.invalidGeneratedPayload(message: "全局上下文为空。")
        }
        return brief
    } catch let error as PaperCueError {
        throw error
    } catch {
        throw PaperCueError.invalidGeneratedPayload(message: "全局上下文 JSON 字段缺失或类型不正确。")
    }
}

private func extractResponsesText(from data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    if let outputText = object["output_text"] as? String,
       !outputText.isEmpty {
        return outputText
    }

    guard let output = object["output"] as? [[String: Any]] else {
        return nil
    }

    var fragments: [String] = []
    for item in output {
        guard let content = item["content"] as? [[String: Any]] else {
            continue
        }

        for contentItem in content {
            if let text = contentItem["text"] as? String {
                fragments.append(text)
            } else if let text = contentItem["content"] as? String {
                fragments.append(text)
            }
        }
    }

    return fragments.isEmpty ? nil : fragments.joined(separator: "\n")
}

private func extractChatCompletionsText(from data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = object["choices"] as? [[String: Any]],
          let first = choices.first,
          let message = first["message"] as? [String: Any] else {
        return nil
    }

    if let content = message["content"] as? String,
       !content.isEmpty {
        return content
    }

    guard let content = message["content"] as? [[String: Any]] else {
        return nil
    }

    let fragments = content.compactMap { item in
        item["text"] as? String ?? item["content"] as? String
    }

    return fragments.isEmpty ? nil : fragments.joined(separator: "\n")
}

private func extractServerMessage(from data: Data) -> String {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    if let error = object["error"] as? [String: Any],
       let message = error["message"] as? String {
        return message
    }

    if let message = object["message"] as? String {
        return message
    }

    return String(data: data, encoding: .utf8) ?? "Unknown error"
}
