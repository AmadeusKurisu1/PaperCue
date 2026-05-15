//
//  SourceReference.swift
//  PaperCue
//
//  Created by Codex on 2026/5/12.
//

import Foundation

struct SourceReference: Equatable, Hashable, Identifiable {
    var id: String {
        let pagePart = pageNumbers.map(String.init).joined(separator: "-")
        return "\(pagePart)|\(quote)"
    }

    var pageNumbers: [Int]
    var quote: String

    var displayLabel: String {
        if !pageNumbers.isEmpty {
            return "来源：" + pageNumbers.map { "Page \($0)" }.joined(separator: ", ")
        }

        if quote.count <= 24 {
            return "来源：" + quote
        }

        return "来源：原文片段"
    }
}

struct ResolvedSourceReference: Equatable, Identifiable {
    var id = UUID()
    var reference: SourceReference
    var excerpt: String
    var pageLabel: String?
}

enum SourceReferenceExtractor {
    static func reference(in text: String, fallback: String = "原文片段") -> SourceReference? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pages = pageNumbers(in: trimmed)
        let quote = cleanedQuote(from: trimmed)
        if pages.isEmpty, quote.isEmpty {
            return SourceReference(pageNumbers: [], quote: fallback)
        }
        return SourceReference(pageNumbers: pages, quote: quote.isEmpty ? fallback : quote)
    }

    static func pageLabels(in text: String) -> [String] {
        pageNumbers(in: text).map { "Page \($0)" }
    }

    static func pageNumbers(in text: String) -> [Int] {
        let patterns = [
            #"\[\s*Page\s+(\d+)\s*\]"#,
            #"\bPage\s+(\d+)\b"#,
            #"第\s*(\d+)\s*页"#
        ]

        var seen = Set<Int>()
        var pages: [Int] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard match.numberOfRanges > 1,
                      let numberRange = Range(match.range(at: 1), in: text),
                      let page = Int(text[numberRange]),
                      seen.insert(page).inserted else {
                    continue
                }
                pages.append(page)
            }
        }

        return pages.sorted()
    }

    static func displayLabel(for text: String, fallback: String = "原文片段") -> String? {
        reference(in: text, fallback: fallback)?.displayLabel
    }

    static func cleanedQuote(from text: String) -> String {
        text
            .replacingOccurrences(of: #"\[\s*Page\s+\d+\s*\]"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bPage\s+\d+\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"第\s*\d+\s*页"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "：:，,。.;；-—\"'“”")))
    }
}

enum SourceReferenceResolver {
    static func resolve(referenceText: String, in documentText: String, excerptRadius: Int = 260) -> ResolvedSourceReference? {
        guard let reference = SourceReferenceExtractor.reference(in: referenceText) else {
            return nil
        }

        let pageSections = splitPages(in: documentText)
        let candidateSections = reference.pageNumbers.isEmpty
            ? pageSections
            : pageSections.filter { section in
                guard let pageNumber = section.pageNumber else { return false }
                return reference.pageNumbers.contains(pageNumber)
            }

        let sections = candidateSections.isEmpty ? pageSections : candidateSections
        let quote = reference.quote
        for section in sections {
            if let excerpt = excerpt(around: quote, in: section.text, radius: excerptRadius) {
                return ResolvedSourceReference(
                    reference: reference,
                    excerpt: excerpt,
                    pageLabel: section.pageNumber.map { "Page \($0)" }
                )
            }
        }

        guard let section = sections.first else { return nil }
        return ResolvedSourceReference(
            reference: reference,
            excerpt: String(section.text.prefix(excerptRadius * 2)).trimmingCharacters(in: .whitespacesAndNewlines),
            pageLabel: section.pageNumber.map { "Page \($0)" }
        )
    }

    private static func splitPages(in text: String) -> [(pageNumber: Int?, text: String)] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\s*Page\s+(\d+)\s*\]"#, options: [.caseInsensitive]) else {
            return [(nil, text)]
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        guard !matches.isEmpty else {
            return [(nil, text)]
        }

        var sections: [(Int?, String)] = []
        for (index, match) in matches.enumerated() {
            guard let markerRange = Range(match.range, in: text) else { continue }
            let nextStart = index + 1 < matches.count
                ? Range(matches[index + 1].range, in: text)?.lowerBound ?? text.endIndex
                : text.endIndex
            let contentStart = markerRange.upperBound
            let content = String(text[contentStart..<nextStart]).trimmingCharacters(in: .whitespacesAndNewlines)
            let pageNumber: Int?
            if match.numberOfRanges > 1,
               let numberRange = Range(match.range(at: 1), in: text) {
                pageNumber = Int(text[numberRange])
            } else {
                pageNumber = nil
            }
            sections.append((pageNumber, content))
        }

        return sections
    }

    private static func excerpt(around quote: String, in text: String, radius: Int) -> String? {
        let normalizedQuote = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuote.isEmpty else { return nil }

        let searchTerms = candidateSearchTerms(from: normalizedQuote)
        for term in searchTerms {
            if let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                let lower = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
                let upper = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
                return String(text[lower..<upper])
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    private static func candidateSearchTerms(from quote: String) -> [String] {
        let collapsed = quote.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard collapsed.count > 42 else { return [collapsed] }

        let prefix = String(collapsed.prefix(42)).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = collapsed.split(separator: " ")
        let firstWords = words.prefix(8).joined(separator: " ")
        return [collapsed, firstWords, prefix].filter { !$0.isEmpty }
    }
}
