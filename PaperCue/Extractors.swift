//
//  Extractors.swift
//  PaperCue
//
//  Created by Codex on 2026/5/11.
//

import Foundation
import PDFKit
import UIKit
@preconcurrency import Vision

struct DocumentTextExtractor {
    var minimumPageTextLengthForOCR = 40
    var ocrRecognizer: any PDFPageTextRecognizing = VisionPDFPageTextRecognizer()

    func extract(from url: URL) async throws -> ExtractedDocumentText {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let pdf = PDFDocument(url: url) else {
            throw PaperCueError.emptyExtractedText
        }

        var pages: [ExtractedPageText] = []
        var ocrErrors: [String] = []

        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else {
                continue
            }

            let directText = normalizeText(page.string ?? "")
            if !shouldUseOCR(for: directText) {
                pages.append(
                    ExtractedPageText(
                        pageNumber: pageIndex + 1,
                        text: directText,
                        isOCR: false
                    )
                )
                continue
            }

            do {
                let ocrText = normalizeText(try await ocrRecognizer.recognizeText(from: page))
                if !ocrText.isEmpty {
                    pages.append(
                        ExtractedPageText(
                            pageNumber: pageIndex + 1,
                            text: ocrText,
                            isOCR: true
                        )
                    )
                } else if !directText.isEmpty {
                    pages.append(
                        ExtractedPageText(
                            pageNumber: pageIndex + 1,
                            text: directText,
                            isOCR: false
                        )
                    )
                }
            } catch {
                ocrErrors.append(error.paperCueMessage)
                if !directText.isEmpty {
                    pages.append(
                        ExtractedPageText(
                            pageNumber: pageIndex + 1,
                            text: directText,
                            isOCR: false
                        )
                    )
                }
            }
        }

        let text = normalizeText(
            pages
                .map { "[Page \($0.pageNumber)]\n\($0.text)" }
                .joined(separator: "\n\n")
        )
        guard !text.isEmpty else {
            if let firstError = ocrErrors.first {
                throw PaperCueError.ocrFailed(message: firstError)
            }
            throw PaperCueError.emptyExtractedText
        }

        return ExtractedDocumentText(
            title: pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? url.deletingPathExtension().lastPathComponent,
            text: text,
            sourceURL: url,
            sourceKind: .pdf,
            pages: pages
        )
    }

    func shouldUseOCR(for text: String) -> Bool {
        normalizeText(text).count < minimumPageTextLengthForOCR
    }
}

protocol PDFPageTextRecognizing {
    func recognizeText(from page: PDFPage) async throws -> String
}

struct VisionPDFPageTextRecognizer: PDFPageTextRecognizing {
    func recognizeText(from page: PDFPage) async throws -> String {
        guard let image = renderImage(from: page),
              let cgImage = image.cgImage else {
            throw PaperCueError.ocrFailed(message: "无法渲染 PDF 页面。")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func renderImage(from page: PDFPage) -> UIImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return nil
        }

        let maxDimension: CGFloat = 2_200
        let scale = min(2, maxDimension / max(pageBounds.width, pageBounds.height))
        let size = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            context.cgContext.saveGState()
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.translateBy(x: 0, y: pageBounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }
}

struct WebArticleExtractor {
    func extract(from url: URL) async throws -> ExtractedDocumentText {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw PaperCueError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 PaperCue/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw PaperCueError.serverError(statusCode: httpResponse.statusCode, message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let title = extractMetadataTitle(from: html, url: url)
            ?? extractTitle(from: html)
            ?? url.host
            ?? url.absoluteString
        let extraction = extractArticleText(from: html)
        let text = normalizeText(extraction.text)

        guard !text.isEmpty else {
            throw PaperCueError.emptyExtractedText
        }
        guard !extraction.isLowConfidence else {
            throw PaperCueError.lowQualityWebContent
        }

        return ExtractedDocumentText(
            title: title,
            text: text,
            sourceURL: url,
            sourceKind: .web
        )
    }

    func extractTitle(from html: String) -> String? {
        guard let range = html.range(of: #"<title[^>]*>(.*?)</title>"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }

        return html[range]
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .htmlDecoded
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractMetadataTitle(from html: String, url: URL) -> String? {
        let metaNames = [
            "citation_title",
            "dc.title",
            "og:title",
            "twitter:title"
        ]

        for name in metaNames {
            if let content = metaContent(named: name, in: html), !content.isEmpty {
                return content
            }
        }

        return ImportURLNormalizer.metadataTitleFallback(for: url)
    }

    func extractVisibleText(from html: String) -> String {
        extractArticleText(from: html).text
    }

    func extractArticleText(from html: String) -> WebArticleExtractionResult {
        let cleaned = stripRemovableContent(from: html)
        let candidates = articleCandidates(from: cleaned)

        if let bestCandidate = candidates.max(by: { $0.score < $1.score }),
           bestCandidate.score > 0 {
            return WebArticleExtractionResult(
                text: htmlToVisibleText(bestCandidate.html),
                score: bestCandidate.score,
                linkDensity: bestCandidate.linkDensity
            )
        }

        let fallback = htmlToVisibleText(cleaned)
        return WebArticleExtractionResult(
            text: fallback,
            score: Double(fallback.count),
            linkDensity: linkDensity(in: cleaned)
        )
    }

    private func stripRemovableContent(from html: String) -> String {
        var cleaned = html
        let removablePatterns = [
            #"<script[\s\S]*?</script>"#,
            #"<style[\s\S]*?</style>"#,
            #"<noscript[\s\S]*?</noscript>"#,
            #"<svg[\s\S]*?</svg>"#,
            #"<nav[\s\S]*?</nav>"#,
            #"<header[\s\S]*?</header>"#,
            #"<footer[\s\S]*?</footer>"#
        ]

        for pattern in removablePatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }

        return cleaned
    }

    private func articleCandidates(from html: String) -> [WebArticleCandidate] {
        var candidates: [WebArticleCandidate] = []
        let preferredPatterns = [
            #"<article\b[^>]*>[\s\S]*?</article>"#,
            #"<main\b[^>]*>[\s\S]*?</main>"#,
            #"<section\b[^>]*>[\s\S]*?</section>"#
        ]

        for pattern in preferredPatterns {
            candidates.append(contentsOf: matches(for: pattern, in: html).map { candidate(from: $0, preferred: true) })
        }

        if let body = matches(for: #"<body\b[^>]*>[\s\S]*?</body>"#, in: html).first {
            candidates.append(candidate(from: body, preferred: false))
        } else {
            candidates.append(candidate(from: html, preferred: false))
        }

        return candidates
    }

    private func candidate(from html: String, preferred: Bool) -> WebArticleCandidate {
        let text = htmlToVisibleText(html)
        let density = linkDensity(in: html)
        let paragraphCount = matches(for: #"<p\b[^>]*>"#, in: html).count
        let headingCount = matches(for: #"<h[1-6]\b[^>]*>"#, in: html).count
        let preferredBoost = preferred ? 1.25 : 1
        let score = (Double(text.count) * max(0.05, 1 - density) + Double(paragraphCount * 220) + Double(headingCount * 80)) * preferredBoost

        return WebArticleCandidate(html: html, score: score, linkDensity: density)
    }

    private func htmlToVisibleText(_ html: String) -> String {
        return html
            .replacingOccurrences(of: #"<li\b[^>]*>"#, with: "\n- ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</(p|div|section|article|h[1-6]|li|br|tr)>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .htmlDecoded
    }

    private func linkDensity(in html: String) -> Double {
        let visible = htmlToVisibleText(html)
        guard !visible.isEmpty else { return 1 }

        let linkedTextCount = matches(for: #"<a\b[^>]*>[\s\S]*?</a>"#, in: html)
            .map { htmlToVisibleText($0).count }
            .reduce(0, +)

        return min(1, Double(linkedTextCount) / Double(visible.count))
    }

    private func matches(for pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }
            return String(text[range])
        }
    }

    private func metaContent(named name: String, in html: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            #"<meta\b(?=[^>]*(?:name|property)=["']"# + escapedName + #"["'])(?=[^>]*content=["']([^"']+)["'])[^>]*>"#,
            #"<meta\b(?=[^>]*content=["']([^"']+)["'])(?=[^>]*(?:name|property)=["']"# + escapedName + #"["'])[^>]*>"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  match.numberOfRanges > 1,
                  let contentRange = Range(match.range(at: 1), in: html) else {
                continue
            }

            return String(html[contentRange])
                .htmlDecoded
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }
}

struct WebArticleExtractionResult: Equatable {
    var text: String
    var score: Double
    var linkDensity: Double

    var isLowConfidence: Bool {
        normalizeText(text).count < 160 || linkDensity > 0.72
    }
}

private struct WebArticleCandidate {
    var html: String
    var score: Double
    var linkDensity: Double
}

func normalizeText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\u{00a0}", with: " ")
        .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

extension String {
    var htmlDecoded: String {
        guard let data = data(using: .utf8) else {
            return self
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        return (try? NSAttributedString(data: data, options: options, documentAttributes: nil).string) ?? self
    }
}
