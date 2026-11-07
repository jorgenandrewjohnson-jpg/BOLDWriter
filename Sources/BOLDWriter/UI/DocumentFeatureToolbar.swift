import SwiftUI

enum DocumentFeatureEntryPoint: String, CaseIterable, Identifiable {
    case evidenceReview
    case evidence
    case readAloud
    case audiobookStudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .evidenceReview: "Evidence Review"
        case .evidence: "Evidence"
        case .readAloud: "Read Aloud"
        case .audiobookStudio: "Audiobook Studio"
        }
    }

    var accessibilityIdentifier: String { "document.feature.\(rawValue)" }
}

struct DocumentFeatureActions {
    var evidenceReview: () -> Void
    var evidence: () -> Void
    var readAloud: () -> Void
    var audiobookStudio: () -> Void

    func open(_ entry: DocumentFeatureEntryPoint) {
        switch entry {
        case .evidenceReview: evidenceReview()
        case .evidence: evidence()
        case .readAloud: readAloud()
        case .audiobookStudio: audiobookStudio()
        }
    }
}

struct DocumentFeatureToolbar: View {
    var actions: DocumentFeatureActions
    var onReadSelection: () -> Void
    var onReadParagraph: () -> Void
    var onReadSection: () -> Void
    var onReadFromCursor: () -> Void
    var onReadDocument: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(DocumentFeatureEntryPoint.allCases) { entry in
                    control(for: entry)
                }
            }
            Menu {
                Button(DocumentFeatureEntryPoint.evidenceReview.title) { actions.open(.evidenceReview) }
                    .accessibilityIdentifier(DocumentFeatureEntryPoint.evidenceReview.accessibilityIdentifier)
                Button(DocumentFeatureEntryPoint.evidence.title) { actions.open(.evidence) }
                    .accessibilityIdentifier(DocumentFeatureEntryPoint.evidence.accessibilityIdentifier)
                Button("Start Read Aloud") { actions.open(.readAloud) }
                readAloudMenuItems
                Button(DocumentFeatureEntryPoint.audiobookStudio.title) { actions.open(.audiobookStudio) }
                    .accessibilityIdentifier(DocumentFeatureEntryPoint.audiobookStudio.accessibilityIdentifier)
            } label: {
                Label("Research & Narration", systemImage: "text.magnifyingglass")
            }
            .accessibilityIdentifier("document.feature.overflow")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func control(for entry: DocumentFeatureEntryPoint) -> some View {
        switch entry {
        case .evidenceReview:
            Button { actions.open(.evidenceReview) } label: {
                Label(entry.title, systemImage: "checklist")
            }
            .help("Review claims, evidence coverage, source status, and citations across this document")
            .accessibilityIdentifier(entry.accessibilityIdentifier)
        case .evidence:
            Button { actions.open(.evidence) } label: {
                Label(entry.title, systemImage: "text.book.closed")
            }
            .help("Review evidence attached to the selected manuscript passage")
            .accessibilityIdentifier(entry.accessibilityIdentifier)
        case .readAloud:
            Menu {
                Button("Start Read Aloud") { actions.open(.readAloud) }
                Divider()
                readAloudMenuItems
            } label: {
                Label(entry.title, systemImage: "speaker.wave.2")
            }
            .accessibilityIdentifier(entry.accessibilityIdentifier)
        case .audiobookStudio:
            Button { actions.open(.audiobookStudio) } label: {
                Label(entry.title, systemImage: "waveform.and.mic")
            }
            .help("Open the nonmodal audiobook production and publishing workspace")
            .accessibilityIdentifier(entry.accessibilityIdentifier)
        }
    }

    @ViewBuilder
    private var readAloudMenuItems: some View {
        Button("Read Selection", action: onReadSelection)
        Button("Read Current Paragraph", action: onReadParagraph)
        Button("Read Current Section", action: onReadSection)
        Button("Read From Cursor", action: onReadFromCursor)
        Button("Read Entire Document", action: onReadDocument)
    }
}
