//
//  DocumentDetailSections.swift
//  PaperCue
//
//  Created by Codex on 2026/5/13.
//

import SwiftUI

struct DocumentHeaderView: View {
    var document: ReadingDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label(document.sourceKind.title, systemImage: document.sourceKind.systemImage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                ReadingStatusBadge(status: document.generationStatus)
            }

            Text(document.title.paperCueBreakableText())
                .font(.largeTitle.weight(.semibold))
                .lineLimit(3)
                .minimumScaleFactor(0.55)
                .fixedSize(horizontal: false, vertical: true)

            if let sourceURL = document.sourceURL {
                Text(sourceURL.absoluteString.paperCueBreakableText(maxRunLength: 14))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GenerationProgressBanner: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "clock.arrow.circlepath")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct TextPreviewSection: View {
    var document: ReadingDocument
    var isGenerating: Bool

    var body: some View {
        StudyPackSectionView(
            title: "文本预览",
            systemImage: "text.alignleft",
            accessory: {
                NavigationLink {
                    FullTextReaderView(document: document)
                } label: {
                    Label("查看全文", systemImage: "doc.text.magnifyingglass")
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                .disabled(isGenerating || document.extractedText.isEmpty)
                .accessibilityIdentifier("openFullTextReaderButton")
            },
            content: {
                Text((document.textPreview.isEmpty ? "没有可显示的文本预览。" : document.textPreview).paperCueBreakableText())
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )
    }
}

struct GenerationConfigurationSection: View {
    var summary: String
    @Binding var selectedProfile: StudyPackGenerationProfile
    @Binding var selectedModules: Set<StudyPackModule>
    @Binding var customPrompt: String
    @Binding var isExpanded: Bool
    var isGenerating: Bool

    var body: some View {
        StudyPackSectionView(title: "生成配置", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                Text(summary.paperCueBreakableText())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        GenerationProfilePicker(selectedProfile: $selectedProfile, isGenerating: isGenerating)
                        GenerationModuleToggleList(
                            selectedModules: $selectedModules,
                            isGenerating: isGenerating
                        )
                        CustomGenerationPromptField(customPrompt: $customPrompt, isGenerating: isGenerating)
                    }
                    .padding(.top, 10)
                } label: {
                    Text("生成选项")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(isGenerating)
            }
        }
    }
}

struct GenerationProfilePicker: View {
    @Binding var selectedProfile: StudyPackGenerationProfile
    var isGenerating: Bool

    var body: some View {
        Picker("生成模式", selection: $selectedProfile) {
            ForEach(StudyPackGenerationProfile.allCases) { profile in
                Text(profile.title).tag(profile)
            }
        }
        .pickerStyle(.segmented)
        .disabled(isGenerating)
        .accessibilityIdentifier("generationProfilePicker")
    }
}

struct GenerationModuleToggleList: View {
    @Binding var selectedModules: Set<StudyPackModule>
    var isGenerating: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("输出模块")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(StudyPackModule.allCases) { module in
                    Toggle(isOn: moduleBinding(module)) {
                        Label(module.title, systemImage: module.systemImage)
                            .font(.body)
                    }
                    .padding(.vertical, 9)
                    .disabled(isGenerating || isLastSelectedModule(module))
                    .accessibilityIdentifier("moduleToggle-\(module.rawValue)")

                    if module != .questions {
                        Divider()
                            .padding(.leading, 28)
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func moduleBinding(_ module: StudyPackModule) -> Binding<Bool> {
        Binding(
            get: { selectedModules.contains(module) },
            set: { isSelected in
                if isSelected {
                    selectedModules.insert(module)
                } else if selectedModules.count > 1 {
                    selectedModules.remove(module)
                }
            }
        )
    }

    private func isLastSelectedModule(_ module: StudyPackModule) -> Bool {
        selectedModules.count == 1 && selectedModules.contains(module)
    }
}

struct CustomGenerationPromptField: View {
    @Binding var customPrompt: String
    var isGenerating: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("自定义要求")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("例如：更关注研究方法，术语解释更短", text: $customPrompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
                .disabled(isGenerating)
                .accessibilityIdentifier("customGenerationPromptField")
        }
    }
}

struct StudyPackContentSection: View {
    var studyPack: GeneratedStudyPack?
    @Binding var selectedTab: StudyTab
    var isEditing: Bool
    var onSourceSelected: (String) -> Void

    var body: some View {
        if let studyPack {
            let tabs = StudyPackTabResolver.availableTabs(for: studyPack)
            if tabs.isEmpty {
                ContentUnavailableView {
                    Label("没有生成内容", systemImage: "tray")
                }
                .frame(maxWidth: .infinity)
            } else {
                Picker("学习材料", selection: selectedTabBinding(for: studyPack)) {
                    ForEach(tabs) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("studyPackTabs")

                StudyPackTabContent(
                    studyPack: studyPack,
                    selectedTab: StudyPackTabResolver.activeTab(selectedTab, for: studyPack),
                    isEditing: isEditing,
                    onSourceSelected: onSourceSelected
                )
            }
        } else {
            ContentUnavailableView {
                Label("还没有学习材料", systemImage: "sparkles")
            } description: {
                Text("点击生成后，PaperCue 会创建摘要、术语表、Anki 卡片和提问清单。")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func selectedTabBinding(for studyPack: GeneratedStudyPack) -> Binding<StudyTab> {
        Binding(
            get: { StudyPackTabResolver.activeTab(selectedTab, for: studyPack) },
            set: { selectedTab = $0 }
        )
    }
}

struct StudyPackTabContent: View {
    var studyPack: GeneratedStudyPack
    var selectedTab: StudyTab
    var isEditing: Bool
    var onSourceSelected: (String) -> Void

    var body: some View {
        switch selectedTab {
        case .summary:
            SummaryView(studyPack: studyPack, isEditing: isEditing)
        case .glossary:
            GlossaryView(terms: studyPack.glossary, isEditing: isEditing, onSourceSelected: onSourceSelected)
        case .cards:
            FlashcardsView(cards: studyPack.flashcards, isEditing: isEditing, onSourceSelected: onSourceSelected)
        case .questions:
            ReviewQuestionsView(questions: studyPack.questions, isEditing: isEditing, onSourceSelected: onSourceSelected)
        }
    }
}

struct StudyPackActionsMenu: View {
    var studyPack: GeneratedStudyPack
    var exportURL: URL?
    var isEditing: Bool
    var isGenerating: Bool
    var onEditButtonTapped: () -> Void
    var onExport: (GeneratedStudyPack, StudyPackExportFormat) -> Void

    var body: some View {
        Menu {
            Button(action: onEditButtonTapped) {
                Label(isEditing ? "完成编辑" : "编辑学习材料", systemImage: isEditing ? "checkmark" : "pencil")
            }
            .disabled(isGenerating)
            .accessibilityIdentifier("editStudyPackButton")

            Divider()

            Menu {
                ForEach(StudyPackExportFormat.allCases) { format in
                    Button(format.title) {
                        onExport(studyPack, format)
                    }
                    .disabled(format == .anki && studyPack.flashcards.isEmpty)
                }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("exportStudyPackMenu")

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("分享导出文件", systemImage: "arrow.up.doc")
                }
                .accessibilityIdentifier("shareAnkiButton")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("学习材料操作")
        .accessibilityIdentifier("studyPackActionsMenu")
    }
}

struct DocumentBottomActionToolbar: View {
    var primaryTitle: String
    var primarySystemImage: String
    var primaryTint: Color
    var isPrimaryDisabled: Bool
    var isGenerating: Bool
    var onPrimaryAction: () -> Void
    var onCancelGeneration: () -> Void

    var body: some View {
        PaperCueGlassToolbar {
            PrimaryGlassActionButton(
                title: primaryTitle,
                systemImage: primarySystemImage,
                tint: primaryTint,
                isDisabled: isPrimaryDisabled,
                action: onPrimaryAction
            )
            .accessibilityIdentifier("generateStudyPackButton")

            if isGenerating {
                PrimaryGlassActionButton(
                    title: "取消",
                    systemImage: "xmark",
                    tint: .red,
                    prominence: .secondary,
                    action: onCancelGeneration
                )
                .accessibilityIdentifier("cancelGenerationButton")
            }
        }
    }
}

struct ErrorBanner: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.red)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SourceReferencePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    var resolvedReference: ResolvedSourceReference
    var onOpenFullText: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(resolvedReference.pageLabel ?? resolvedReference.reference.displayLabel, systemImage: "bookmark")
                        .font(.headline)
                        .foregroundStyle(.blue)

                    Text((resolvedReference.excerpt.isEmpty ? "没有可显示的原文片段。" : resolvedReference.excerpt).paperCueBreakableText())
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        onOpenFullText()
                        dismiss()
                    } label: {
                        Label("在全文中打开", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}
