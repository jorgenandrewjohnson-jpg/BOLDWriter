import SwiftUI

struct BookHealthCheckView: View {
    let report: BookHealthReport
    let onOpenCoverCreator: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showPrintProof = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Check My Book")
                        .font(.title2.weight(.semibold))
                    Text("Production pagination: \(report.pageCount) pages · Trim: \(report.trimDescription)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }

            if report.findings.isEmpty {
                ContentUnavailableView(
                    "No checks completed",
                    systemImage: "checkmark.seal",
                    description: Text("Run the check again after opening a manuscript.")
                )
            } else {
                List(report.findings) { finding in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: finding.severity))
                            .foregroundStyle(color(for: finding.severity))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(finding.title).font(.headline)
                            Text(finding.location).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            Text(finding.detail).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if finding.coverProjectID != nil {
                            Button("Review Cover", action: onOpenCoverCreator)
                                .buttonStyle(.borderless)
                                .accessibilityHint("Opens Cover Creator to review the production cover")
                        }
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.inset)
            }

            HStack {
                Text("This check reuses the production PDF paginator and print-cover preflight. Review warnings before exporting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Inspect Print Proof") { showPrintProof = true }
                    .disabled(report.productionPDFData == nil || report.pageCount == 0)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 460)
        .sheet(isPresented: $showPrintProof) {
            if let data = report.productionPDFData {
                BookProofPreviewView(data: data, pageCount: report.pageCount, pageSettings: report.pageSettings)
            }
        }
    }

    private var statusBadge: some View {
        let (label, symbol, tint): (String, String, Color) = switch report.status {
        case .ready: ("READY", "checkmark.seal.fill", .green)
        case .review: ("REVIEW", "exclamationmark.triangle.fill", .orange)
        case .notReady: ("NOT READY", "xmark.octagon.fill", .red)
        }
        return Label(label, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(tint)
            .accessibilityLabel("Book health status: \(label)")
    }

    private func icon(for severity: BookHealthSeverity) -> String {
        switch severity {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .information: "info.circle.fill"
        }
    }

    private func color(for severity: BookHealthSeverity) -> Color {
        switch severity {
        case .error: .red
        case .warning: .orange
        case .information: .blue
        }
    }
}
