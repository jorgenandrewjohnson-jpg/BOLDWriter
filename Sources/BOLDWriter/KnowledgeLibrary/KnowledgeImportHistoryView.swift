import SwiftUI

struct KnowledgeImportHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: KnowledgeLibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Import History").font(.title2.bold())
                    Text("Completed items are saved in the local library. Rescan the same Takeout sources to retry interrupted or failed items.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if library.takeoutImportSessions.isEmpty {
                ContentUnavailableView("No imports yet", systemImage: "clock.arrow.circlepath", description: Text("Takeout import results and error summaries will appear here."))
            } else {
                List(library.takeoutImportSessions) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(session.sourceLabel).font(.headline).lineLimit(1)
                            Spacer()
                            Text(session.cancelled ? "Cancelled" : session.failures == 0 ? "Complete" : "Needs attention")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(session.cancelled || session.failures > 0 ? Color.orange : Color.secondary)
                        }
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        Text("\(session.imported) imported · \(session.duplicates) duplicates · \(session.unchanged) unchanged · \(session.failures) failed")
                            .font(.callout.monospacedDigit())
                        if !session.summary.isEmpty {
                            DisclosureGroup("Findings (\(session.summary.count))") {
                                ForEach(Array(session.summary.enumerated()), id: \.offset) { _, message in
                                    Text(message).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.foregroundStyle(.orange)
                        }
                    }.padding(.vertical, 5)
                }.listStyle(.inset)
            }
        }
        .padding(24)
        .frame(minWidth: 690, minHeight: 440)
    }
}
