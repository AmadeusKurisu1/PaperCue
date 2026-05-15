//
//  DocumentDetailView.swift
//  PaperCue
//
//  Created by Codex on 2026/5/11.
//

import SwiftData
import SwiftUI

enum StudyTab: String, CaseIterable, Identifiable {
    case summary = "摘要"
    case glossary = "术语"
    case cards = "卡片"
    case questions = "问题"

    var id: String { rawValue }
}

private struct FullTextReaderRoute: Hashable, Identifiable {
    let id = UUID()
    var sourceReference: SourceReference?
}

enum StudyPackTabResolver {
    static func availableTabs(for studyPack: GeneratedStudyPack) -> [StudyTab] {
        StudyTab.allCases.filter { tab in
            switch tab {
            case .summary:
                studyPack.hasSummaryContent
            case .glossary:
                !studyPack.glossary.isEmpty
            case .cards:
                !studyPack.flashcards.isEmpty
            case .questions:
                !studyPack.questions.isEmpty
            }
        }
    }

    static func activeTab(_ selectedTab: StudyTab, for studyPack: GeneratedStudyPack) -> StudyTab {
        let tabs = availableTabs(for: studyPack)
        return tabs.first(where: { $0 == selectedTab }) ?? tabs.first ?? .summary
    }
}

struct DocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @Bindable var document: ReadingDocument

    @State private var selectedTab: StudyTab = .summary
    @State private var isGenerating = false
    @State private var operationError: String?
    @State private var exportURL: URL?
    @State private var generationTask: Task<Void, Never>?
    @State private var selectedGenerationProfile: StudyPackGenerationProfile = .deepReading
    @State private var selectedGenerationModules = Set(StudyPackModule.allCases)
    @State private var customGenerationPrompt = ""
    @State private var isGenerationOptionsExpanded = true
    @State private var generationProgressText: String?
    @State private var isEditingStudyPack = false
    @State private var selectedSourceReference: ResolvedSourceReference?
    @State private var fullTextReaderRoute: FullTextReaderRoute?

    private var hasOperationError: Binding<Bool> {
        Binding(
            get: { operationError != nil },
            set: { newValue in
                if !newValue {
                    operationError = nil
                }
            }
        )
    }

    private var generationOptions: StudyPackGenerationOptions {
        StudyPackGenerationOptions(
            enabledModules: StudyPackModule.allCases.filter { selectedGenerationModules.contains($0) },
            customPrompt: customGenerationPrompt
        )
    }

    private var generationConfigurationSummary: String {
        let modules = generationOptions.orderedEnabledModules.map(\.title).joined(separator: "、")
        let promptSuffix = customGenerationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : " · 已加自定义要求"
        return "\(selectedGenerationProfile.title) · \(modules.isEmpty ? "未选择模块" : modules)\(promptSuffix)"
    }

    private var canGenerate: Bool {
        !isGenerating && !isEditingStudyPack && !document.extractedText.isEmpty && !generationOptions.orderedEnabledModules.isEmpty
    }

    private var primaryActionTitle: String {
        if isEditingStudyPack {
            return "完成"
        }
        return isGenerating ? "生成中" : "生成"
    }

    private var primaryActionSystemImage: String {
        isEditingStudyPack ? "checkmark" : "sparkles"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DocumentHeaderView(document: document)

                if let errorMessage = document.errorMessage, document.generationStatus == .failed {
                    ErrorBanner(message: errorMessage)
                }

                if isGenerating, let generationProgressText {
                    GenerationProgressBanner(message: generationProgressText)
                }

                TextPreviewSection(document: document, isGenerating: isGenerating)

                GenerationConfigurationSection(
                    summary: generationConfigurationSummary,
                    selectedProfile: $selectedGenerationProfile,
                    selectedModules: $selectedGenerationModules,
                    customPrompt: $customGenerationPrompt,
                    isExpanded: $isGenerationOptionsExpanded,
                    isGenerating: isGenerating
                )

                StudyPackContentSection(
                    studyPack: document.studyPack,
                    selectedTab: $selectedTab,
                    isEditing: isEditingStudyPack,
                    onSourceSelected: showSourceReference
                )
            }
            .padding()
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.bottom, 112)
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let studyPack = document.studyPack {
                ToolbarItem(placement: .topBarTrailing) {
                    StudyPackActionsMenu(
                        studyPack: studyPack,
                        exportURL: exportURL,
                        isEditing: isEditingStudyPack,
                        isGenerating: isGenerating,
                        onEditButtonTapped: toggleStudyPackEditing,
                        onExport: exportStudyPack
                    )
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            DocumentBottomActionToolbar(
                primaryTitle: primaryActionTitle,
                primarySystemImage: primaryActionSystemImage,
                primaryTint: isEditingStudyPack ? .orange : .blue,
                isPrimaryDisabled: isEditingStudyPack ? isGenerating : !canGenerate,
                isGenerating: isGenerating,
                onPrimaryAction: handlePrimaryAction,
                onCancelGeneration: cancelGeneration
            )
        }
        .alert("操作失败", isPresented: hasOperationError) {
            Button("好", role: .cancel) {
                operationError = nil
            }
        } message: {
            Text(operationError ?? "")
        }
        .navigationDestination(item: $fullTextReaderRoute) { route in
            FullTextReaderView(document: document, initialReference: route.sourceReference)
        }
        .sheet(item: $selectedSourceReference) { reference in
            SourceReferencePreviewSheet(resolvedReference: reference) {
                selectedSourceReference = nil
                fullTextReaderRoute = FullTextReaderRoute(sourceReference: reference.reference)
            }
        }
        .onDisappear {
            cancelGeneration()
        }
    }

    private func handlePrimaryAction() {
        if isEditingStudyPack {
            saveStudyPackEdits()
        } else {
            generateStudyPack()
        }
    }

    private func toggleStudyPackEditing() {
        if isEditingStudyPack {
            saveStudyPackEdits()
        } else {
            isEditingStudyPack = true
        }
    }

    private func generateStudyPack() {
        guard generationTask == nil else { return }

        generationTask = Task {
            isGenerating = true
            document.generationStatus = .generating
            document.errorMessage = nil
            exportURL = nil
            generationProgressText = "准备生成学习材料。"
            isEditingStudyPack = false

            do {
                let configuration = try settings.llmConfiguration()
                let payload = try await StudyPackGenerationService().generate(
                    input: GenerateStudyPackInput(
                        title: document.title,
                        sourceKind: document.sourceKind,
                        sourceURL: document.sourceURL,
                        text: document.extractedText,
                        generationProfile: selectedGenerationProfile,
                        options: generationOptions
                    ),
                    configuration: configuration,
                    progress: { progress in
                        generationProgressText = progress.message
                    }
                )
                try Task.checkCancellation()

                if let existing = document.studyPack {
                    modelContext.delete(existing)
                    document.studyPack = nil
                }

                let studyPack = GeneratedStudyPack(payload: payload)
                modelContext.insert(studyPack)
                document.studyPack = studyPack
                selectedTab = StudyPackTabResolver.availableTabs(for: studyPack).first ?? .summary
                document.generationStatus = .completed
                document.errorMessage = nil
                do {
                    try modelContext.save()
                } catch {
                    throw PaperCueError.persistenceFailed(message: error.localizedDescription)
                }
            } catch is CancellationError {
                document.generationStatus = document.studyPack == nil ? .ready : .completed
                document.errorMessage = nil
                do {
                    try modelContext.save()
                } catch {
                    operationError = PaperCueError.persistenceFailed(message: error.localizedDescription).paperCueMessage
                }
            } catch {
                document.generationStatus = .failed
                document.errorMessage = error.paperCueMessage
                operationError = error.paperCueMessage
                do {
                    try modelContext.save()
                } catch {
                    operationError = PaperCueError.persistenceFailed(message: error.localizedDescription).paperCueMessage
                }
            }

            isGenerating = false
            generationProgressText = nil
            generationTask = nil
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        generationProgressText = nil
        if document.generationStatus == .generating {
            document.generationStatus = document.studyPack == nil ? .ready : .completed
        }
    }

    private func saveStudyPackEdits() {
        do {
            try modelContext.save()
            isEditingStudyPack = false
        } catch {
            operationError = PaperCueError.persistenceFailed(message: error.localizedDescription).paperCueMessage
        }
    }

    private func showSourceReference(_ referenceText: String) {
        guard let resolved = SourceReferenceResolver.resolve(referenceText: referenceText, in: document.extractedText) else {
            operationError = "没有在原文预览中找到对应来源。"
            return
        }
        selectedSourceReference = resolved
    }

    private func exportStudyPack(_ studyPack: GeneratedStudyPack, format: StudyPackExportFormat) {
        do {
            exportURL = try StudyPackExporter().export(studyPack: studyPack, sourceTitle: document.title, format: format)
        } catch {
            operationError = error.paperCueMessage
        }
    }
}
