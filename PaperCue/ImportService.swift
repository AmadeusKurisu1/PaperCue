//
//  ImportService.swift
//  PaperCue
//
//  Created by Codex on 2026/5/11.
//

import Foundation

struct ImportService {
    var pdfExtractor = DocumentTextExtractor()
    var webExtractor = WebArticleExtractor()
    var fileManager: FileManager = .default
    var extractionCache = DocumentExtractionCache()

    func importPDF(from sourceURL: URL) async throws -> ReadingDocument {
        let localURL = try copyImportedFile(from: sourceURL)
        let extracted: ExtractedDocumentText
        if let cached = extractionCache.cachedPDFExtraction(for: sourceURL) {
            extracted = cached
        } else {
            extracted = try await pdfExtractor.extract(from: localURL)
            try? extractionCache.storePDFExtraction(extracted, for: sourceURL)
        }

        return ReadingDocument(
            title: extracted.title,
            sourceKind: .pdf,
            sourceURL: sourceURL,
            storedFileName: localURL.lastPathComponent,
            extractedText: extracted.text
        )
    }

    func importWebPage(from url: URL) async throws -> ReadingDocument {
        let extracted: ExtractedDocumentText
        if let cached = extractionCache.cachedWebExtraction(for: url) {
            extracted = cached
        } else {
            extracted = try await webExtractor.extract(from: url)
            try? extractionCache.storeWebExtraction(extracted, for: url)
        }

        return ReadingDocument(
            title: extracted.title,
            sourceKind: .web,
            sourceURL: url,
            extractedText: extracted.text
        )
    }

    func importPastedText(title: String, text: String) throws -> ReadingDocument {
        let normalizedText = normalizePastedText(text)
        guard !normalizedText.isEmpty else {
            throw PaperCueError.emptyExtractedText
        }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReadingDocument(
            title: normalizedTitle.isEmpty ? "粘贴文本" : normalizedTitle,
            sourceKind: .text,
            extractedText: normalizedText
        )
    }

    private func normalizePastedText(_ text: String) -> String {
        normalizeText(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func copyImportedFile(from url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let directory = try importedDocumentsDirectory()
        let fileExtension = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
        let destination = directory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        try fileManager.copyItem(at: url, to: destination)
        return destination
    }

    func importedDocumentsDirectory() throws -> URL {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("ImportedDocuments", isDirectory: true)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

struct DocumentExtractionCache {
    var directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("PaperCue", isDirectory: true)
        .appendingPathComponent("ExtractionCache", isDirectory: true)
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("PaperCue-ExtractionCache", isDirectory: true)
    var fileManager: FileManager = .default

    func cachedWebExtraction(for url: URL) -> ExtractedDocumentText? {
        cache.value(forKey: cacheKey(kind: "web", source: url.absoluteString))
    }

    func storeWebExtraction(_ extraction: ExtractedDocumentText, for url: URL) throws {
        try cache.store(extraction, forKey: cacheKey(kind: "web", source: url.absoluteString))
    }

    func cachedPDFExtraction(for url: URL) -> ExtractedDocumentText? {
        cache.value(forKey: cacheKey(kind: "pdf", source: pdfSourceSignature(for: url)))
    }

    func storePDFExtraction(_ extraction: ExtractedDocumentText, for url: URL) throws {
        try cache.store(extraction, forKey: cacheKey(kind: "pdf", source: pdfSourceSignature(for: url)))
    }

    private var cache: JSONFileCache<ExtractedDocumentText> {
        JSONFileCache(directory: directory, fileManager: fileManager)
    }

    private func cacheKey(kind: String, source: String) -> String {
        StableCacheKey.key(for: [kind, source])
    }

    private func pdfSourceSignature(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return [
            url.path,
            values?.contentModificationDate?.timeIntervalSince1970.description ?? "",
            values?.fileSize.map(String.init) ?? ""
        ].joined(separator: "|")
    }
}
