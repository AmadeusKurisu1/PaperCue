//
//  ImportViews.swift
//  PaperCue
//
//  Created by Codex on 2026/5/11.
//

import Foundation
import SwiftUI

struct DocumentRowView: View {
    var document: ReadingDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(document.sourceKind.title, systemImage: document.sourceKind.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                ReadingStatusBadge(status: document.generationStatus)
            }

            Text(document.title.paperCueBreakableText())
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text((document.textPreview.isEmpty ? "暂无文本预览" : document.textPreview).paperCueBreakableText())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}

struct EmptyLibraryPrompt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "text.page.badge.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("导入 PDF、网页或文本开始")
                .font(.headline)

            Text("PaperCue 会提取或整理正文，再生成摘要、术语表、Anki 卡片和提问清单。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
        .accessibilityIdentifier("emptyLibraryPrompt")
    }
}

struct EmptyDetailView: View {
    var body: some View {
        ContentUnavailableView {
            Label("选择一篇文档", systemImage: "book.pages")
        } description: {
            Text("从左侧文档库选择，或导入新的 PDF、网页、文本。")
        }
    }
}

struct URLImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var errorMessage: String?

    var onImport: (URL) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("网页或论文地址") {
                    TextField("https://example.com/article", text: $urlText)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("urlImportTextField")

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("导入网页")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        guard let url = ImportURLNormalizer.normalizedURL(from: urlText) else {
                            errorMessage = PaperCueError.invalidURL.errorDescription
                            return
                        }

                        onImport(url)
                        dismiss()
                    }
                    .accessibilityIdentifier("confirmURLImportButton")
                }
            }
        }
    }

}

struct TextImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var errorMessage: String?

    var onImport: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("可留空", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("textImportTitleField")
                }

                Section("正文") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 260)
                        .accessibilityIdentifier("textImportBodyEditor")

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("粘贴文本")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        guard !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            errorMessage = PaperCueError.emptyExtractedText.errorDescription
                            return
                        }

                        onImport(title, bodyText)
                        dismiss()
                    }
                    .accessibilityIdentifier("confirmTextImportButton")
                }
            }
        }
    }
}
