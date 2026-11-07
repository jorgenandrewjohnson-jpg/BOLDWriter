import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Native Cover Creator workflow for exporting a guide-only PDF.
/// All dimensions are explicit inputs; no printer-specific stock is assumed.
struct BOLDPrintCoverProofSheet: View {
    let coverProject: CoverProject
    @Environment(\.dismiss) private var dismiss

    @State private var fields = BOLDPrintCoverProofInputs()
    @State private var artworkPreview: NSImage?
    @State private var artworkError: String?
    @State private var interiorSummary: String?
    @State private var alertMessage = ""
    @State private var showError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Physical Paperback Cover Guide")
                .font(.title2.weight(.semibold))

            Text(
                "Enter the actual page count and your printer's paper specifications. This exports a vector PDF with front, spine, back, bleed, and safe-area guides."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )

            HStack(spacing: 10) {
                Button("Read Interior PDF…") {
                    chooseInteriorPDF()
                }

                if let interiorSummary {
                    Text(interiorSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Form {
                TextField(
                    "Interior PDF page count",
                    text: $fields.pageCount
                )

                TextField(
                    "Trim width (in)",
                    text: $fields.trimWidth
                )

                TextField(
                    "Trim height (in)",
                    text: $fields.trimHeight
                )

                TextField(
                    "Sheet caliper (mils)",
                    text: $fields.caliperMils
                )

                TextField(
                    "Outside bleed (in)",
                    text: $fields.bleedInches
                )

                TextField(
                    "Safe text inset (in)",
                    text: $fields.safeInsetInches
                )

                TextField(
                    "Printer spine allowance (in)",
                    text: $fields.spineAllowanceInches
                )
            }
            .formStyle(.grouped)

            if let checked = try? fields.validate() {
                BOLDPrintCoverGuidePreview(
                    geometry: checked.geometry,
                    safeInsetInches: checked.safeInsetInches,
                    artwork: compatibleArtwork(for: checked.geometry)
                )

                if let warning = artworkWarning(for: checked.geometry) {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let artworkError {
                    Text(artworkError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }


                Text(
                    String(
                        format: "Flat cover: %.3f × %.3f in   •   Spine: %.3f in",
                        checked.geometry.totalCoverWidthInches,
                        checked.geometry.totalCoverHeightInches,
                        checked.geometry.spineWidthInches
                    )
                )
                .font(.callout.monospacedDigit())
            }

            Text(
                "Guide only — do not submit this PDF as final printer artwork. It does not include the current cover's artwork."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save PDF Guide…") {
                    saveGuide()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            loadCurrentArtwork()
        }
        .alert(
            "Cover guide export failed",
            isPresented: $showError
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func compatibleArtwork(
        for geometry: BOLDPrintCoverGeometry.Result
    ) -> NSImage? {
        guard let alignment = BOLDPrintCoverArtworkAlignment.evaluate(
            project: coverProject,
            geometry: geometry
        ), alignment.matches else {
            return nil
        }

        return artworkPreview
    }

    private func artworkWarning(
        for geometry: BOLDPrintCoverGeometry.Result
    ) -> String? {
        guard let alignment = BOLDPrintCoverArtworkAlignment.evaluate(
            project: coverProject,
            geometry: geometry
        ) else {
            return "The cover artwork's physical dimensions could not be verified."
        }

        return alignment.warning
    }

    private func loadCurrentArtwork() {
        guard artworkPreview == nil else {
            return
        }

        guard let plan = PhysicalBookCoverTextures.renderPlan(
            project: coverProject,
            previewDPI: 24
        ) else {
            artworkError = "The existing cover cannot be rasterized within the preview memory budget."
            return
        }

        do {
            artworkPreview = try CoverArtwork.render(
                coverProject,
                includeGuides: false,
                includeTemplate: true,
                scale: plan.panelDPI
            )

            artworkError = nil
        } catch {
            artworkError = "The existing artwork could not be previewed: "
                + error.localizedDescription
        }
    }

    private func chooseInteriorPDF() {
        let panel = NSOpenPanel()

        panel.title = "Choose Finished Interior PDF"

        panel.message = "Page count and consistent trim dimensions will be read from the PDF."

        panel.allowedContentTypes = [.pdf]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK,
              let selectedURL = panel.url else {
            return
        }

        do {
            // Inspect all pages before changing any form values.
            let inspected = try BOLDInteriorPDFInspection.inspect(
                url: selectedURL
            )

            fields.apply(inspected)

            interiorSummary = "\(selectedURL.lastPathComponent) — \(inspected.pageCount) pages"
        } catch {
            alertMessage = error.localizedDescription
            showError = true
        }
    }

    private func saveGuide() {
        do {
            let checked = try fields.validate()

            let panel = NSSavePanel()
            panel.title = "Save Physical Cover Guide"
            panel.prompt = "Save Guide"

            panel.nameFieldStringValue =
                "BOLD Writer Paperback Cover Guide.pdf"

            panel.allowedContentTypes = [.pdf]
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK,
                  let destination = panel.url else {
                return
            }

            // Refuse to overwrite preexisting artwork or PDF files.
            try BOLDPrintCoverProofPDF.create(
                geometry: checked.geometry,
                safeInsetInches: checked.safeInsetInches,
                at: destination
            )

            dismiss()
        } catch {
            alertMessage = error.localizedDescription
            showError = true
        }
    }
}
