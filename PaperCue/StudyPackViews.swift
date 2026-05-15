//
//  StudyPackViews.swift
//  PaperCue
//
//  Created by Codex on 2026/5/11.
//

import SwiftData
import SwiftUI

struct SummaryView: View {
    @Bindable var studyPack: GeneratedStudyPack
    var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudyPackSectionView(title: "一句话概括", systemImage: "quote.bubble") {
                if isEditing {
                    TextEditor(text: $studyPack.summaryOneSentence)
                        .frame(minHeight: 76)
                        .textEditorStyle()
                } else {
                    Text(studyPack.summaryOneSentence.paperCueBreakableText())
                        .font(.title3.weight(.medium))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            StudyPackSectionView(title: "关键点", systemImage: "list.bullet.rectangle") {
                if isEditing {
                    TextEditor(
                        text: Binding(
                            get: { studyPack.summaryKeyPoints.joined(separator: "\n") },
                            set: { text in
                                studyPack.summaryKeyPoints = text
                                    .components(separatedBy: .newlines)
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                            }
                        )
                    )
                    .frame(minHeight: 132)
                    .textEditorStyle()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(studyPack.summaryKeyPoints.enumerated()), id: \.offset) { _, point in
                            Label(point.paperCueBreakableText(), systemImage: "checkmark.circle")
                                .labelStyle(.titleAndIcon)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            StudyPackSectionView(title: "方法或论证", systemImage: "flowchart") {
                editableText($studyPack.summaryMethodOrArgument, minHeight: 112)
            }

            StudyPackSectionView(title: "局限", systemImage: "exclamationmark.magnifyingglass") {
                editableText($studyPack.summaryLimitations, minHeight: 92)
            }
        }
    }

    @ViewBuilder
    private func editableText(_ text: Binding<String>, minHeight: CGFloat) -> some View {
        if isEditing {
            TextEditor(text: text)
                .frame(minHeight: minHeight)
                .textEditorStyle()
        } else {
            Text(text.wrappedValue.paperCueBreakableText())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GlossaryView: View {
    var terms: [GlossaryTerm]
    var isEditing = false
    var onSourceSelected: ((String) -> Void)?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(terms) { term in
                GlossaryTermRow(term: term, isEditing: isEditing, onSourceSelected: onSourceSelected)
                Divider()
            }
        }
        .textSelection(.enabled)
    }
}

struct FlashcardsView: View {
    var cards: [Flashcard]
    var isEditing = false
    var onSourceSelected: ((String) -> Void)?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(cards) { card in
                FlashcardRow(card: card, isEditing: isEditing, onSourceSelected: onSourceSelected)
                Divider()
            }
        }
        .textSelection(.enabled)
    }
}

struct ReviewQuestionsView: View {
    var questions: [ReviewQuestion]
    var isEditing = false
    var onSourceSelected: ((String) -> Void)?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(questions) { item in
                ReviewQuestionRow(item: item, isEditing: isEditing, onSourceSelected: onSourceSelected)
                Divider()
            }
        }
        .textSelection(.enabled)
    }
}

private struct GlossaryTermRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var term: GlossaryTerm
    var isEditing: Bool
    var onSourceSelected: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                TextField("术语", text: $term.term)
                    .textFieldStyle(.roundedBorder)
                TextField("原文术语", text: $term.originalTerm)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $term.explanation)
                    .frame(minHeight: 86)
                    .textEditorStyle()
                TextField("来源或上下文", text: $term.context, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                DeleteInlineButton(title: "删除术语") {
                    modelContext.delete(term)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(term.term.paperCueBreakableText())
                        .font(.headline)
                    Text(term.originalTerm.paperCueBreakableText())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(term.explanation.paperCueBreakableText())
                    .fixedSize(horizontal: false, vertical: true)
                SourceReferenceChip(text: term.context, onSelect: onSourceSelected)
                if !term.context.isEmpty {
                    Text(term.context.paperCueBreakableText())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlashcardRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var card: Flashcard
    var isEditing: Bool
    var onSourceSelected: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditing {
                TextField("正面问题", text: $card.front, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $card.back)
                    .frame(minHeight: 96)
                    .textEditorStyle()
                TextField(
                    "标签，用空格分隔",
                    text: Binding(
                        get: { card.tags.joined(separator: " ") },
                        set: { text in
                            card.tags = text
                                .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" })
                                .map(String.init)
                                .filter { !$0.isEmpty }
                                .uniqued()
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                TextField("来源短句", text: $card.sourceQuote, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                DeleteInlineButton(title: "删除卡片") {
                    modelContext.delete(card)
                }
            } else {
                Label(card.front.paperCueBreakableText(), systemImage: "questionmark.circle")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Text(card.back.paperCueBreakableText())
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if !card.sourceQuote.isEmpty {
                    SourceReferenceChip(text: card.sourceQuote, onSelect: onSourceSelected)
                    Text(card.sourceQuote.paperCueBreakableText())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !card.tags.isEmpty {
                    Text(card.tags.joined(separator: "  ").paperCueBreakableText())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReviewQuestionRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: ReviewQuestion
    var isEditing: Bool
    var onSourceSelected: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                TextField("问题", text: $item.question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $item.purpose)
                    .frame(minHeight: 80)
                    .textEditorStyle()
                TextField("相关来源", text: $item.relatedSection, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                DeleteInlineButton(title: "删除问题") {
                    modelContext.delete(item)
                }
            } else {
                Text(item.question.paperCueBreakableText())
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.purpose.paperCueBreakableText())
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                SourceReferenceChip(text: item.relatedSection, fallback: "相关段落", onSelect: onSourceSelected)
                if !item.relatedSection.isEmpty {
                    Text(item.relatedSection.paperCueBreakableText())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DeleteInlineButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: "trash")
                .font(.footnote.weight(.medium))
        }
        .buttonStyle(.borderless)
    }
}

private struct SourceReferenceChip: View {
    var text: String
    var fallback = "原文片段"
    var onSelect: ((String) -> Void)?

    var body: some View {
        if let label = SourceReferenceExtractor.displayLabel(for: text, fallback: fallback) {
            Button {
                onSelect?(text)
            } label: {
                Label(label, systemImage: "bookmark")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(onSelect == nil)
        }
    }
}

private extension View {
    func textEditorStyle() -> some View {
        self
            .padding(6)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(.separator).opacity(0.55), lineWidth: 1)
            }
    }
}
