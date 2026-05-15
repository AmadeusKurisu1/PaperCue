//
//  ContentView.swift
//  PaperCue
//
//  Created by 孙昊 on 2026/5/11.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @Query(sort: \ReadingDocument.importedAt, order: .reverse) private var documents: [ReadingDocument]

    @State private var selectedDocumentID: UUID?
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var isShowingPDFImporter = false
    @State private var isShowingURLImporter = false
    @State private var isShowingTextImporter = false
    @State private var isShowingSettings = false
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            List(selection: $selectedDocumentID) {
                if documents.isEmpty {
                    EmptyLibraryPrompt()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(documents) { document in
                        NavigationLink(value: document.id) {
                            DocumentRowView(document: document)
                        }
                        .accessibilityIdentifier("documentRow-\(document.id.uuidString)")
                    }
                    .onDelete(perform: deleteDocuments)
                }
            }
            .navigationTitle("PaperCue")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingPDFImporter = true
                    } label: {
                        Label("导入 PDF", systemImage: "doc.badge.plus")
                    }
                    .accessibilityIdentifier("importPDFButton")

                    Button {
                        isShowingURLImporter = true
                    } label: {
                        Label("导入网页", systemImage: "link.badge.plus")
                    }
                    .accessibilityIdentifier("importURLButton")

                    Button {
                        isShowingTextImporter = true
                    } label: {
                        Label("粘贴文本", systemImage: "doc.plaintext")
                    }
                    .accessibilityIdentifier("importTextButton")

                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("settingsButton")
                }
            }
            .overlay {
                if isImporting {
                    ProgressView("导入中")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        } detail: {
            if let document = selectedDocument {
                DocumentDetailView(document: document)
                    .environmentObject(settings)
            } else {
                EmptyDetailView()
            }
        }
        .fileImporter(isPresented: $isShowingPDFImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            importPDF(result)
        }
        .sheet(isPresented: $isShowingURLImporter) {
            URLImportView { url in
                importWebPage(url)
            }
        }
        .sheet(isPresented: $isShowingTextImporter) {
            TextImportView { title, text in
                importPastedText(title: title, text: text)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .alert("操作失败", isPresented: hasImportError) {
            Button("好", role: .cancel) {
                importError = nil
            }
        } message: {
            Text(importError ?? "")
        }
        .onAppear(perform: selectFallbackDocumentIfNeeded)
        .onChange(of: documents.map(\.id)) {
            selectFallbackDocumentIfNeeded()
        }
    }

    private var selectedDocument: ReadingDocument? {
        guard let selectedDocumentID else { return documents.first }
        return documents.first { $0.id == selectedDocumentID }
    }

    private var hasImportError: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { newValue in
                if !newValue {
                    importError = nil
                }
            }
        )
    }

    private func importPDF(_ result: Result<[URL], Error>) {
        Task {
            isImporting = true
            defer { isImporting = false }

            do {
                let sourceURLs = try result.get()
                guard !sourceURLs.isEmpty else {
                    throw PaperCueError.emptyExtractedText
                }

                var lastImportedDocument: ReadingDocument?
                for sourceURL in sourceURLs {
                    let document = try await ImportService().importPDF(from: sourceURL)
                    modelContext.insert(document)
                    lastImportedDocument = document
                }

                do {
                    try modelContext.save()
                } catch {
                    throw PaperCueError.persistenceFailed(message: error.localizedDescription)
                }
                selectedDocumentID = lastImportedDocument?.id
                preferredCompactColumn = .detail
            } catch {
                importError = error.paperCueMessage
            }
        }
    }

    private func importWebPage(_ url: URL) {
        Task {
            isImporting = true
            defer { isImporting = false }

            do {
                let document = try await ImportService().importWebPage(from: url)
                modelContext.insert(document)
                do {
                    try modelContext.save()
                } catch {
                    throw PaperCueError.persistenceFailed(message: error.localizedDescription)
                }
                selectedDocumentID = document.id
                preferredCompactColumn = .detail
            } catch {
                importError = error.paperCueMessage
            }
        }
    }

    private func importPastedText(title: String, text: String) {
        Task {
            isImporting = true
            defer { isImporting = false }

            do {
                let document = try ImportService().importPastedText(title: title, text: text)
                modelContext.insert(document)
                do {
                    try modelContext.save()
                } catch {
                    throw PaperCueError.persistenceFailed(message: error.localizedDescription)
                }
                selectedDocumentID = document.id
                preferredCompactColumn = .detail
            } catch {
                importError = error.paperCueMessage
            }
        }
    }

    private func selectFallbackDocumentIfNeeded() {
        if let selectedDocumentID, documents.contains(where: { $0.id == selectedDocumentID }) {
            return
        }

        selectedDocumentID = documents.first?.id
        preferredCompactColumn = selectedDocumentID == nil ? .sidebar : .detail
    }

    private func deleteDocuments(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(documents[index])
        }
        do {
            try modelContext.save()
        } catch {
            importError = PaperCueError.persistenceFailed(message: error.localizedDescription).paperCueMessage
        }
    }
}

#Preview {
    let configuration = ModelConfiguration(schema: paperCueSchema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: paperCueSchema, configurations: [configuration])

    ContentView()
        .environmentObject(AppSettings())
        .modelContainer(container)
}
