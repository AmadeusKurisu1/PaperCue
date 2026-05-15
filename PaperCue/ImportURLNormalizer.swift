//
//  ImportURLNormalizer.swift
//  PaperCue
//
//  Created by Codex on 2026/5/12.
//

import Foundation

enum ImportURLNormalizer {
    static func normalizedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let doiURL = doiURL(from: trimmed) {
            return doiURL
        }

        if let arxivURL = arxivURL(from: trimmed) {
            return arxivURL
        }

        if let pubMedURL = pubMedURL(from: trimmed) {
            return pubMedURL
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }

        return url
    }

    static func metadataTitleFallback(for url: URL) -> String? {
        let absolute = url.absoluteString
        if let arxivID = arxivID(from: absolute) {
            return "arXiv \(arxivID)"
        }

        if let doi = doi(from: absolute) {
            return "DOI \(doi)"
        }

        if let pmid = pubMedID(from: absolute) {
            return "PubMed \(pmid)"
        }

        return nil
    }

    private static func doiURL(from text: String) -> URL? {
        guard let doi = doi(from: text) else { return nil }
        return URL(string: "https://doi.org/\(doi)")
    }

    private static func arxivURL(from text: String) -> URL? {
        guard let arxivID = arxivID(from: text) else { return nil }
        return URL(string: "https://arxiv.org/abs/\(arxivID)")
    }

    private static func pubMedURL(from text: String) -> URL? {
        guard let pmid = pubMedID(from: text) else { return nil }
        return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/")
    }

    private static func doi(from text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: "https://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://doi.org/", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "doi:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return firstMatch(#"10\.\d{4,9}/[-._;()/:A-Z0-9]+"#, in: normalized, options: [.caseInsensitive])
    }

    private static func arxivID(from text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: "arXiv:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let id = firstMatch(#"\d{4}\.\d{4,5}(v\d+)?"#, in: normalized, options: [.caseInsensitive]) {
            return id
        }

        return firstMatch(#"[a-z-]+(\.[A-Z]{2})?/\d{7}(v\d+)?"#, in: normalized, options: [.caseInsensitive])
    }

    private static func pubMedID(from text: String) -> String? {
        let normalized = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/")))
        if normalized.range(of: "pubmed", options: .caseInsensitive) != nil {
            return firstMatch(#"\b\d{6,9}\b"#, in: normalized)
        }

        if normalized.range(of: #"^pmid:\s*\d{6,9}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return firstMatch(#"\d{6,9}"#, in: normalized)
        }

        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }

        return String(text[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
