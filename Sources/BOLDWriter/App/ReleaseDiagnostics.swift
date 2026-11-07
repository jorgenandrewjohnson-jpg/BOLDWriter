#if !APP_STORE
import AppKit
import Foundation
import PDFKit

/// Explicit command-line diagnostics: no network, credentials, or UI automation.
@MainActor
enum ReleaseDiagnostics {
    static func run(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (text, metadata) = SampleDocumentFactory.make()
        let sample = BOLDWriterDocument()
        sample.replaceText(with: text)
        sample.metadata = metadata
        let nativeURL = directory.appendingPathComponent("BOLD-Writer-Sample.boldwriter")
        try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata).write(to: nativeURL, options: .atomic, originalContentsURL: nil)
        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: nativeURL), contentType: .boldWriterDocument)
        guard reopened.text.string == text.string, reopened.metadata.comments == metadata.comments else {
            throw WriterError.message("Release diagnostic: native sample did not reopen correctly.")
        }
        for format in ExportFormat.allCases {
            try ExportService.write(format, document: sample, to: directory.appendingPathComponent("BOLD-Writer-Sample.\(format.extensionName)"))
        }
        let docxURL = directory.appendingPathComponent("BOLD-Writer-Sample.docx")
        let imported = try BOLDWriterDocument(fileWrapper: FileWrapper(url: docxURL), contentType: .docx)
        guard imported.text.string.contains("The Lantern at North Harbor"), imported.text.string.contains("Appendix") else {
            throw WriterError.message("Release diagnostic: DOCX sample did not reopen correctly.")
        }
        guard let pdf = PDFDocument(url: directory.appendingPathComponent("BOLD-Writer-Sample.pdf")), pdf.pageCount >= 2 else {
            throw WriterError.message("Release diagnostic: invalid sample PDF.")
        }
        for index in [0, pdf.pageCount - 1] {
            guard let page = pdf.page(at: index), let tiff = page.thumbnail(of: NSSize(width: 918, height: 1188), for: .mediaBox).tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: directory.appendingPathComponent("PDF-Page-\(index + 1).png"), options: .atomic)
        }
        var measurements: [[String: Any]] = []
        for count in [1_000, 20_000, 100_000, 250_000] {
            let began = Date()
            let string = Array(repeating: "harbor", count: count).joined(separator: " ")
            let text = NSAttributedString(string: string, attributes: [.font: WriterStyle.normal.font])
            let url = directory.appendingPathComponent("Manuscript-\(count).boldwriter")
            try BOLDWriterDocument.packageWrapper(text: text, metadata: DocumentMetadata(title: "\(count)-word test manuscript")).write(to: url, options: .atomic, originalContentsURL: nil)
            let loaded = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .boldWriterDocument)
            let statistics = DocumentAnalysis.statistics(for: loaded.text.string)
            guard statistics.words == count, loaded.text.string == string else { throw WriterError.message("Release diagnostic: large manuscript content mismatch.") }
            let storage = NSTextStorage(attributedString: loaded.text)
            let layout = NSLayoutManager()
            let container = NSTextContainer(containerSize: NSSize(width: 500, height: 700))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            guard layout.glyphRange(for: container).length > 0 else { throw WriterError.message("Release diagnostic: no first-page layout.") }
            measurements.append(["words": count, "saveReopenAnalysisAndFirstPageSeconds": Date().timeIntervalSince(began)])
        }
        let report: [String: Any] = ["nativeSampleReopened": true, "docxSampleReopened": true, "pdfPages": pdf.pageCount, "exportsGenerated": ExportFormat.allCases.map(\.extensionName), "largeManuscripts": measurements, "interactiveUITested": false, "liveAPITested": false]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("Release-Diagnostics.json"), options: .atomic)
        print("Release diagnostics passed. PDF: \(pdf.pageCount) pages; all four manuscript sizes reopened and laid out their first page.")
    }
}
#endif
