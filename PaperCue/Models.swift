//
//  Models.swift
//  PaperCue
//
//  Created by Codex on 2026/5/11.
//

import Foundation
import SwiftData

let paperCueSchema = Schema([
    ReadingDocument.self,
    GeneratedStudyPack.self,
    GlossaryTerm.self,
    Flashcard.self,
    ReviewQuestion.self,
])

enum DocumentSourceKind: String, Codable, CaseIterable {
    case pdf
    case web
    case text

    var title: String {
        switch self {
        case .pdf:
            "PDF"
        case .web:
            "Web"
        case .text:
            "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf:
            "doc.richtext"
        case .web:
            "globe"
        case .text:
            "doc.plaintext"
        }
    }
}

enum StudyPackGenerationProfile: String, Codable, CaseIterable, Identifiable {
    case deepReading
    case examReview
    case seminar
    case ankiFocus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepReading:
            "精读"
        case .examReview:
            "复习"
        case .seminar:
            "讨论"
        case .ankiFocus:
            "Anki"
        }
    }

    var promptInstruction: String {
        switch self {
        case .deepReading:
            "偏重论文主线、概念关系、证据链、方法选择和局限，适合完整精读。"
        case .examReview:
            "偏重可考点、关键定义、对比关系和容易混淆的结论，答案要便于快速复习。"
        case .seminar:
            "偏重可讨论的问题、争议点、假设、外部有效性和后续研究方向。"
        case .ankiFocus:
            "偏重高质量主动回忆卡片；卡片正面应具体、可回答，背面应短而完整，避免宽泛问题。"
        }
    }
}

enum StudyPackModule: String, Codable, CaseIterable, Identifiable, Hashable {
    case summary
    case glossary
    case flashcards
    case questions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary:
            "摘要"
        case .glossary:
            "术语"
        case .flashcards:
            "卡片"
        case .questions:
            "问题"
        }
    }

    var systemImage: String {
        switch self {
        case .summary:
            "text.alignleft"
        case .glossary:
            "character.book.closed"
        case .flashcards:
            "rectangle.on.rectangle"
        case .questions:
            "questionmark.bubble"
        }
    }
}

struct StudyPackGenerationOptions: Codable, Equatable {
    var enabledModules: [StudyPackModule]
    var customPrompt: String

    init(
        enabledModules: [StudyPackModule] = StudyPackModule.allCases,
        customPrompt: String = ""
    ) {
        self.enabledModules = enabledModules
        self.customPrompt = customPrompt
    }

    var enabledModuleSet: Set<StudyPackModule> {
        Set(enabledModules)
    }

    var orderedEnabledModules: [StudyPackModule] {
        let enabled = enabledModuleSet
        return StudyPackModule.allCases.filter { enabled.contains($0) }
    }

    func includes(_ module: StudyPackModule) -> Bool {
        enabledModuleSet.contains(module)
    }
}

enum GenerationStatus: String, Codable, CaseIterable {
    case idle
    case extracting
    case ready
    case generating
    case completed
    case failed

    var title: String {
        switch self {
        case .idle:
            "待导入"
        case .extracting:
            "提取中"
        case .ready:
            "可生成"
        case .generating:
            "生成中"
        case .completed:
            "已完成"
        case .failed:
            "需要处理"
        }
    }
}

@Model
final class ReadingDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var sourceKindRaw: String
    var sourceURLString: String?
    var storedFileName: String?
    var importedAt: Date
    var updatedAt: Date
    var extractedText: String
    var textPreview: String
    var generationStatusRaw: String
    var errorMessage: String?
    @Relationship(deleteRule: .cascade) var studyPack: GeneratedStudyPack?

    init(
        id: UUID = UUID(),
        title: String,
        sourceKind: DocumentSourceKind,
        sourceURL: URL? = nil,
        storedFileName: String? = nil,
        importedAt: Date = Date(),
        extractedText: String,
        status: GenerationStatus = .ready,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title
        self.sourceKindRaw = sourceKind.rawValue
        self.sourceURLString = sourceURL?.absoluteString
        self.storedFileName = storedFileName
        self.importedAt = importedAt
        self.updatedAt = importedAt
        self.extractedText = extractedText
        self.textPreview = Self.makePreview(from: extractedText)
        self.generationStatusRaw = status.rawValue
        self.errorMessage = errorMessage
    }

    var sourceKind: DocumentSourceKind {
        get { DocumentSourceKind(rawValue: sourceKindRaw) ?? .pdf }
        set { sourceKindRaw = newValue.rawValue }
    }

    var sourceURL: URL? {
        guard let sourceURLString else { return nil }
        return URL(string: sourceURLString)
    }

    var generationStatus: GenerationStatus {
        get { GenerationStatus(rawValue: generationStatusRaw) ?? .idle }
        set {
            generationStatusRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    func refreshExtractedText(_ text: String) {
        extractedText = text
        textPreview = Self.makePreview(from: text)
        updatedAt = Date()
    }

    static func makePreview(from text: String, maxLength: Int = 420) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > maxLength else { return collapsed }
        let index = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<index]) + "..."
    }
}

@Model
final class GeneratedStudyPack {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var summaryOneSentence: String
    var summaryKeyPoints: [String]
    var summaryMethodOrArgument: String
    var summaryLimitations: String
    @Relationship(deleteRule: .cascade) var glossary: [GlossaryTerm]
    @Relationship(deleteRule: .cascade) var flashcards: [Flashcard]
    @Relationship(deleteRule: .cascade) var questions: [ReviewQuestion]

    init(id: UUID = UUID(), createdAt: Date = Date(), payload: GeneratedStudyPackPayload) {
        self.id = id
        self.createdAt = createdAt
        self.summaryOneSentence = payload.summary.oneSentence
        self.summaryKeyPoints = payload.summary.keyPoints
        self.summaryMethodOrArgument = payload.summary.methodOrArgument
        self.summaryLimitations = payload.summary.limitations
        self.glossary = payload.glossary.map(GlossaryTerm.init(payload:))
        self.flashcards = payload.flashcards.map(Flashcard.init(payload:))
        self.questions = payload.questions.map(ReviewQuestion.init(payload:))
    }

    var summaryPayload: StudySummaryPayload {
        StudySummaryPayload(
            oneSentence: summaryOneSentence,
            keyPoints: summaryKeyPoints,
            methodOrArgument: summaryMethodOrArgument,
            limitations: summaryLimitations
        )
    }

    var hasSummaryContent: Bool {
        !summaryOneSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || summaryKeyPoints.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !summaryMethodOrArgument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !summaryLimitations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@Model
final class GlossaryTerm {
    @Attribute(.unique) var id: UUID
    var term: String
    var originalTerm: String
    var explanation: String
    var context: String

    init(id: UUID = UUID(), term: String, originalTerm: String, explanation: String, context: String) {
        self.id = id
        self.term = term
        self.originalTerm = originalTerm
        self.explanation = explanation
        self.context = context
    }

    convenience init(payload: GlossaryTermPayload) {
        self.init(
            term: payload.term,
            originalTerm: payload.originalTerm,
            explanation: payload.explanation,
            context: payload.context
        )
    }
}

@Model
final class Flashcard {
    @Attribute(.unique) var id: UUID
    var front: String
    var back: String
    var tags: [String]
    var sourceQuote: String

    init(id: UUID = UUID(), front: String, back: String, tags: [String], sourceQuote: String) {
        self.id = id
        self.front = front
        self.back = back
        self.tags = tags
        self.sourceQuote = sourceQuote
    }

    convenience init(payload: FlashcardPayload) {
        self.init(
            front: payload.front,
            back: payload.back,
            tags: payload.tags,
            sourceQuote: payload.sourceQuote
        )
    }
}

@Model
final class ReviewQuestion {
    @Attribute(.unique) var id: UUID
    var question: String
    var purpose: String
    var relatedSection: String

    init(id: UUID = UUID(), question: String, purpose: String, relatedSection: String) {
        self.id = id
        self.question = question
        self.purpose = purpose
        self.relatedSection = relatedSection
    }

    convenience init(payload: ReviewQuestionPayload) {
        self.init(
            question: payload.question,
            purpose: payload.purpose,
            relatedSection: payload.relatedSection
        )
    }
}

struct ExtractedPageText: Codable, Equatable {
    var pageNumber: Int
    var text: String
    var isOCR: Bool
}

struct ExtractedDocumentText: Codable, Equatable {
    var title: String
    var text: String
    var sourceURL: URL?
    var sourceKind: DocumentSourceKind
    var pages: [ExtractedPageText]

    init(
        title: String,
        text: String,
        sourceURL: URL?,
        sourceKind: DocumentSourceKind,
        pages: [ExtractedPageText] = []
    ) {
        self.title = title
        self.text = text
        self.sourceURL = sourceURL
        self.sourceKind = sourceKind
        self.pages = pages
    }
}

struct GenerateStudyPackInput: Equatable {
    var title: String
    var sourceKind: DocumentSourceKind
    var sourceURL: URL?
    var text: String
    var generationProfile: StudyPackGenerationProfile = .deepReading
    var options: StudyPackGenerationOptions = StudyPackGenerationOptions()
    var outputLanguage: String = "中文为主，专业术语保留英文原词并附中文解释"
    var taskInstruction: String?
}

struct GeneratedStudyPackPayload: Codable, Equatable {
    var summary: StudySummaryPayload
    var glossary: [GlossaryTermPayload]
    var flashcards: [FlashcardPayload]
    var questions: [ReviewQuestionPayload]

    init(
        summary: StudySummaryPayload,
        glossary: [GlossaryTermPayload],
        flashcards: [FlashcardPayload],
        questions: [ReviewQuestionPayload]
    ) {
        self.summary = summary
        self.glossary = glossary
        self.flashcards = flashcards
        self.questions = questions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        summary = (try? container.decode(StudySummaryPayload.self, forAnyKey: ["summary"])) ?? .empty
        glossary = try container.decodeIfPresent([GlossaryTermPayload].self, forAnyKey: ["glossary", "terms", "terminology"]) ?? []
        flashcards = try container.decodeIfPresent([FlashcardPayload].self, forAnyKey: ["flashcards", "ankiCards", "anki_cards", "cards"]) ?? []
        questions = try container.decodeIfPresent([ReviewQuestionPayload].self, forAnyKey: ["questions", "reviewQuestions", "review_questions"]) ?? []
    }
}

struct StudySummaryPayload: Codable, Equatable {
    var oneSentence: String
    var keyPoints: [String]
    var methodOrArgument: String
    var limitations: String

    init(oneSentence: String, keyPoints: [String], methodOrArgument: String, limitations: String) {
        self.oneSentence = oneSentence
        self.keyPoints = keyPoints
        self.methodOrArgument = methodOrArgument
        self.limitations = limitations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        oneSentence = try container.decodeStringIfPresent(forAnyKey: ["oneSentence", "one_sentence", "overview"]) ?? ""
        keyPoints = try container.decodeStringArrayIfPresent(forAnyKey: ["keyPoints", "key_points", "points", "bulletPoints", "bullet_points"]) ?? []
        methodOrArgument = try container.decodeStringIfPresent(forAnyKey: ["methodOrArgument", "method_or_argument", "method", "argument"]) ?? ""
        limitations = try container.decodeStringIfPresent(forAnyKey: ["limitations", "limits"]) ?? ""
    }
}

extension StudySummaryPayload {
    static let empty = StudySummaryPayload(
        oneSentence: "",
        keyPoints: [],
        methodOrArgument: "",
        limitations: ""
    )
}

struct GlossaryTermPayload: Codable, Equatable {
    var term: String
    var originalTerm: String
    var explanation: String
    var context: String

    init(term: String, originalTerm: String, explanation: String, context: String) {
        self.term = term
        self.originalTerm = originalTerm
        self.explanation = explanation
        self.context = context
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        let decodedTerm = try container.decodeStringIfPresent(forAnyKey: ["term", "name", "concept"]) ?? ""
        let decodedOriginalTerm = try container.decodeStringIfPresent(forAnyKey: ["originalTerm", "original_term", "englishTerm", "english_term", "original"]) ?? ""
        term = decodedTerm.isEmpty ? decodedOriginalTerm : decodedTerm
        originalTerm = decodedOriginalTerm.isEmpty ? term : decodedOriginalTerm
        explanation = try container.decodeString(forAnyKey: ["explanation", "definition", "description"])
        context = try container.decodeStringIfPresent(forAnyKey: ["context", "sourceContext", "source_context", "section"]) ?? ""
    }
}

struct FlashcardPayload: Codable, Equatable {
    var front: String
    var back: String
    var tags: [String]
    var sourceQuote: String

    init(front: String, back: String, tags: [String], sourceQuote: String) {
        self.front = front
        self.back = back
        self.tags = tags
        self.sourceQuote = sourceQuote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        front = try container.decodeString(forAnyKey: ["front", "question", "prompt"])
        back = try container.decodeString(forAnyKey: ["back", "answer", "response"])
        tags = try container.decodeStringArrayIfPresent(forAnyKey: ["tags", "tag"]) ?? []
        sourceQuote = try container.decodeStringIfPresent(forAnyKey: ["sourceQuote", "source_quote", "quote", "evidence", "source"]) ?? ""
    }
}

struct ReviewQuestionPayload: Codable, Equatable {
    var question: String
    var purpose: String
    var relatedSection: String

    init(question: String, purpose: String, relatedSection: String) {
        self.question = question
        self.purpose = purpose
        self.relatedSection = relatedSection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        question = try container.decodeString(forAnyKey: ["question", "prompt"])
        purpose = try container.decodeStringIfPresent(forAnyKey: ["purpose", "rationale", "why"]) ?? ""
        relatedSection = try container.decodeStringIfPresent(forAnyKey: ["relatedSection", "related_section", "section", "source"]) ?? ""
    }
}

private struct FlexibleCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == FlexibleCodingKey {
    func decode<T: Decodable>(_ type: T.Type, forAnyKey keyNames: [String]) throws -> T {
        for keyName in keyNames {
            let key = FlexibleCodingKey(keyName)
            guard contains(key) else { continue }
            return try decode(T.self, forKey: key)
        }

        throw DecodingError.keyNotFound(
            FlexibleCodingKey(keyNames.first ?? ""),
            DecodingError.Context(codingPath: codingPath, debugDescription: "Expected one of: \(keyNames.joined(separator: ", "))")
        )
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forAnyKey keyNames: [String]) throws -> T? {
        for keyName in keyNames {
            let key = FlexibleCodingKey(keyName)
            guard contains(key) else { continue }
            return try decodeIfPresent(T.self, forKey: key)
        }

        return nil
    }

    func decodeString(forAnyKey keyNames: [String]) throws -> String {
        if let value = try decodeStringIfPresent(forAnyKey: keyNames), !value.isEmpty {
            return value
        }

        throw DecodingError.keyNotFound(
            FlexibleCodingKey(keyNames.first ?? ""),
            DecodingError.Context(codingPath: codingPath, debugDescription: "Expected non-empty string for one of: \(keyNames.joined(separator: ", "))")
        )
    }

    func decodeStringIfPresent(forAnyKey keyNames: [String]) throws -> String? {
        for keyName in keyNames {
            let key = FlexibleCodingKey(keyName)
            guard contains(key) else { continue }

            if let value = try? decode(String.self, forKey: key) {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let values = try? decode([String].self, forKey: key) {
                return values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            }

            if let value = try? decode(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? decode(Double.self, forKey: key) {
                return String(value)
            }
        }

        return nil
    }

    func decodeStringArray(forAnyKey keyNames: [String]) throws -> [String] {
        if let values = try decodeStringArrayIfPresent(forAnyKey: keyNames), !values.isEmpty {
            return values
        }

        throw DecodingError.keyNotFound(
            FlexibleCodingKey(keyNames.first ?? ""),
            DecodingError.Context(codingPath: codingPath, debugDescription: "Expected non-empty string array for one of: \(keyNames.joined(separator: ", "))")
        )
    }

    func decodeStringArrayIfPresent(forAnyKey keyNames: [String]) throws -> [String]? {
        for keyName in keyNames {
            let key = FlexibleCodingKey(keyName)
            guard contains(key) else { continue }

            if let values = try? decode([String].self, forKey: key) {
                return values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }

            if let value = try? decode(String.self, forKey: key) {
                return value
                    .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == ";" || $0 == "；" || $0.isNewline })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }

        return nil
    }
}

extension GeneratedStudyPackPayload {
    static var sample: GeneratedStudyPackPayload {
        GeneratedStudyPackPayload(
            summary: StudySummaryPayload(
                oneSentence: "本文解释了一个研究主题的核心问题、方法和结论。",
                keyPoints: [
                    "研究问题聚焦在可验证的机制或现象。",
                    "作者用实验或论证支持主要结论。",
                    "阅读时应关注假设、证据链和局限。"
                ],
                methodOrArgument: "作者先界定问题，再给出方法、结果和解释。",
                limitations: "样本、场景或外部有效性可能限制结论推广。"
            ),
            glossary: [
                GlossaryTermPayload(
                    term: "核心概念",
                    originalTerm: "Key concept",
                    explanation: "理解全文论证时必须掌握的基础概念。",
                    context: "通常出现在摘要、引言或方法部分。"
                )
            ],
            flashcards: [
                FlashcardPayload(
                    front: "这篇文章最重要的问题是什么？",
                    back: "识别研究问题、方法和主要结论之间的关系。",
                    tags: ["PaperCue", "summary"],
                    sourceQuote: "示例摘录"
                )
            ],
            questions: [
                ReviewQuestionPayload(
                    question: "作者的关键证据是否足以支持结论？",
                    purpose: "检查论证强度",
                    relatedSection: "结果与讨论"
                )
            ]
        )
    }
}
