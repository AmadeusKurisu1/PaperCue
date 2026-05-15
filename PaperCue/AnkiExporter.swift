//
//  AnkiExporter.swift
//  PaperCue
//
//  Created by Codex on 2026/5/11.
//

import Foundation

struct AnkiExporter {
    func export(cards: [Flashcard], sourceTitle: String) throws -> URL {
        guard !cards.isEmpty else {
            throw PaperCueError.exportFailed
        }

        let safeTitle = safeFileName(from: sourceTitle)
        let fileName = "\(safeTitle.isEmpty ? "PaperCue" : safeTitle)-Anki.tsv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let header = ["Front", "Back", "Tags", "Source"].joined(separator: "\t")
        let rows = cards.map { card in
            [
                sanitizeTSVField(card.front),
                sanitizeTSVField(card.back),
                sanitizeTSVField((card.tags + ["PaperCue"]).uniqued().joined(separator: " ")),
                sanitizeTSVField(sourceTitle)
            ].joined(separator: "\t")
        }

        let content = ([header] + rows).joined(separator: "\n")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

enum StudyPackExportFormat: String, CaseIterable, Identifiable {
    case anki
    case markdown
    case json
    case csv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anki:
            "Anki TSV"
        case .markdown:
            "Markdown"
        case .json:
            "JSON"
        case .csv:
            "CSV"
        }
    }

    var fileExtension: String {
        switch self {
        case .anki:
            "tsv"
        case .markdown:
            "md"
        case .json:
            "json"
        case .csv:
            "csv"
        }
    }
}

struct StudyPackExporter {
    func export(studyPack: GeneratedStudyPack, sourceTitle: String, format: StudyPackExportFormat) throws -> URL {
        switch format {
        case .anki:
            return try AnkiExporter().export(cards: studyPack.flashcards, sourceTitle: sourceTitle)
        case .markdown:
            return try write(content: markdown(studyPack: studyPack, sourceTitle: sourceTitle), sourceTitle: sourceTitle, suffix: "StudyPack", format: format)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(studyPack.payload)
            guard let content = String(data: data, encoding: .utf8) else {
                throw PaperCueError.exportFailed
            }
            return try write(content: content, sourceTitle: sourceTitle, suffix: "StudyPack", format: format)
        case .csv:
            return try write(content: csv(studyPack: studyPack, sourceTitle: sourceTitle), sourceTitle: sourceTitle, suffix: "StudyPack", format: format)
        }
    }

    private func write(content: String, sourceTitle: String, suffix: String, format: StudyPackExportFormat) throws -> URL {
        let safeTitle = safeFileName(from: sourceTitle)
        let fileName = "\(safeTitle.isEmpty ? "PaperCue" : safeTitle)-\(suffix).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func markdown(studyPack: GeneratedStudyPack, sourceTitle: String) -> String {
        var lines: [String] = [
            "# \(sourceTitle)",
            "",
            "## 一句话概括",
            studyPack.summaryOneSentence,
            "",
            "## 关键点"
        ]
        lines += studyPack.summaryKeyPoints.map { "- \($0)" }
        lines += [
            "",
            "## 方法或论证",
            studyPack.summaryMethodOrArgument,
            "",
            "## 局限",
            studyPack.summaryLimitations,
            "",
            "## 术语"
        ]
        for term in studyPack.glossary {
            lines += [
                "- **\(term.term)** (\(term.originalTerm)): \(term.explanation)"
            ]
            if !term.context.isEmpty {
                lines.append("  - 来源：\(term.context)")
            }
        }
        lines += ["", "## Anki 卡片"]
        for card in studyPack.flashcards {
            lines += [
                "- Q: \(card.front)",
                "  A: \(card.back)"
            ]
            if !card.sourceQuote.isEmpty {
                lines.append("  来源：\(card.sourceQuote)")
            }
        }
        lines += ["", "## 提问清单"]
        for question in studyPack.questions {
            lines.append("- \(question.question) - \(question.purpose)")
            if !question.relatedSection.isEmpty {
                lines.append("  - 来源：\(question.relatedSection)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func csv(studyPack: GeneratedStudyPack, sourceTitle: String) -> String {
        var rows = [
            ["Type", "FrontOrTitle", "BackOrContent", "Tags", "Source"].map(csvField).joined(separator: ",")
        ]

        rows.append(["Summary", "One sentence", studyPack.summaryOneSentence, "", sourceTitle].map(csvField).joined(separator: ","))
        rows.append(["Summary", "Method or argument", studyPack.summaryMethodOrArgument, "", sourceTitle].map(csvField).joined(separator: ","))
        rows.append(["Summary", "Limitations", studyPack.summaryLimitations, "", sourceTitle].map(csvField).joined(separator: ","))
        for point in studyPack.summaryKeyPoints {
            rows.append(["Key point", point, "", "", sourceTitle].map(csvField).joined(separator: ","))
        }
        for term in studyPack.glossary {
            rows.append(["Glossary", term.term, term.explanation, term.originalTerm, term.context].map(csvField).joined(separator: ","))
        }
        for card in studyPack.flashcards {
            rows.append(["Flashcard", card.front, card.back, card.tags.joined(separator: " "), card.sourceQuote].map(csvField).joined(separator: ","))
        }
        for question in studyPack.questions {
            rows.append(["Question", question.question, question.purpose, "", question.relatedSection].map(csvField).joined(separator: ","))
        }

        return rows.joined(separator: "\n")
    }
}

extension GeneratedStudyPack {
    var payload: GeneratedStudyPackPayload {
        GeneratedStudyPackPayload(
            summary: summaryPayload,
            glossary: glossary.map {
                GlossaryTermPayload(
                    term: $0.term,
                    originalTerm: $0.originalTerm,
                    explanation: $0.explanation,
                    context: $0.context
                )
            },
            flashcards: flashcards.map {
                FlashcardPayload(
                    front: $0.front,
                    back: $0.back,
                    tags: $0.tags,
                    sourceQuote: $0.sourceQuote
                )
            },
            questions: questions.map {
                ReviewQuestionPayload(
                    question: $0.question,
                    purpose: $0.purpose,
                    relatedSection: $0.relatedSection
                )
            }
        )
    }
}

func safeFileName(from title: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
    let pieces = title.unicodeScalars.map { scalar in
        allowed.contains(scalar) ? String(scalar) : "-"
    }

    return pieces.joined()
        .replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

func sanitizeTSVField(_ field: String) -> String {
    field
        .replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\r\n", with: "<br>")
        .replacingOccurrences(of: "\n", with: "<br>")
        .replacingOccurrences(of: "\r", with: "<br>")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func csvField(_ field: String) -> String {
    let escaped = field
        .replacingOccurrences(of: "\"", with: "\"\"")
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    return "\"\(escaped)\""
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
