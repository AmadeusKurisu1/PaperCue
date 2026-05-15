//
//  PaperCueApp.swift
//  PaperCue
//
//  Created by 孙昊 on 2026/5/11.
//

import Foundation
import SwiftUI
import SwiftData

@main
struct PaperCueApp: App {
    @StateObject private var settings = AppSettings()

    var sharedModelContainer: ModelContainer = {
        let isUITesting = ProcessInfo.processInfo.environment["PAPERCUE_UI_TESTING"] == "1"
        let modelConfiguration = ModelConfiguration(schema: paperCueSchema, isStoredInMemoryOnly: isUITesting)

        do {
            let container = try ModelContainer(for: paperCueSchema, configurations: [modelConfiguration])
            if isUITesting, ProcessInfo.processInfo.environment["PAPERCUE_UI_TESTING_SEED_DOCUMENT"] == "1" {
                seedUITestingDocument(in: container)
            }
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
        .modelContainer(sharedModelContainer)
    }
}

@MainActor
private func seedUITestingDocument(in container: ModelContainer) {
    let context = ModelContext(container)
    let document = ReadingDocument(
        title: "Seeded Paper",
        sourceKind: .pdf,
        sourceURL: URL(string: "https://example.com/seeded-paper.pdf"),
        extractedText: String(repeating: "This seeded paper discusses retrieval, evidence, methods, limitations, and review questions. ", count: 12)
    )

    context.insert(document)
    do {
        try context.save()
    } catch {
        assertionFailure("Could not seed UI testing document: \(error)")
    }
}
