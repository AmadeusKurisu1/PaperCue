//
//  PaperCueTests.swift
//  PaperCueTests
//
//  Created by 孙昊 on 2026/5/11.
//

import Foundation
import SwiftData
import Testing
@testable import PaperCue

@Suite(.serialized)
@MainActor
struct PaperCueTests {
    @Test func readingDocumentStoresStudyPackGraph() throws {
        let configuration = ModelConfiguration(schema: paperCueSchema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: paperCueSchema, configurations: [configuration])
        let context = ModelContext(container)

        let document = ReadingDocument(
            title: "A Paper",
            sourceKind: .pdf,
            sourceURL: URL(string: "https://example.com/paper.pdf"),
            extractedText: "This is a paper about retrieval augmented generation."
        )
        let pack = GeneratedStudyPack(payload: .sample)

        context.insert(document)
        context.insert(pack)
        document.studyPack = pack
        document.generationStatus = .completed
        try context.save()

        #expect(document.generationStatus == .completed)
        #expect(document.studyPack?.flashcards.count == 1)
        #expect(document.textPreview.contains("retrieval augmented generation"))
    }

    @Test func decodesStudyPackPayloadFromFencedJSON() throws {
        let json = """
        ```json
        {
          "summary": {
            "oneSentence": "一句话",
            "keyPoints": ["点一", "点二"],
            "methodOrArgument": "方法",
            "limitations": "局限"
          },
          "glossary": [
            {
              "term": "表示学习",
              "originalTerm": "Representation learning",
              "explanation": "学习数据表示的方法。",
              "context": "方法部分"
            }
          ],
          "flashcards": [
            {
              "front": "问题？",
              "back": "答案",
              "tags": ["PaperCue"],
              "sourceQuote": "原文"
            }
          ],
          "questions": [
            {
              "question": "还需要验证什么？",
              "purpose": "复盘",
              "relatedSection": "讨论"
            }
          ]
        }
        ```
        """

        let payload = try decodePayload(from: json)

        #expect(payload.summary.keyPoints.count == 2)
        #expect(payload.glossary.first?.originalTerm == "Representation learning")
        #expect(payload.flashcards.first?.front == "问题？")
        #expect(payload.questions.first?.purpose == "复盘")
    }

    @Test func decodesStudyPackPayloadFromCompatibleProviderKeyVariants() throws {
        let json = """
        {
          "summary": {
            "one_sentence": "本文研究语音特征与抑郁症状分类之间的关系。",
            "key_points": ["使用语音特征", "训练分类模型"],
            "method_or_argument": "作者提取语音指标并比较分类结果。",
            "limitations": ["样本规模有限", "需要外部验证"]
          },
          "terms": [
            {
              "concept": "抑郁症状分类",
              "original_term": "Depressive symptom classification",
              "definition": "根据观察信号判断症状类别的任务。",
              "section": "Introduction"
            }
          ],
          "anki_cards": [
            {
              "question": "这项研究使用什么信号进行分类？",
              "answer": "使用语音信号和相关声学特征。",
              "tags": "PaperCue, voice"
            }
          ],
          "review_questions": [
            {
              "question": "模型是否能推广到其他人群？",
              "rationale": "评估外部有效性",
              "section": "Discussion"
            }
          ]
        }
        """

        let payload = try decodePayload(from: json)

        #expect(payload.summary.oneSentence.contains("语音特征"))
        #expect(payload.summary.limitations.contains("外部验证"))
        #expect(payload.glossary.first?.term == "抑郁症状分类")
        #expect(payload.flashcards.first?.front.contains("什么信号") == true)
        #expect(payload.flashcards.first?.sourceQuote == "")
        #expect(payload.flashcards.first?.tags == ["PaperCue", "voice"])
        #expect(payload.questions.first?.purpose == "评估外部有效性")
    }

    @Test func providerPresetMatchingRecognizesKnownBaseURLs() {
        #expect(LLMProviderPreset.matching(baseURLString: "https://api.openai.com") == .openAI)
        #expect(LLMProviderPreset.matching(baseURLString: "https://api.deepseek.com/v1/") == .deepSeek)
        #expect(LLMProviderPreset.matching(baseURLString: "https://open.bigmodel.cn/api/paas/v4") == .zhipu)
        #expect(LLMProviderPreset.matching(baseURLString: "https://example.com/openai") == nil)
    }

    @Test func providerPresetsExposeDefaultModelChoices() {
        for provider in LLMProviderPreset.allCases where !provider.isCustom {
            #expect(provider.modelPresets.contains { $0.id == provider.defaultModel })
        }

        #expect(LLMProviderPreset.openAI.modelPresets.map(\.id).contains("gpt-5.5"))
        #expect(LLMProviderPreset.deepSeek.modelPresets.map(\.id).contains("deepseek-v4-pro"))
        #expect(LLMProviderPreset.kimi.modelPresets.map(\.id).contains("kimi-k2.6"))
        #expect(LLMProviderPreset.kimi.modelPresets.map(\.id).contains("kimi-k2-0905-preview"))
    }

    @Test func onlyOpenAIPresetPrefersResponsesAPI() {
        #expect(LLMProviderPreset.openAI.prefersResponsesAPI)

        for provider in LLMProviderPreset.allCases where provider != .openAI {
            #expect(!provider.prefersResponsesAPI)
        }
    }

    @Test func webExtractorStripsScriptStyleAndDecodesEntities() {
        let html = """
        <html>
          <head>
            <title>Paper &amp; Notes</title>
            <style>.hidden { display: none; }</style>
            <script>window.secret = true;</script>
          </head>
          <body>
            <article>
              <h1>Title</h1>
              <p>First&nbsp;paragraph.</p>
              <p>Second paragraph.</p>
            </article>
          </body>
        </html>
        """

        let extractor = WebArticleExtractor()
        let title = extractor.extractTitle(from: html)
        let text = normalizeText(extractor.extractVisibleText(from: html))

        #expect(title == "Paper & Notes")
        #expect(text.contains("First paragraph."))
        #expect(text.contains("Second paragraph."))
        #expect(!text.contains("window.secret"))
        #expect(!text.contains("display: none"))
    }

    @Test func webExtractorScoresArticleAboveNavigationChrome() {
        let html = """
        <html>
          <body>
            <nav><a href="/">Home</a><a href="/topics">Topics</a><a href="/about">About</a></nav>
            <article>
              <h1>Important paper</h1>
              <p>This article paragraph explains the research question, motivation, method, evidence, and conclusion in enough detail for reading support.</p>
              <p>The second paragraph adds limitations, external validity concerns, and implications for future work.</p>
            </article>
            <footer><a href="/privacy">Privacy</a></footer>
          </body>
        </html>
        """

        let result = WebArticleExtractor().extractArticleText(from: html)
        let text = normalizeText(result.text)

        #expect(text.contains("research question"))
        #expect(!text.contains("Privacy"))
        #expect(!result.isLowConfidence)
    }

    @Test func webExtractorMarksLinkHeavyPagesAsLowConfidence() {
        let html = """
        <html><body>
          <main>
            <a href="/a">Home</a>
            <a href="/b">Topics</a>
            <a href="/c">Authors</a>
          </main>
        </body></html>
        """

        let result = WebArticleExtractor().extractArticleText(from: html)

        #expect(result.isLowConfidence)
    }

    @Test func importURLNormalizerHandlesDOIArxivAndPubMedInputs() throws {
        #expect(ImportURLNormalizer.normalizedURL(from: "10.1145/1234567.890123")?.absoluteString == "https://doi.org/10.1145/1234567.890123")
        #expect(ImportURLNormalizer.normalizedURL(from: "arXiv:2401.12345")?.absoluteString == "https://arxiv.org/abs/2401.12345")
        #expect(ImportURLNormalizer.normalizedURL(from: "PMID: 12345678")?.absoluteString == "https://pubmed.ncbi.nlm.nih.gov/12345678/")
    }

    @Test func webExtractorPrefersCitationMetadataTitle() {
        let html = """
        <html>
          <head>
            <title>Site chrome title</title>
            <meta name="citation_title" content="Actual Paper Title">
          </head>
          <body><article><p>Body text long enough for extraction.</p></article></body>
        </html>
        """

        let title = WebArticleExtractor().extractMetadataTitle(from: html, url: URL(string: "https://example.com/paper")!)

        #expect(title == "Actual Paper Title")
    }

    @Test func documentExtractionCacheStoresAndLoadsWebExtraction() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PaperCueExtractionCache-\(UUID().uuidString)")
        let cache = DocumentExtractionCache(directory: directory)
        let url = URL(string: "https://example.com/article")!
        let extraction = ExtractedDocumentText(
            title: "Cached Article",
            text: "Cached body",
            sourceURL: url,
            sourceKind: .web
        )

        try cache.storeWebExtraction(extraction, for: url)

        #expect(cache.cachedWebExtraction(for: url) == extraction)
    }

    @Test func pastedTextImportCreatesReadyTextDocument() throws {
        let document = try ImportService().importPastedText(
            title: "  My Notes  ",
            text: " First paragraph.\n\n\n Second paragraph. "
        )

        #expect(document.title == "My Notes")
        #expect(document.sourceKind == .text)
        #expect(document.sourceURL == nil)
        #expect(document.generationStatus == .ready)
        #expect(document.extractedText == "First paragraph.\n\nSecond paragraph.")
    }

    @Test func sourceReferenceExtractorFindsPageMarkers() {
        let labels = SourceReferenceExtractor.pageLabels(in: "See [Page 12] and Page 3, then 第 12 页 again.")

        #expect(labels == ["Page 3", "Page 12"])
        #expect(SourceReferenceExtractor.displayLabel(for: "[Page 12] key evidence") == "来源：Page 12")
        #expect(SourceReferenceExtractor.displayLabel(for: "Discussion") == "来源：Discussion")
    }

    @Test func breakableTextAddsOpportunitiesInsideLongRuns() {
        let value = "abcdefghijklmnopqrstuvwxyz".paperCueBreakableText(maxRunLength: 6)

        #expect(value.contains("\u{200B}"))
        #expect(value.replacingOccurrences(of: "\u{200B}", with: "") == "abcdefghijklmnopqrstuvwxyz")
    }

    @Test func fullTextParserSplitsPageMarkedTextIntoReaderBlocks() {
        let text = """
        [Page 1]
        Opening paragraph.

        Second paragraph.

        [Page 2]
        Method paragraph with causal evidence.
        """

        let blocks = DocumentTextBlockParser.blocks(from: text, sourceKind: .pdf)

        #expect(blocks.count == 3)
        #expect(blocks[0].pageNumber == 1)
        #expect(blocks[0].startsPage)
        #expect(blocks[1].pageNumber == 1)
        #expect(!blocks[1].startsPage)
        #expect(blocks[2].pageNumber == 2)
        #expect(blocks[2].startsPage)
    }

    @Test func fullTextParserBreaksVeryLongParagraphs() {
        let text = String(repeating: "continuousreadingtext", count: 180)

        let blocks = DocumentTextBlockParser.blocks(from: text, sourceKind: .text)

        #expect(blocks.count > 1)
        #expect(blocks.allSatisfy { $0.text.count <= 2_400 })
    }

    @Test func fullTextParserFindsSourceReferenceBlock() throws {
        let text = """
        [Page 1]
        The opening page introduces the topic.

        [Page 2]
        The method section explains the causal evidence and robustness checks in detail.
        """
        let blocks = DocumentTextBlockParser.blocks(from: text, sourceKind: .pdf)
        let reference = SourceReference(pageNumbers: [2], quote: "causal evidence")

        let blockID = try #require(DocumentTextBlockParser.bestBlockID(matching: reference, in: blocks))
        let block = try #require(blocks.first { $0.id == blockID })

        #expect(block.pageNumber == 2)
        #expect(block.text.contains("causal evidence"))
    }

    @Test func sourceReferenceResolverFindsQuotedPageExcerpt() throws {
        let documentText = """
        [Page 1]
        The opening page introduces the topic.

        [Page 2]
        The method section explains the causal evidence and robustness checks in detail.
        """

        let resolved = try #require(SourceReferenceResolver.resolve(referenceText: "[Page 2] causal evidence", in: documentText))

        #expect(resolved.pageLabel == "Page 2")
        #expect(resolved.excerpt.contains("causal evidence"))
    }

    @Test func textChunkerSplitsLongDocumentsWithOverlap() {
        let paragraphs = (0..<16).map { index in
            "Paragraph \(index) " + String(repeating: "research evidence ", count: 18)
        }
        let text = paragraphs.joined(separator: "\n\n")
        let chunker = TextChunker(longDocumentThreshold: 200, maxChunkLength: 420, overlapLength: 60)

        let chunks = chunker.chunk(text: text)

        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.text.count <= 420 })
        #expect(chunks[1].text.contains("research evidence"))
    }

    @Test func payloadValidatorDeduplicatesAndLimitsFinalCards() throws {
        let payload = Self.validPayload(cardCount: 18, duplicateFirstCard: true)
        let normalized = try PayloadValidator.validateAndNormalize(payload, requireMinimumFlashcards: true)

        #expect(normalized.flashcards.count == 16)
        #expect(Set(normalized.flashcards.map(\.front)).count == normalized.flashcards.count)
        #expect(normalized.summary.keyPoints == ["Point A", "Point B"])
    }

    @Test func payloadValidatorRejectsTooFewFinalCards() {
        let payload = Self.validPayload(cardCount: 3)

        do {
            _ = try PayloadValidator.validateAndNormalize(payload, requireMinimumFlashcards: true)
            Issue.record("Expected final payload with too few cards to fail validation.")
        } catch let error as PaperCueError {
            #expect(error.errorDescription?.contains("Anki 卡片少于 8 张") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func payloadValidatorHonorsDisabledModules() throws {
        let payload = Self.validPayload(cardCount: 3)
        let options = StudyPackGenerationOptions(enabledModules: [.summary, .questions])

        let normalized = try PayloadValidator.validateAndNormalize(
            payload,
            requireMinimumFlashcards: true,
            options: options
        )

        #expect(!normalized.summary.oneSentence.isEmpty)
        #expect(normalized.glossary.isEmpty)
        #expect(normalized.flashcards.isEmpty)
        #expect(!normalized.questions.isEmpty)
    }

    @Test func generationServiceChunksThenConsolidatesLongDocuments() async throws {
        let client = RecordingLLMClient(
            payload: Self.validPayload(cardCount: 8),
            contextBrief: "全局上下文：本文围绕检索增强生成评估，方法线索是分块证据汇总。"
        )
        let service = StudyPackGenerationService(
            chunker: TextChunker(longDocumentThreshold: 120, maxChunkLength: 220, overlapLength: 40),
            clientFactory: { _ in client },
            cache: nil
        )
        let text = (0..<10)
            .map { "Section \($0) " + String(repeating: "paper cue generation evidence ", count: 12) }
            .joined(separator: "\n\n")

        _ = try await service.generate(
            input: GenerateStudyPackInput(
                title: "Long paper",
                sourceKind: .pdf,
                sourceURL: nil,
                text: text,
                generationProfile: .seminar
            ),
            configuration: Self.testConfiguration()
        )

        #expect(client.inputs.count > 2)
        #expect(client.contextInputs.count == 1)
        #expect(client.contextInputs.first?.text == text)
        #expect(client.inputs.dropLast().allSatisfy { $0.taskInstruction?.contains("分块") == true })
        #expect(client.inputs.dropLast().allSatisfy { $0.taskInstruction?.contains("全局上下文 brief") == true })
        #expect(client.inputs.dropLast().allSatisfy { $0.taskInstruction?.contains("检索增强生成评估") == true })
        #expect(client.inputs.last?.taskInstruction?.contains("合并去重") == true)
        #expect(client.inputs.last?.taskInstruction?.contains("检索增强生成评估") == true)
        #expect(client.inputs.allSatisfy { $0.generationProfile == .seminar })
    }

    @Test func generationServiceRetriesFailedChunk() async throws {
        let client = FlakyLLMClient(payload: Self.validPayload(cardCount: 8), failuresBeforeSuccess: 1)
        let service = StudyPackGenerationService(
            chunker: TextChunker(longDocumentThreshold: 120, maxChunkLength: 220, overlapLength: 40),
            clientFactory: { _ in client },
            cache: nil,
            maxChunkAttempts: 2
        )
        let text = (0..<8)
            .map { "Chunk \($0) " + String(repeating: "retry evidence ", count: 18) }
            .joined(separator: "\n\n")
        var progressMessages: [String] = []

        _ = try await service.generate(
            input: GenerateStudyPackInput(title: "Retry", sourceKind: .text, sourceURL: nil, text: text),
            configuration: Self.testConfiguration(),
            progress: { progressMessages.append($0.message) }
        )

        #expect(client.inputs.count > 2)
        #expect(progressMessages.contains { $0.contains("正在重试") })
    }

    @Test func generationServiceAllowsSummaryOnlyWithoutCards() async throws {
        let client = RecordingLLMClient(payload: Self.validPayload(cardCount: 0))
        let service = StudyPackGenerationService(
            clientFactory: { _ in client },
            cache: nil
        )

        let payload = try await service.generate(
            input: GenerateStudyPackInput(
                title: "Summary only",
                sourceKind: .text,
                sourceURL: nil,
                text: "Short article body.",
                options: StudyPackGenerationOptions(enabledModules: [.summary])
            ),
            configuration: Self.testConfiguration()
        )

        #expect(!payload.summary.oneSentence.isEmpty)
        #expect(payload.glossary.isEmpty)
        #expect(payload.flashcards.isEmpty)
        #expect(payload.questions.isEmpty)
    }

    @Test func generationServiceReusesCachedChunkPayloads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PaperCueGenerationCache-\(UUID().uuidString)")
        let cache = StudyPackGenerationCache(directory: directory)
        let firstClient = RecordingLLMClient(payload: Self.validPayload(cardCount: 8))
        let secondClient = RecordingLLMClient(payload: Self.validPayload(cardCount: 8))
        let chunker = TextChunker(longDocumentThreshold: 120, maxChunkLength: 220, overlapLength: 40)
        let text = (0..<8)
            .map { "Cached \($0) " + String(repeating: "generation cache evidence ", count: 12) }
            .joined(separator: "\n\n")
        let input = GenerateStudyPackInput(title: "Cache", sourceKind: .text, sourceURL: nil, text: text)

        _ = try await StudyPackGenerationService(
            chunker: chunker,
            clientFactory: { _ in firstClient },
            cache: cache
        )
        .generate(input: input, configuration: Self.testConfiguration())

        _ = try await StudyPackGenerationService(
            chunker: chunker,
            clientFactory: { _ in secondClient },
            cache: cache
        )
        .generate(input: input, configuration: Self.testConfiguration())

        #expect(firstClient.inputs.count > 2)
        #expect(secondClient.inputs.count == 1)
        #expect(secondClient.inputs.first?.taskInstruction?.contains("合并去重") == true)
    }

    @Test func pdfExtractorOCRTriggerUsesMinimumPageTextLength() {
        let extractor = DocumentTextExtractor(minimumPageTextLengthForOCR: 10)

        #expect(extractor.shouldUseOCR(for: "short"))
        #expect(!extractor.shouldUseOCR(for: "This page has enough text."))
    }

    @Test func chatCompletionsFallsBackWhenResponseFormatUnsupported() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handlers = [
            { request in
                let data = Self.jsonData([
                    "error": [
                        "message": "response_format is not supported"
                    ]
                ])
                return (Self.httpResponse(for: request, statusCode: 400), data)
            },
            { request in
                let data = Self.jsonData([
                    "choices": [
                        [
                            "message": [
                                "content": Self.validPayloadJSONString(cardCount: 8)
                            ]
                        ]
                    ]
                ])
                return (Self.httpResponse(for: request, statusCode: 200), data)
            }
        ]

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenAICompatibleLLMClient(
            configuration: Self.testConfiguration(prefersResponsesAPI: false),
            urlSession: session
        )

        _ = try await client.generateStudyPack(
            input: GenerateStudyPackInput(
                title: "Fallback",
                sourceKind: .web,
                sourceURL: URL(string: "https://example.com"),
                text: "Article body"
            )
        )

        #expect(MockURLProtocol.requests.count == 2)
        let firstBody = try #require(Self.requestBody(at: 0))
        let secondBody = try #require(Self.requestBody(at: 1))
        #expect(firstBody["response_format"] != nil)
        #expect(secondBody["response_format"] == nil)
    }

    @Test func generationProfileInstructionAppearsInLLMRequestBody() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handlers = [
            { request in
                let data = Self.jsonData([
                    "choices": [
                        [
                            "message": [
                                "content": Self.validPayloadJSONString(cardCount: 8)
                            ]
                        ]
                    ]
                ])
                return (Self.httpResponse(for: request, statusCode: 200), data)
            }
        ]

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenAICompatibleLLMClient(
            configuration: Self.testConfiguration(prefersResponsesAPI: false),
            urlSession: session
        )

        _ = try await client.generateStudyPack(
            input: GenerateStudyPackInput(
                title: "Seminar",
                sourceKind: .text,
                sourceURL: nil,
                text: "[Page 2]\nEvidence body",
                generationProfile: .seminar
            )
        )

        let body = try #require(Self.requestBody(at: 0))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let userMessage = try #require(messages.first { ($0["role"] as? String) == "user" }?["content"] as? String)

        #expect(userMessage.contains("生成模式：讨论"))
        #expect(userMessage.contains("外部有效性"))
        #expect(userMessage.contains("来源回溯要求"))
        #expect(userMessage.contains("[Page 2]"))
    }

    @Test func customPromptAndModuleSelectionAppearInLLMRequestBody() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handlers = [
            { request in
                let data = Self.jsonData([
                    "choices": [
                        [
                            "message": [
                                "content": Self.validPayloadJSONString(cardCount: 8)
                            ]
                        ]
                    ]
                ])
                return (Self.httpResponse(for: request, statusCode: 200), data)
            }
        ]

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenAICompatibleLLMClient(
            configuration: Self.testConfiguration(prefersResponsesAPI: false),
            urlSession: session
        )

        _ = try await client.generateStudyPack(
            input: GenerateStudyPackInput(
                title: "Custom",
                sourceKind: .text,
                sourceURL: nil,
                text: "Article body.",
                options: StudyPackGenerationOptions(
                    enabledModules: [.summary, .questions],
                    customPrompt: "更关注研究设计，不要展开背景。"
                )
            )
        )

        let body = try #require(Self.requestBody(at: 0))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let userMessage = try #require(messages.first { ($0["role"] as? String) == "user" }?["content"] as? String)

        #expect(userMessage.contains("用户自定义要求"))
        #expect(userMessage.contains("更关注研究设计"))
        #expect(userMessage.contains("未选择模块：术语、卡片"))
        #expect(userMessage.contains("- 摘要"))
        #expect(userMessage.contains("- 提问清单"))
        #expect(!userMessage.contains("- Anki 卡片"))
    }

    @Test func contextBriefRequestReturnsDecodedBrief() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handlers = [
            { request in
                let data = Self.jsonData([
                    "choices": [
                        [
                            "message": [
                                "content": #"{"contextBrief":"研究问题是检索增强生成评估；方法线索是分块证据汇总。"}"#
                            ]
                        ]
                    ]
                ])
                return (Self.httpResponse(for: request, statusCode: 200), data)
            }
        ]

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenAICompatibleLLMClient(
            configuration: Self.testConfiguration(prefersResponsesAPI: false),
            urlSession: session
        )

        let brief = try await client.generateStudyPackContextBrief(
            input: GenerateStudyPackInput(
                title: "Context",
                sourceKind: .text,
                sourceURL: nil,
                text: "Article body about retrieval augmented generation."
            )
        )

        let body = try #require(Self.requestBody(at: 0))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let userMessage = try #require(messages.first { ($0["role"] as? String) == "user" }?["content"] as? String)

        #expect(brief.contains("检索增强生成评估"))
        #expect(userMessage.contains("全局上下文 brief"))
        #expect(userMessage.contains("Article body"))
        #expect(body["response_format"] != nil)
    }

    @Test func ankiExporterWritesEscapedTSV() throws {
        let card = Flashcard(
            front: "What\tchanged?",
            back: "Line 1\nLine 2",
            tags: ["PaperCue", "review", "review"],
            sourceQuote: "Quote"
        )

        let url = try AnkiExporter().export(cards: [card], sourceTitle: "Paper: Cue/Notes")
        let content = try String(contentsOf: url, encoding: .utf8)

        #expect(url.lastPathComponent == "Paper-Cue-Notes-Anki.tsv")
        #expect(content.contains("Front\tBack\tTags\tSource"))
        #expect(content.contains("What changed?\tLine 1<br>Line 2\tPaperCue review\tPaper: Cue/Notes"))
    }

    @Test func studyPackExporterWritesMarkdownJSONAndCSV() throws {
        let pack = GeneratedStudyPack(payload: Self.validPayload(cardCount: 8))
        let exporter = StudyPackExporter()

        let markdown = try String(contentsOf: exporter.export(studyPack: pack, sourceTitle: "Export Paper", format: .markdown), encoding: .utf8)
        let json = try String(contentsOf: exporter.export(studyPack: pack, sourceTitle: "Export Paper", format: .json), encoding: .utf8)
        let csv = try String(contentsOf: exporter.export(studyPack: pack, sourceTitle: "Export Paper", format: .csv), encoding: .utf8)

        #expect(markdown.contains("# Export Paper"))
        #expect(json.contains("\"flashcards\""))
        #expect(csv.contains("\"Flashcard\""))
    }

    private static func testConfiguration(prefersResponsesAPI: Bool = true) -> LLMConfiguration {
        LLMConfiguration(
            baseURL: URL(string: "https://example.com/v1")!,
            apiKey: "test-key",
            model: "test-model",
            maxOutputTokens: 2_000,
            prefersResponsesAPI: prefersResponsesAPI,
            generationTimeoutSeconds: 30
        )
    }

    private static func validPayload(cardCount: Int, duplicateFirstCard: Bool = false) -> GeneratedStudyPackPayload {
        let cards = (0..<cardCount).map { index in
            FlashcardPayload(
                front: duplicateFirstCard && index == 1 ? "Card 0?" : "Card \(index)?",
                back: "Answer \(index)",
                tags: ["PaperCue", "review", "review"],
                sourceQuote: "Quote \(index)"
            )
        }

        return GeneratedStudyPackPayload(
            summary: StudySummaryPayload(
                oneSentence: "One sentence summary.",
                keyPoints: ["Point A", "Point A", "Point B"],
                methodOrArgument: "Method.",
                limitations: "Limitations."
            ),
            glossary: [
                GlossaryTermPayload(
                    term: "Concept",
                    originalTerm: "Concept",
                    explanation: "Explanation.",
                    context: "Context."
                )
            ],
            flashcards: cards,
            questions: [
                ReviewQuestionPayload(
                    question: "Question?",
                    purpose: "Purpose.",
                    relatedSection: "Discussion"
                )
            ]
        )
    }

    private static func validPayloadJSONString(cardCount: Int) -> String {
        let data = try! JSONEncoder().encode(validPayload(cardCount: cardCount))
        return String(data: data, encoding: .utf8)!
    }

    private static func jsonData(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private static func httpResponse(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private static func requestBody(at index: Int) -> [String: Any]? {
        guard MockURLProtocol.bodies.indices.contains(index),
              let body = MockURLProtocol.bodies[index],
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }

        return object
    }
}

@MainActor
private final class RecordingLLMClient: LLMClient {
    var payload: GeneratedStudyPackPayload
    var contextBrief: String
    var inputs: [GenerateStudyPackInput] = []
    var contextInputs: [GenerateStudyPackInput] = []

    init(payload: GeneratedStudyPackPayload, contextBrief: String = "全局上下文：研究问题、方法和关键术语。") {
        self.payload = payload
        self.contextBrief = contextBrief
    }

    func generateStudyPack(input: GenerateStudyPackInput) async throws -> GeneratedStudyPackPayload {
        inputs.append(input)
        return payload
    }

    func generateStudyPackContextBrief(input: GenerateStudyPackInput) async throws -> String {
        contextInputs.append(input)
        return contextBrief
    }
}

@MainActor
private final class FlakyLLMClient: LLMClient {
    var payload: GeneratedStudyPackPayload
    var failuresBeforeSuccess: Int
    var inputs: [GenerateStudyPackInput] = []

    init(payload: GeneratedStudyPackPayload, failuresBeforeSuccess: Int) {
        self.payload = payload
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func generateStudyPack(input: GenerateStudyPackInput) async throws -> GeneratedStudyPackPayload {
        inputs.append(input)
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw PaperCueError.networkUnavailable(message: "Transient failure")
        }
        return payload
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handlers: [(URLRequest) -> (HTTPURLResponse, Data)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data?] = []

    static func reset() {
        handlers = []
        requests = []
        bodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodies.append(Self.bodyData(from: request))

        guard !Self.handlers.isEmpty else {
            client?.urlProtocol(self, didFailWithError: PaperCueError.unsupportedResponse)
            return
        }

        let handler = Self.handlers.removeFirst()
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }

        return data
    }
}
