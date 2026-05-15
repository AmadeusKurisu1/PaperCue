//
//  FullTextReaderView.swift
//  PaperCue
//
//  Created by Codex on 2026/5/12.
//

import Foundation
import SwiftUI

struct DocumentTextBlock: Identifiable, Equatable {
    var id: String
    var pageNumber: Int?
    var startsPage: Bool
    var text: String
}

enum DocumentTextBlockParser {
    private static let maxBlockLength = 2_400

    static func blocks(from text: String, sourceKind: DocumentSourceKind? = nil) -> [DocumentTextBlock] {
        let normalized = normalizeText(text)
        guard !normalized.isEmpty else { return [] }

        var index = 0
        return pageSections(in: normalized).flatMap { section in
            paragraphBlocks(
                from: section.text,
                pageNumber: section.pageNumber,
                nextIndex: &index
            )
        }
    }

    static func bestBlockID(matching reference: SourceReference, in blocks: [DocumentTextBlock]) -> DocumentTextBlock.ID? {
        let pageFilteredBlocks: [DocumentTextBlock]
        if reference.pageNumbers.isEmpty {
            pageFilteredBlocks = blocks
        } else {
            pageFilteredBlocks = blocks.filter { block in
                guard let pageNumber = block.pageNumber else { return false }
                return reference.pageNumbers.contains(pageNumber)
            }
        }

        let candidates = pageFilteredBlocks.isEmpty ? blocks : pageFilteredBlocks
        let quote = reference.quote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !quote.isEmpty {
            for term in candidateSearchTerms(from: quote) {
                if let block = candidates.first(where: { $0.text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
                    return block.id
                }
            }
        }

        return candidates.first?.id
    }

    private static func pageSections(in text: String) -> [(pageNumber: Int?, text: String)] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\s*Page\s+(\d+)\s*\]"#, options: [.caseInsensitive]) else {
            return [(nil, text)]
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else {
            return [(nil, text)]
        }

        var sections: [(pageNumber: Int?, text: String)] = []

        if let firstRange = Range(matches[0].range, in: text), firstRange.lowerBound > text.startIndex {
            let prefix = String(text[text.startIndex..<firstRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                sections.append((nil, prefix))
            }
        }

        for (matchIndex, match) in matches.enumerated() {
            guard let markerRange = Range(match.range, in: text) else { continue }
            let nextStart = matchIndex + 1 < matches.count
                ? Range(matches[matchIndex + 1].range, in: text)?.lowerBound ?? text.endIndex
                : text.endIndex
            let content = String(text[markerRange.upperBound..<nextStart]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }

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

    private static func paragraphBlocks(
        from text: String,
        pageNumber: Int?,
        nextIndex: inout Int
    ) -> [DocumentTextBlock] {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sourceParagraphs = paragraphs.isEmpty ? [text] : paragraphs
        var blocks: [DocumentTextBlock] = []
        var isFirstBlockOnPage = true

        for paragraph in sourceParagraphs {
            for chunk in splitLongText(paragraph) {
                blocks.append(
                    DocumentTextBlock(
                        id: "reader-block-\(nextIndex)",
                        pageNumber: pageNumber,
                        startsPage: pageNumber != nil && isFirstBlockOnPage,
                        text: chunk
                    )
                )
                nextIndex += 1
                isFirstBlockOnPage = false
            }
        }

        return blocks
    }

    private static func splitLongText(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxBlockLength else { return [trimmed] }

        let preferredBreaks: Set<Character> = ["\n", ".", "。", "!", "！", "?", "？", ";", "；"]
        var chunks: [String] = []
        var remaining = trimmed

        while remaining.count > maxBlockLength {
            let target = remaining.index(remaining.startIndex, offsetBy: maxBlockLength)
            let head = remaining[..<target]
            let preferredIndex = head.indices.last { preferredBreaks.contains(head[$0]) }

            let splitIndex: String.Index
            if let preferredIndex,
               remaining.distance(from: remaining.startIndex, to: preferredIndex) > maxBlockLength / 2 {
                splitIndex = remaining.index(after: preferredIndex)
            } else {
                splitIndex = target
            }

            let chunk = String(remaining[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
            remaining = String(remaining[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !remaining.isEmpty {
            chunks.append(remaining)
        }

        return chunks
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

struct FullTextReaderView: View {
    var document: ReadingDocument
    var initialReference: SourceReference?

    private let blocks: [DocumentTextBlock]
    @State private var searchText = ""
    @State private var selectedMatchIndex = 0
    @State private var focusedBlockID: DocumentTextBlock.ID?
    @State private var didScrollToInitialReference = false

    init(document: ReadingDocument, initialReference: SourceReference? = nil) {
        self.document = document
        self.initialReference = initialReference
        self.blocks = DocumentTextBlockParser.blocks(from: document.extractedText, sourceKind: document.sourceKind)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    readerHeader

                    if blocks.isEmpty {
                        ContentUnavailableView {
                            Label("没有可显示的全文", systemImage: "doc.text.magnifyingglass")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(blocks) { block in
                            VStack(alignment: .leading, spacing: 10) {
                                if block.startsPage, let pageNumber = block.pageNumber {
                                    PageDivider(pageNumber: pageNumber)
                                }

                                ReaderTextBlockView(
                                    block: block,
                                    isFocused: block.id == activeFocusedBlockID
                                )
                                .id(block.id)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .navigationTitle("全文")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索全文")
            .toolbar {
                searchToolbar(proxy: proxy)
            }
            .onAppear {
                scrollToInitialReferenceIfNeeded(proxy)
            }
            .onChange(of: searchText) { _, _ in
                selectedMatchIndex = 0
                scrollToCurrentSearchMatch(proxy)
            }
        }
    }

    private var readerHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(document.title.paperCueBreakableText())
                .font(.title2.weight(.semibold))
                .lineLimit(4)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Label(document.sourceKind.title, systemImage: document.sourceKind.systemImage)

                Text("\(document.extractedText.count.formatted()) 字")

                if pageCount > 0 {
                    Text("\(pageCount.formatted()) 页")
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var pageCount: Int {
        Set(blocks.compactMap(\.pageNumber)).count
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchMatchIDs: [DocumentTextBlock.ID] {
        guard !trimmedSearchText.isEmpty else { return [] }
        return blocks
            .filter { $0.text.range(of: trimmedSearchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .map(\.id)
    }

    private var activeFocusedBlockID: DocumentTextBlock.ID? {
        currentSearchMatchID ?? focusedBlockID
    }

    private var currentSearchMatchID: DocumentTextBlock.ID? {
        let matchIDs = searchMatchIDs
        guard !matchIDs.isEmpty else { return nil }
        let index = min(max(selectedMatchIndex, 0), matchIDs.count - 1)
        return matchIDs[index]
    }

    private var searchStatusText: String {
        guard !trimmedSearchText.isEmpty else { return "" }
        let count = searchMatchIDs.count
        guard count > 0 else { return "0 个匹配" }
        return "\(min(selectedMatchIndex + 1, count)) / \(count)"
    }

    @ToolbarContentBuilder
    private func searchToolbar(proxy: ScrollViewProxy) -> some ToolbarContent {
        if !trimmedSearchText.isEmpty {
            ToolbarItemGroup(placement: .bottomBar) {
                Text(searchStatusText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    moveSearch(by: -1, proxy: proxy)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(searchMatchIDs.isEmpty)
                .accessibilityLabel("上一个匹配")

                Button {
                    moveSearch(by: 1, proxy: proxy)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(searchMatchIDs.isEmpty)
                .accessibilityLabel("下一个匹配")
            }
        }
    }

    private func moveSearch(by offset: Int, proxy: ScrollViewProxy) {
        let matchIDs = searchMatchIDs
        guard !matchIDs.isEmpty else { return }
        selectedMatchIndex = (selectedMatchIndex + offset + matchIDs.count) % matchIDs.count
        scrollToCurrentSearchMatch(proxy)
    }

    private func scrollToCurrentSearchMatch(_ proxy: ScrollViewProxy) {
        guard let id = currentSearchMatchID else {
            focusedBlockID = nil
            return
        }

        focusedBlockID = id
        withAnimation(.snappy) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func scrollToInitialReferenceIfNeeded(_ proxy: ScrollViewProxy) {
        guard !didScrollToInitialReference else { return }
        didScrollToInitialReference = true

        guard let initialReference,
              let id = DocumentTextBlockParser.bestBlockID(matching: initialReference, in: blocks) else {
            return
        }

        focusedBlockID = id
        withAnimation(.snappy) {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

private struct ReaderTextBlockView: View {
    var block: DocumentTextBlock
    var isFocused: Bool

    var body: some View {
        Text(block.text.paperCueBreakableText(maxRunLength: 22))
            .font(.body)
            .lineSpacing(5)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, isFocused ? 10 : 0)
            .padding(.vertical, isFocused ? 8 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }
            }
    }
}

private struct PageDivider: View {
    var pageNumber: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("Page \(pageNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(Color.secondary.opacity(0.22))
                .frame(height: 1)
        }
        .padding(.top, 8)
    }
}
