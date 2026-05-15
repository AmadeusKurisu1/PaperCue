//
//  StudyPackGenerationService.swift
//  PaperCue
//
//  Created by Codex on 2026/5/11.
//

import Foundation

struct TextChunk: Equatable, Identifiable {
    var id: Int { index }
    var index: Int
    var text: String
    var startOffset: Int
    var endOffset: Int
}

struct TextChunker {
    var longDocumentThreshold = 42_000
    var maxChunkLength = 18_000
    var overlapLength = 800

    func chunk(text: String) -> [TextChunk] {
        let normalized = normalizeText(text)
        guard normalized.count > longDocumentThreshold else {
            return [
                TextChunk(
                    index: 0,
                    text: normalized,
                    startOffset: 0,
                    endOffset: normalized.count
                )
            ]
        }

        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var rawChunks: [String] = []
        var current = ""

        for paragraph in paragraphs {
            if paragraph.count > maxChunkLength {
                if !current.isEmpty {
                    rawChunks.append(current)
                    current = ""
                }
                rawChunks.append(contentsOf: splitLongParagraph(paragraph))
                continue
            }

            let separator = current.isEmpty ? "" : "\n\n"
            if current.count + separator.count + paragraph.count <= maxChunkLength {
                current += separator + paragraph
            } else {
                if !current.isEmpty {
                    rawChunks.append(current)
                }

                let overlap = overlapSuffix(from: rawChunks.last ?? "")
                if !overlap.isEmpty && overlap.count + 2 + paragraph.count <= maxChunkLength {
                    current = overlap + "\n\n" + paragraph
                } else {
                    current = paragraph
                }
            }
        }

        if !current.isEmpty {
            rawChunks.append(current)
        }

        var approximateStart = 0
        return rawChunks.enumerated().map { index, text in
            let start = max(0, approximateStart)
            let end = start + text.count
            approximateStart = max(0, end - overlapLength)
            return TextChunk(index: index, text: text, startOffset: start, endOffset: end)
        }
    }

    private func splitLongParagraph(_ paragraph: String) -> [String] {
        var chunks: [String] = []
        var start = paragraph.startIndex
        let stepBack = min(overlapLength, max(1, maxChunkLength / 2))

        while start < paragraph.endIndex {
            let end = paragraph.index(start, offsetBy: maxChunkLength, limitedBy: paragraph.endIndex) ?? paragraph.endIndex
            chunks.append(String(paragraph[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines))

            guard end < paragraph.endIndex else {
                break
            }

            let nextStart = paragraph.index(end, offsetBy: -stepBack, limitedBy: paragraph.startIndex) ?? start
            if nextStart <= start {
                start = end
            } else {
                start = nextStart
            }
        }

        return chunks.filter { !$0.isEmpty }
    }

    private func overlapSuffix(from text: String) -> String {
        guard overlapLength > 0, text.count > overlapLength else {
            return text
        }

        let index = text.index(text.endIndex, offsetBy: -overlapLength)
        return String(text[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum StudyPackGenerationStage: String, Equatable {
    case preparing
    case chunkStarted
    case chunkCompleted
    case chunkCached
    case chunkRetrying
    case consolidating
    case completed
}

struct StudyPackGenerationProgress: Equatable {
    var stage: StudyPackGenerationStage
    var completedChunks: Int
    var totalChunks: Int
    var message: String
}

struct StudyPackGenerationCache {
    var directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("PaperCue", isDirectory: true)
        .appendingPathComponent("GenerationCache", isDirectory: true)
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("PaperCue-GenerationCache", isDirectory: true)
    var fileManager: FileManager = .default

    func partialPayload(for input: GenerateStudyPackInput, chunk: TextChunk, totalChunks: Int, configuration: LLMConfiguration) -> GeneratedStudyPackPayload? {
        cache.value(forKey: cacheKey(input: input, chunk: chunk, totalChunks: totalChunks, configuration: configuration))
    }

    func storePartialPayload(
        _ payload: GeneratedStudyPackPayload,
        for input: GenerateStudyPackInput,
        chunk: TextChunk,
        totalChunks: Int,
        configuration: LLMConfiguration
    ) throws {
        try cache.store(payload, forKey: cacheKey(input: input, chunk: chunk, totalChunks: totalChunks, configuration: configuration))
    }

    private var cache: JSONFileCache<GeneratedStudyPackPayload> {
        JSONFileCache(directory: directory, fileManager: fileManager)
    }

    private func cacheKey(input: GenerateStudyPackInput, chunk: TextChunk, totalChunks: Int, configuration: LLMConfiguration) -> String {
        StableCacheKey.key(
            for: [
                "chunk-v2",
                configuration.model,
                input.title,
                input.sourceKind.rawValue,
                input.sourceURL?.absoluteString ?? "",
                input.generationProfile.rawValue,
                input.outputLanguage,
                input.options.orderedEnabledModules.map(\.rawValue).joined(separator: ","),
                input.options.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
                "\(chunk.index)",
                "\(totalChunks)",
                chunk.text
            ]
        )
    }
}

enum PayloadValidator {
    static func validateAndNormalize(
        _ payload: GeneratedStudyPackPayload,
        requireMinimumFlashcards: Bool = false,
        options: StudyPackGenerationOptions = StudyPackGenerationOptions()
    ) throws -> GeneratedStudyPackPayload {
        guard !options.orderedEnabledModules.isEmpty else {
            throw PaperCueError.invalidGeneratedPayload(message: "至少需要选择一个生成模块。")
        }

        let oneSentence = trim(payload.summary.oneSentence)
        let keyPoints = deduplicated(payload.summary.keyPoints.map(trim).filter { !$0.isEmpty })
        let methodOrArgument = trim(payload.summary.methodOrArgument)
        let limitations = trim(payload.summary.limitations)

        if options.includes(.summary) {
            guard !oneSentence.isEmpty else {
                throw PaperCueError.invalidGeneratedPayload(message: "一句话概括为空。")
            }
            guard !keyPoints.isEmpty else {
                throw PaperCueError.invalidGeneratedPayload(message: "关键点为空。")
            }
            guard !methodOrArgument.isEmpty else {
                throw PaperCueError.invalidGeneratedPayload(message: "方法或论证为空。")
            }
            guard !limitations.isEmpty else {
                throw PaperCueError.invalidGeneratedPayload(message: "局限为空。")
            }
        }

        let glossary = options.includes(.glossary)
            ? deduplicated(
                payload.glossary.compactMap { item -> GlossaryTermPayload? in
                    let term = trim(item.term.isEmpty ? item.originalTerm : item.term)
                    let originalTerm = trim(item.originalTerm.isEmpty ? term : item.originalTerm)
                    let explanation = trim(item.explanation)
                    let context = trim(item.context)
                    guard !term.isEmpty, !explanation.isEmpty else { return nil }
                    return GlossaryTermPayload(
                        term: term,
                        originalTerm: originalTerm,
                        explanation: explanation,
                        context: context
                    )
                },
                key: { normalizedKey($0.term) }
            )
            : []

        let flashcards = options.includes(.flashcards)
            ? Array(
                deduplicated(
                    payload.flashcards.compactMap { item -> FlashcardPayload? in
                        let front = trim(item.front)
                        let back = trim(item.back)
                        guard !front.isEmpty, !back.isEmpty else { return nil }
                        return FlashcardPayload(
                            front: front,
                            back: back,
                            tags: deduplicated(item.tags.map(trim).filter { !$0.isEmpty }),
                            sourceQuote: trim(item.sourceQuote)
                        )
                    },
                    key: { normalizedKey($0.front) }
                )
                .prefix(16)
            )
            : []

        if options.includes(.flashcards), requireMinimumFlashcards, flashcards.count < 8 {
            throw PaperCueError.invalidGeneratedPayload(message: "Anki 卡片少于 8 张。")
        }

        let questions = options.includes(.questions)
            ? deduplicated(
                payload.questions.compactMap { item -> ReviewQuestionPayload? in
                    let question = trim(item.question)
                    guard !question.isEmpty else { return nil }
                    return ReviewQuestionPayload(
                        question: question,
                        purpose: trim(item.purpose),
                        relatedSection: trim(item.relatedSection)
                    )
                },
                key: { normalizedKey($0.question) }
            )
            : []

        return GeneratedStudyPackPayload(
            summary: options.includes(.summary)
                ? StudySummaryPayload(
                    oneSentence: oneSentence,
                    keyPoints: keyPoints,
                    methodOrArgument: methodOrArgument,
                    limitations: limitations
                )
                : .empty,
            glossary: glossary,
            flashcards: flashcards,
            questions: questions
        )
    }

    private nonisolated static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func normalizedKey(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private nonisolated static func deduplicated(_ values: [String]) -> [String] {
        deduplicated(values, key: normalizedKey)
    }

    private nonisolated static func deduplicated<Value>(_ values: [Value], key: (Value) -> String) -> [Value] {
        var seen = Set<String>()
        var result: [Value] = []

        for value in values {
            let dedupeKey = key(value)
            guard !dedupeKey.isEmpty, seen.insert(dedupeKey).inserted else {
                continue
            }
            result.append(value)
        }

        return result
    }
}

struct StudyPackGenerationService {
    var chunker = TextChunker()
    var clientFactory: (LLMConfiguration) -> any LLMClient = {
        OpenAICompatibleLLMClient(configuration: $0)
    }
    var cache: StudyPackGenerationCache? = StudyPackGenerationCache()
    var maxChunkAttempts = 2

    func generate(
        input: GenerateStudyPackInput,
        configuration: LLMConfiguration,
        progress: (StudyPackGenerationProgress) -> Void = { _ in }
    ) async throws -> GeneratedStudyPackPayload {
        try Task.checkCancellation()
        guard !input.options.orderedEnabledModules.isEmpty else {
            throw PaperCueError.invalidGeneratedPayload(message: "至少需要选择一个生成模块。")
        }

        let chunks = chunker.chunk(text: input.text)
        let client = clientFactory(configuration)
        progress(
            StudyPackGenerationProgress(
                stage: .preparing,
                completedChunks: 0,
                totalChunks: chunks.count,
                message: chunks.count > 1 ? "准备分块生成，共 \(chunks.count) 块。" : "准备生成学习材料。"
            )
        )

        guard chunks.count > 1 else {
            let payload = try await client.generateStudyPack(input: input)
            let normalized = try PayloadValidator.validateAndNormalize(payload, requireMinimumFlashcards: true, options: input.options)
            progress(
                StudyPackGenerationProgress(
                    stage: .completed,
                    completedChunks: 1,
                    totalChunks: 1,
                    message: "生成完成。"
                )
            )
            return normalized
        }

        let contextBrief = try await documentContextBrief(
            client: client,
            input: input,
            chunks: chunks,
            progress: progress
        )
        var partialPayloads: [GeneratedStudyPackPayload] = []
        for chunk in chunks {
            try Task.checkCancellation()

            if let cached = cache?.partialPayload(for: input, chunk: chunk, totalChunks: chunks.count, configuration: configuration) {
                partialPayloads.append(cached)
                progress(
                    StudyPackGenerationProgress(
                        stage: .chunkCached,
                        completedChunks: partialPayloads.count,
                        totalChunks: chunks.count,
                        message: "已复用第 \(chunk.index + 1) / \(chunks.count) 块缓存。"
                    )
                )
                continue
            }

            var chunkInput = input
            chunkInput.text = chunk.text
            chunkInput.taskInstruction = """
            全局上下文 brief（用于理解当前分片中的术语、缩写、指代和论文主线；若与当前分片原文冲突，以当前分片原文为准，不要据此补写当前分片未出现的证据）：
            \(contextBrief)

            这是全文的第 \(chunk.index + 1) / \(chunks.count) 个分块。请只根据这个分块生成局部学习材料；不要补全文中未出现的信息。卡片和术语优先覆盖本分块最关键内容。
            """

            progress(
                StudyPackGenerationProgress(
                    stage: .chunkStarted,
                    completedChunks: partialPayloads.count,
                    totalChunks: chunks.count,
                    message: "正在生成第 \(chunk.index + 1) / \(chunks.count) 块。"
                )
            )

            let payload = try await generateChunkWithRetry(
                client: client,
                input: chunkInput,
                chunk: chunk,
                totalChunks: chunks.count,
                progress: progress
            )
            let normalized = try PayloadValidator.validateAndNormalize(payload, options: input.options)
            try? cache?.storePartialPayload(normalized, for: input, chunk: chunk, totalChunks: chunks.count, configuration: configuration)
            partialPayloads.append(normalized)
            progress(
                StudyPackGenerationProgress(
                    stage: .chunkCompleted,
                    completedChunks: partialPayloads.count,
                    totalChunks: chunks.count,
                    message: "第 \(chunk.index + 1) / \(chunks.count) 块完成。"
                )
            )
        }

        try Task.checkCancellation()
        progress(
            StudyPackGenerationProgress(
                stage: .consolidating,
                completedChunks: partialPayloads.count,
                totalChunks: chunks.count,
                message: "正在合并分块结果。"
            )
        )

        var consolidationInput = input
        consolidationInput.text = try consolidationText(from: partialPayloads)
        consolidationInput.taskInstruction = """
        全局上下文 brief：
        \(contextBrief)

        下面是同一篇文档各分块生成的学习材料 JSON。请合并去重，保留最能覆盖全文主线的内容，并继续严格遵守输出 schema。若已选择 Anki 卡片模块，最终输出 8 到 16 张卡片；未选择的模块必须保持空。
        """

        let mergedPayload = try await client.generateStudyPack(input: consolidationInput)
        let normalized = try PayloadValidator.validateAndNormalize(mergedPayload, requireMinimumFlashcards: true, options: input.options)
        progress(
            StudyPackGenerationProgress(
                stage: .completed,
                completedChunks: chunks.count,
                totalChunks: chunks.count,
                message: "生成完成。"
            )
        )
        return normalized
    }

    private func documentContextBrief(
        client: any LLMClient,
        input: GenerateStudyPackInput,
        chunks: [TextChunk],
        progress: (StudyPackGenerationProgress) -> Void
    ) async throws -> String {
        progress(
            StudyPackGenerationProgress(
                stage: .preparing,
                completedChunks: 0,
                totalChunks: chunks.count,
                message: "正在生成全文上下文。"
            )
        )

        do {
            let brief = try await client.generateStudyPackContextBrief(input: input)
            let normalized = normalizedContextBrief(brief)
            if !normalized.isEmpty {
                progress(
                    StudyPackGenerationProgress(
                        stage: .preparing,
                        completedChunks: 0,
                        totalChunks: chunks.count,
                        message: "已生成全文上下文，准备分块。"
                    )
                )
                return normalized
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            progress(
                StudyPackGenerationProgress(
                    stage: .preparing,
                    completedChunks: 0,
                    totalChunks: chunks.count,
                    message: "全文上下文生成失败，使用本地提要继续。"
                )
            )
        }

        return fallbackContextBrief(for: input, chunks: chunks)
    }

    private func normalizedContextBrief(_ brief: String) -> String {
        let normalized = normalizeText(brief)
        guard normalized.count > 1_500 else {
            return normalized
        }

        return String(normalized.prefix(1_500)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fallbackContextBrief(for input: GenerateStudyPackInput, chunks: [TextChunk]) -> String {
        let normalized = normalizeText(input.text)
        let opening = clippedContextText(firstParagraphs(from: normalized, limit: 2), maxLength: 900)
        let ending = normalized.count > 2_400 ? clippedContextText(String(normalized.suffix(900)), maxLength: 900) : ""
        let headings = headingHints(from: normalized, limit: 8)

        var lines = [
            "标题：\(input.title)",
            "来源类型：\(input.sourceKind.title)",
            "分块数量：\(chunks.count)。"
        ]

        if !headings.isEmpty {
            lines.append("可能的章节线索：\(headings.joined(separator: "；"))")
        }

        if !opening.isEmpty {
            lines.append("开头/摘要线索：\(opening)")
        }

        if !ending.isEmpty {
            lines.append("结尾线索：\(ending)")
        }

        lines.append("使用要求：该 brief 只用于理解当前分片中的术语、缩写和指代；生成内容仍以当前分片原文为准。")
        return lines.joined(separator: "\n")
    }

    private func firstParagraphs(from text: String, limit: Int) -> String {
        text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(limit)
            .joined(separator: "\n\n")
    }

    private func headingHints(from text: String, limit: Int) -> [String] {
        var seen = Set<String>()
        var headings: [String] = []

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard looksLikeHeading(line) else { continue }

            let key = line.lowercased()
            guard seen.insert(key).inserted else { continue }

            headings.append(line)
            if headings.count >= limit {
                break
            }
        }

        return headings
    }

    private func looksLikeHeading(_ line: String) -> Bool {
        guard line.count >= 2, line.count <= 90 else {
            return false
        }

        let lowercased = line.lowercased()
        let knownHeadings = [
            "abstract",
            "introduction",
            "background",
            "related work",
            "method",
            "methods",
            "results",
            "discussion",
            "conclusion",
            "摘要",
            "引言",
            "背景",
            "相关工作",
            "方法",
            "实验",
            "结果",
            "讨论",
            "结论"
        ]

        if knownHeadings.contains(where: { lowercased == $0 || lowercased.hasPrefix("\($0) ") }) {
            return true
        }

        return line.range(of: #"^\d+(\.\d+)*\.?\s+\S+"#, options: .regularExpression) != nil
    }

    private func clippedContextText(_ text: String, maxLength: Int) -> String {
        let normalized = normalizeText(text)
        guard normalized.count > maxLength else {
            return normalized
        }

        return String(normalized.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generateChunkWithRetry(
        client: any LLMClient,
        input: GenerateStudyPackInput,
        chunk: TextChunk,
        totalChunks: Int,
        progress: (StudyPackGenerationProgress) -> Void
    ) async throws -> GeneratedStudyPackPayload {
        var lastError: Error?
        let attempts = max(1, maxChunkAttempts)

        for attempt in 1...attempts {
            do {
                return try await client.generateStudyPack(input: input)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt < attempts else { break }
                progress(
                    StudyPackGenerationProgress(
                        stage: .chunkRetrying,
                        completedChunks: chunk.index,
                        totalChunks: totalChunks,
                        message: "第 \(chunk.index + 1) / \(totalChunks) 块失败，正在重试。"
                    )
                )
            }
        }

        throw lastError ?? PaperCueError.unsupportedResponse
    }

    private func consolidationText(from payloads: [GeneratedStudyPackPayload]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payloads)

        guard let text = String(data: data, encoding: .utf8) else {
            throw PaperCueError.invalidGeneratedPayload(message: "分块结果无法编码。")
        }

        return text
    }
}
