import Foundation
import PDFKit

enum BookHealthSeverity: String, Equatable {
    case error
    case warning
    case information
}

struct BookHealthFinding: Identifiable, Equatable {
    var id: String
    var severity: BookHealthSeverity
    var title: String
    var location: String
    var detail: String
    var coverProjectID: UUID?
}

struct BookHealthProductionPDF {
    var data: Data
    var pageSettings: [PageSettings]
    var pageRanges: [NSRange]
}

struct BookHealthReport: Identifiable, Equatable {
    var id = UUID()
    var status: PhysicalBookPreflightStatus
    var pageCount: Int
    var trimDescription: String
    var findings: [BookHealthFinding]
    var productionPDFData: Data?
    var pageSettings: [PageSettings]

    static func productionPDF(
        from text: NSAttributedString,
        settings: PageSettings,
        sections: [DocumentSection],
        floatingImages: [FloatingImage] = []
    ) throws -> BookHealthProductionPDF {
        var pageSettings: [PageSettings] = []
        var pageRanges: [NSRange] = []
        let data = try PDFExporter.data(
            from: text,
            settings: settings,
            sections: sections,
            pageLayoutSink: { pageSettings = $0 },
            pageRangeSink: { pageRanges = $0 },
            floatingImages: floatingImages
        )
        return BookHealthProductionPDF(data: data, pageSettings: pageSettings, pageRanges: pageRanges)
    }

    static func evaluate(
        pdfData: Data,
        pageSettings: [PageSettings],
        coverProjects: [CoverProject],
        documentText: NSAttributedString? = nil,
        pageRanges: [NSRange] = [],
        bookmarks: [DocumentBookmark] = [],
        tocSettings: [PublishingTOCSettings] = []
    ) -> BookHealthReport {
        var findings: [BookHealthFinding] = []
        let pdf = PDFDocument(data: pdfData)
        let pageCount = pdf?.pageCount ?? 0

        if pageCount == 0 {
            findings.append(.init(
                id: "manuscript.pdf.invalid",
                severity: .error,
                title: "Production PDF could not be validated",
                location: "Manuscript export",
                detail: "The production pagination pipeline did not produce a readable PDF.",
                coverProjectID: nil
            ))
        } else {
            findings.append(.init(
                id: "manuscript.pages",
                severity: .information,
                title: "Production pagination completed",
                location: "Manuscript",
                detail: "The export-ready PDF contains \(pageCount) pages.",
                coverProjectID: nil
            ))
            if pageSettings.count != pageCount {
                findings.append(.init(
                    id: "manuscript.page-settings",
                    severity: .error,
                    title: "Page layout data does not match the PDF",
                    location: "Manuscript pagination",
                    detail: "Pagination returned \(pageSettings.count) page layouts for a \(pageCount)-page PDF. Recheck the document before print export.",
                    coverProjectID: nil
                ))
            }
            let fontIssues = Dictionary(grouping: PDFFontPreflight.unembeddedPageFonts(in: pdfData), by: \.fontName)
            for (index, name) in fontIssues.keys.sorted().enumerated() {
                guard let pages = fontIssues[name], let first = pages.first else { continue }
                findings.append(.init(
                    id: "manuscript.pdf.font-unembedded.\(index)",
                    severity: .warning,
                    title: "PDF font is not embedded",
                    location: "Manuscript page \(first.pageNumber)",
                    detail: "The exported PDF references \(name) without a font program. Check the printer's font requirements or choose a font the PDF exporter can embed.",
                    coverProjectID: nil
                ))
            }
            let imagePlacements = PDFImageResolutionPreflight.placements(in: pdfData)
            if let lowest = imagePlacements.min(by: { $0.minimumDPI < $1.minimumDPI }) {
                findings.append(.init(
                    id: "manuscript.pdf.image-resolution-summary",
                    severity: .information,
                    title: "PDF image resolution inspected",
                    location: "Manuscript export",
                    detail: "Measured \(imagePlacements.count) placed raster images\(imagePlacements.count == 10_000 ? " (inspection limit reached)" : "") in the exported PDF. Lowest effective resolution: \(Int(lowest.minimumDPI.rounded())) pixels/in on page \(lowest.pageNumber).",
                    coverProjectID: nil
                ))
            }
            for (index, image) in imagePlacements.enumerated() where image.minimumDPI < 150 {
                findings.append(.init(
                    id: "manuscript.pdf.image-low-resolution.\(index)",
                    severity: .warning,
                    title: "Review image resolution",
                    location: "Manuscript page \(image.pageNumber)",
                    detail: "A \(image.pixelWidth) × \(image.pixelHeight) pixel image is placed at about \(Int(image.minimumDPI.rounded())) pixels/in. It may appear soft in print. Confirm your printer's requirement or place a higher-resolution image at the same size.",
                    coverProjectID: nil
                ))
            }
        }

        let first = pageSettings.first
        let trimDescription: String
        if let first {
            let width = Double(first.pageSize.width / 72)
            let height = Double(first.pageSize.height / 72)
            trimDescription = String(format: "%.3f × %.3f in", width, height)
            findings.append(.init(
                id: "manuscript.trim",
                severity: .information,
                title: "Manuscript trim size",
                location: "Manuscript page setup",
                detail: trimDescription,
                coverProjectID: nil
            ))
            if pageSettings.contains(where: {
                abs(Double($0.pageSize.width / 72) - width) > 0.01
                    || abs(Double($0.pageSize.height / 72) - height) > 0.01
            }) {
                findings.append(.init(
                    id: "manuscript.mixed-trim",
                    severity: .error,
                    title: "The manuscript contains mixed trim sizes",
                    location: "Manuscript pages",
                    detail: "Print-wrap geometry requires consistent page dimensions. Review section page setup before generating covers.",
                    coverProjectID: nil
                ))
            }
            if let pdf, pdf.pageCount == pageSettings.count {
                for index in 0..<pdf.pageCount {
                    guard let page = pdf.page(at: index) else {
                        findings.append(.init(
                            id: "manuscript.pdf.page.\(index + 1)",
                            severity: .error,
                            title: "A PDF page is unreadable",
                            location: "Manuscript page \(index + 1)",
                            detail: "The production PDF contains a page that PDFKit cannot read.",
                            coverProjectID: nil
                        ))
                        continue
                    }
                    let bounds = page.bounds(for: .mediaBox)
                    let expected = pageSettings[index].pageSize
                    if abs(bounds.width - expected.width) > 1 || abs(bounds.height - expected.height) > 1 {
                        findings.append(.init(
                            id: "manuscript.pdf.geometry.\(index + 1)",
                            severity: .error,
                            title: "PDF page size differs from manuscript layout",
                            location: "Manuscript page \(index + 1)",
                            detail: "The exported page geometry does not match the pagination settings.",
                            coverProjectID: nil
                        ))
                    }
                    if page.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                        findings.append(.init(
                            id: "manuscript.blank-page.\(index + 1)",
                            severity: .warning,
                            title: "Confirm this blank page is intentional",
                            location: "Manuscript page \(index + 1)",
                            detail: "The exported page contains no selectable text. Image-only and intentionally blank pages may be expected.",
                            coverProjectID: nil
                        ))
                    }
                }
            }
        } else {
            trimDescription = "Unavailable"
            findings.append(.init(
                id: "manuscript.trim.unavailable",
                severity: .error,
                title: "Page layout data is unavailable",
                location: "Manuscript pagination",
                detail: "The production exporter returned no page settings.",
                coverProjectID: nil
            ))
        }

        if let documentText {
            findings.append(contentsOf: paginationHeadingFindings(
                documentText: documentText,
                pageRanges: pageRanges
            ))
            do {
                try DocumentBookmarks.validate(bookmarks, textLength: documentText.length)
            } catch {
                findings.append(.init(
                    id: "manuscript.bookmarks.invalid",
                    severity: .error,
                    title: "Bookmark data is invalid",
                    location: "Manuscript references",
                    detail: error.localizedDescription,
                    coverProjectID: nil
                ))
            }
            do {
                try PublishingTOCSettings.validate(tocSettings)
            } catch {
                findings.append(.init(
                    id: "manuscript.toc.settings.invalid",
                    severity: .error,
                    title: "Table of contents settings are invalid",
                    location: "Manuscript table of contents",
                    detail: error.localizedDescription,
                    coverProjectID: nil
                ))
            }
            let bookmarkNames = Set(bookmarks.map { $0.name.lowercased() })
            let tocIDs = Set(tocSettings.map(\.fieldID))
            let fullRange = NSRange(location: 0, length: documentText.length)
            documentText.enumerateAttribute(.boldWriterField, in: fullRange) { value, range, _ in
                guard let field = value as? WordField else { return }
                let components = field.instruction.split(whereSeparator: { $0.isWhitespace })
                guard let command = components.first?.uppercased() else { return }
                if command == "REF" || command == "PAGEREF" {
                    guard components.count > 1 else { return }
                    let target = components[1].trimmingCharacters(in: CharacterSet(charactersIn: "\\{}"))
                    guard !bookmarkNames.contains(target.lowercased()) else { return }
                    let pageNumber = pageRanges.firstIndex(where: { NSLocationInRange(range.location, $0) }).map { $0 + 1 }
                    let location = pageNumber.map { "Manuscript page \($0)" } ?? "Manuscript references"
                    findings.append(.init(
                        id: "manuscript.cross-reference.\(field.id.uuidString)",
                        severity: .error,
                        title: "Cross-reference target is missing",
                        location: location,
                        detail: "The \(command) field refers to ‘\(target)’, but that bookmark is not present. Restore the bookmark or edit the reference.",
                        coverProjectID: nil
                    ))
                } else if command == "TOC", !tocSettings.isEmpty, !tocIDs.contains(field.id) {
                    findings.append(.init(
                        id: "manuscript.toc.field-settings.\(field.id.uuidString)",
                        severity: .warning,
                        title: "Contents field has no matching publishing settings",
                        location: "Manuscript table of contents",
                        detail: "The field uses default contents settings. Reopen its table-of-contents options to confirm heading depth and page-number style.",
                        coverProjectID: nil
                    ))
                }
            }
            for setting in tocSettings where !documentTextContainsField(setting.fieldID, in: documentText) {
                findings.append(.init(
                    id: "manuscript.toc.field-missing.\(setting.fieldID.uuidString)",
                    severity: .error,
                    title: "Table of contents field is missing",
                    location: "Manuscript table of contents",
                    detail: "Saved contents settings no longer point to a field in this manuscript. Reinsert or remove the orphaned contents settings.",
                    coverProjectID: nil
                ))
            }
        }

        let printProjects = coverProjects.filter { $0.type == .printFullWrap }
        let configuredBindings = Set(printProjects.map { $0.productionBinding ?? .softcover })
        for binding in BookBinding.allCases where !configuredBindings.contains(binding) {
            let key = binding == .softcover ? "softcover" : "hardcover"
            findings.append(.init(
                id: "cover.profile.missing.\(key)",
                severity: .warning,
                title: "No \(binding.rawValue) print cover is configured",
                location: "\(binding.rawValue) cover profile",
                detail: "Add a matching print-wrap project if you plan to publish this binding.",
                coverProjectID: nil
            ))
        }

        for project in printProjects {
            let binding = project.productionBinding ?? .softcover
            let assessment = PhysicalBookDiagnostics.publishingPreflight(
                project: project,
                manuscriptPageCount: pageCount,
                pageSettings: pageSettings
            )
            for (index, message) in assessment.errors.enumerated() {
                findings.append(.init(
                    id: "cover.\(project.id.uuidString).error.\(index)",
                    severity: .error,
                    title: "\(binding.rawValue.capitalized) cover needs attention",
                    location: project.name,
                    detail: message,
                    coverProjectID: project.id
                ))
            }
            for (index, message) in assessment.warnings.enumerated() {
                findings.append(.init(
                    id: "cover.\(project.id.uuidString).warning.\(index)",
                    severity: .warning,
                    title: "Review \(binding.rawValue) cover",
                    location: project.name,
                    detail: message,
                    coverProjectID: project.id
                ))
            }
            for layer in project.layers {
                guard let object = layer.smartObject, object.storageMode == .linked else { continue }
                switch CoverLinkedSmartObjectResource.status(of: object) {
                case .current:
                    findings.append(.init(
                        id: "cover.\(project.id.uuidString).linked.\(layer.id.uuidString).current",
                        severity: .information,
                        title: "Linked artwork is available",
                        location: "\(project.name) · \(layer.name)",
                        detail: "The linked source can be read from its saved file bookmark.",
                        coverProjectID: project.id
                    ))
                case .modified, .staleBookmarkResolved:
                    findings.append(.init(
                        id: "cover.\(project.id.uuidString).linked.\(layer.id.uuidString).modified",
                        severity: .warning,
                        title: "Review linked artwork changes",
                        location: "\(project.name) · \(layer.name)",
                        detail: "The linked source changed or its file bookmark needs refreshing. Review the artwork before export.",
                        coverProjectID: project.id
                    ))
                case .unavailable, .none:
                    findings.append(.init(
                        id: "cover.\(project.id.uuidString).linked.\(layer.id.uuidString).unavailable",
                        severity: .error,
                        title: "Linked artwork is unavailable",
                        location: "\(project.name) · \(layer.name)",
                        detail: "BOLD Writer cannot read this linked source. Relink the original file or embed the artwork before production export.",
                        coverProjectID: project.id
                    ))
                }
            }
        }

        let errors = findings.contains { $0.severity == .error }
        let warnings = findings.contains { $0.severity == .warning }
        let status: PhysicalBookPreflightStatus = errors ? .notReady : (warnings ? .review : .ready)
        return BookHealthReport(
            status: status,
            pageCount: pageCount,
            trimDescription: trimDescription,
            findings: findings,
            productionPDFData: pdfData,
            pageSettings: pageSettings
        )
    }

    /// Uses the completed PDF pagination map. A warning is emitted only when a
    /// semantic heading's first following body text starts on a later page.
    /// This avoids inferring a visual orphan from text offsets alone.
    static func paginationHeadingFindings(
        documentText: NSAttributedString,
        pageRanges: [NSRange]
    ) -> [BookHealthFinding] {
        guard pageRanges.count > 1, documentText.length > 0 else { return [] }
        let source = documentText.string as NSString
        let headings = BOLDBookAuditAnalyzer.semanticHeadings(in: documentText)
        guard !headings.isEmpty else { return [] }

        func pageIndex(containing offset: Int) -> Int? {
            pageRanges.firstIndex { offset >= $0.location && offset < NSMaxRange($0) }
        }

        var results: [BookHealthFinding] = []
        for heading in headings {
            let headingPage = pageIndex(containing: heading.range.location)
            guard let headingPage else { continue }
            let paragraph = source.paragraphRange(for: heading.range)
            var bodyOffset = NSMaxRange(paragraph)
            while bodyOffset < source.length,
                  isWhitespace(source.character(at: bodyOffset)) {
                bodyOffset += 1
            }
            guard bodyOffset < source.length,
                  let bodyPage = pageIndex(containing: bodyOffset),
                  bodyPage > headingPage else { continue }
            results.append(.init(
                id: "manuscript.heading.orphan.\(heading.range.location)",
                severity: .warning,
                title: "Heading is separated from its body text",
                location: "Manuscript page \(headingPage + 1)",
                detail: "The heading is on page \(headingPage + 1), while its first following body text starts on page \(bodyPage + 1). Review the actual layout and consider keeping the heading with its paragraph.",
                coverProjectID: nil
            ))
        }
        return results
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    static func exportFailure(_ message: String) -> BookHealthReport {
        BookHealthReport(
            status: .notReady,
            pageCount: 0,
            trimDescription: "Unavailable",
            findings: [.init(
                id: "manuscript.export.failure",
                severity: .error,
                title: "Production pagination failed",
                location: "Manuscript",
                detail: message,
                coverProjectID: nil
            )],
            productionPDFData: nil,
            pageSettings: []
        )
    }

    private static func documentTextContainsField(_ id: UUID, in text: NSAttributedString) -> Bool {
        guard text.length > 0 else { return false }
        var found = false
        text.enumerateAttribute(.boldWriterField, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if (value as? WordField)?.id == id {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}
