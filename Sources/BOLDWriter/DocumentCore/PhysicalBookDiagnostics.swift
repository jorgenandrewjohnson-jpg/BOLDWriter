import AppKit
import Foundation

enum PhysicalBookInteriorImageResolutionSeverity: String, Equatable {
    case marginal
    case low
}

struct PhysicalBookInteriorImageResolutionIssue: Equatable {
    let pageNumber: Int
    let imageName: String
    let effectiveDPI: Double
    let targetDPI: Double
    let severity: PhysicalBookInteriorImageResolutionSeverity
    let message: String
}

enum PhysicalBookImageResolutionSeverity: String, Equatable {
    case marginal
    case low
}

enum PhysicalBookImageResolutionRegion: String, Equatable, Hashable {
    case back
    case spine
    case front
}

struct PhysicalBookImageResolutionIssue: Equatable {
    let layerName: String
    let effectiveDPI: Double
    let targetDPI: Double
    let severity: PhysicalBookImageResolutionSeverity
    let regions: [PhysicalBookImageResolutionRegion]
    let message: String
}

enum PhysicalBookCoverSafeEdge: String, Equatable, Hashable {
    case spineSide
    case outer
    case top
    case bottom
}

struct PhysicalBookCoverSafeIssue: Equatable {
    let panel: PhysicalBookCoverPanel
    let edge: PhysicalBookCoverSafeEdge
    let layerName: String
    let message: String
}

enum PhysicalBookSpineTextIssueKind: Equatable {
    case spineTooNarrow
    case outsideSpineTrim
    case widerThanSafeSpine
    case insufficientFoldClearance
}

struct PhysicalBookSpineTextIssue: Equatable {
    let kind: PhysicalBookSpineTextIssueKind
    let layerName: String?
    let message: String
}

enum PhysicalBookPreflightStatus: String, Equatable {
    case ready = "READY"
    case review = "REVIEW"
    case notReady = "NOT READY"
}

struct PhysicalBookPreflightSummary: Equatable {
    let status: PhysicalBookPreflightStatus
    let errorCount: Int
    let warningCount: Int
}

struct PhysicalBookPublishingPreflight: Equatable {
    let pageCount: Int
    let status: PhysicalBookPreflightStatus
    let errors: [String]
    let warnings: [String]

    var isReady: Bool { status == .ready }
}

enum PhysicalBookDiagnostics {
    static func kdpMinimumMargins(pageCount: Int) -> (inside: Double, outside: Double) {
        let inside: Double
        switch pageCount {
        case ...150: inside = 27
        case 151...300: inside = 36
        case 301...500: inside = 45
        case 501...700: inside = 54
        default: inside = 63
        }
        return (inside, 18)
    }

    /// Applies the current KDP no-bleed minimums without shrinking any larger
    /// margins already present in the manuscript. The caller can apply this to
    /// a derived copy before repagination; it never changes source documents.
    static func applyingKDPPrintMargins(to settings: PageSettings, pageCount: Int) -> PageSettings {
        let minimum = kdpMinimumMargins(pageCount: pageCount)
        var result = settings
        result.leftMargin = max(settings.leftMargin, minimum.inside)
        // PageSettings stores a single left/right pair; keeping both at the
        // inside minimum is conservative and remains valid after mirroring.
        result.rightMargin = max(settings.rightMargin, minimum.inside)
        result.mirrorMargins = true
        result.gutter = 0
        result.topMargin = max(settings.topMargin, minimum.outside)
        // Keep body copy clear of the running footer. A quarter-inch body
        // margin would place footer and last text line on the same baseline.
        result.bottomMargin = max(settings.bottomMargin, 36)
        result.headerDistance = max(settings.effectiveHeaderDistance, minimum.outside)
        result.footerDistance = max(settings.effectiveFooterDistance, minimum.outside)
        return result
    }

    static func kdpInteriorMarginIssues(pageSettings: [PageSettings], pageCount: Int) -> [String] {
        guard !pageSettings.isEmpty else { return ["Export-ready pagination did not return page settings."] }
        let minimum = kdpMinimumMargins(pageCount: pageCount)
        var issues: [String] = []
        for (index, page) in pageSettings.enumerated() {
            let inside: Double
            let outside: Double
            if page.usesMirrorMargins {
                let isEvenPage = (index + 1).isMultiple(of: 2)
                inside = isEvenPage ? page.rightMargin : page.leftMargin
                outside = isEvenPage ? page.leftMargin : page.rightMargin
            } else {
                inside = min(page.leftMargin, page.rightMargin)
                outside = min(page.leftMargin, page.rightMargin)
            }
            let gutter = page.effectiveGutter
            if inside + gutter < minimum.inside - 0.5 {
                issues.append(String(format: "Page %d inside margin is %.3f in; KDP requires at least %.3f in for %d pages.", index + 1, (inside + gutter) / 72, minimum.inside / 72, pageCount))
            }
            if outside < minimum.outside - 0.5 || page.topMargin < minimum.outside - 0.5 || page.bottomMargin < minimum.outside - 0.5 {
                issues.append(String(format: "Page %d outside/top/bottom margins are below KDP's %.3f in no-bleed minimum.", index + 1, minimum.outside / 72))
            }
            if page.showsPageNumbers && page.effectiveFooterDistance < minimum.outside - 0.5 {
                issues.append(String(format: "Page %d footer distance is below KDP's %.3f in no-bleed minimum and may clip page numbers.", index + 1, minimum.outside / 72))
            }
            if issues.count >= 12 { break }
        }
        return issues
    }

    /// Production eligibility is based on the final paginated manuscript and
    /// its physical cover project. Imported templates remain references until
    /// their trim, page count, and binding match the current production profile.
    static func publishingPreflight(
        project: CoverProject,
        manuscriptPageCount: Int,
        pageSettings: [PageSettings]
    ) -> PhysicalBookPublishingPreflight {
        var errors: [String] = []
        var warnings: [String] = []

        if manuscriptPageCount <= 0 {
            errors.append("Manuscript pagination produced no printable pages.")
        }
        errors.append(contentsOf: kdpInteriorMarginIssues(pageSettings: pageSettings, pageCount: manuscriptPageCount))
        if project.type != .printFullWrap {
            errors.append("Select or create a full-wrap print cover project.")
        }

        if let measured = project.activeKDPHardcoverLayout {
            if measured.pageCount != manuscriptPageCount {
                errors.append("Imported KDP hardcover template is for \(measured.pageCount) pages; the current manuscript paginates to \(manuscriptPageCount). Keep it as a reference and generate a matching KDP template before production export.")
            }
            let page = pageSettings.first
            if let page {
                let width = Double(page.pageSize.width / 72)
                let height = Double(page.pageSize.height / 72)
                if abs(width - measured.trimWidth) > 0.01 || abs(height - measured.trimHeight) > 0.01 {
                    errors.append(String(format: "Imported hardcover template trim is %.3f × %.3f in; manuscript trim is %.3f × %.3f in. Generate a matching hardcover template.", measured.trimWidth, measured.trimHeight, width, height))
                }
            }
        } else {
            let hasVerifiedPaperbackGeometry =
                project.spinePageCount != nil
                && project.spineCaliperInches.map { $0.isFinite && $0 > 0 } == true
                && project.paperStockPreset != nil
                && project.productionBinding != nil
            if !hasVerifiedPaperbackGeometry {
                errors.append("Print cover geometry is provisional. Set final manuscript pagination, trim, binding, bleed, and paper stock before production export.")
            }
            if let mismatch = pageCountMessage(coverPages: project.spinePageCount, manuscriptPages: manuscriptPageCount) {
                errors.append(mismatch + " Regenerate the cover geometry from the final manuscript pagination.")
            }
            let mismatchedPages = trimMismatchPages(project: project, pages: pageSettings)
            if !mismatchedPages.isEmpty {
                errors.append("Cover trim does not match manuscript page size on pages: \(mismatchedPages.prefix(12).map(String.init).joined(separator: ", ")).")
            }
            if let delta = expectedSpineMismatch(project: project, manuscriptPages: manuscriptPageCount) {
                errors.append(String(format: "Cover spine differs from the selected paper stock by %.4f in. Regenerate the print wrap.", delta))
            }
        }

        if project.activeKDPHardcoverLayout == nil {
            let expectedWidth = project.backWidth + project.spineWidth + project.trimWidth + 2 * project.bleed
            let expectedHeight = project.trimHeight + 2 * project.bleed
            if ![project.canvasWidth, project.canvasHeight, expectedWidth, expectedHeight].allSatisfy(\.isFinite)
                || abs(project.canvasWidth - expectedWidth) > 0.01
                || abs(project.canvasHeight - expectedHeight) > 0.01 {
                errors.append("Cover canvas dimensions do not match its back, spine, front, and bleed measurements.")
            }
        }

        let missingProductionArtwork = project.layers.filter {
            $0.visible && !$0.isReferenceLayer
                && ($0.kind == .image || $0.kind == .paint)
                && $0.imageData == nil
        }
        if !missingProductionArtwork.isEmpty {
            let names = missingProductionArtwork.map { $0.name.isEmpty ? "Image" : $0.name }
            errors.append("Production artwork layer(s) are missing embedded source assets: \(names.joined(separator: ", ")).")
        }
        let missingReferenceArtwork = project.layers.filter {
            $0.visible && $0.isReferenceLayer
                && ($0.kind == .image || $0.kind == .paint || $0.kind == .template)
                && $0.imageData == nil
        }
        if !missingReferenceArtwork.isEmpty {
            let names = missingReferenceArtwork.map { $0.name.isEmpty ? "Reference layer" : $0.name }
            warnings.append("Reference-only layer(s) have unavailable artwork and are not included in print: \(names.joined(separator: ", ")).")
        }
        if project.dpi < 300 {
            errors.append("Cover export resolution is below KDP's 300 DPI minimum.")
        }
        for issue in coverImageResolutionIssues(project: project) {
            if issue.severity == .low {
                errors.append(issue.message)
            } else {
                warnings.append(issue.message)
            }
        }
        warnings.append(contentsOf: coverContentSafeIssues(project: project).map(\.message))
        warnings.append(contentsOf: spineTextIssues(project: project).map(\.message))
        let outside = project.layers.filter {
            $0.visible && !$0.isReferenceLayer && $0.kind != .group && ($0.frame.x < -0.001 || $0.frame.y < -0.001 || $0.frame.x + $0.frame.width > 1.001 || $0.frame.y + $0.frame.height > 1.001)
        }
        if !outside.isEmpty {
            errors.append("\(outside.count) visible layer(s) extend beyond the cover canvas and may be clipped.")
        }
        if (project.productionBinding ?? .softcover) == .softcover && project.bleed < 0.125 {
            warnings.append("Cover bleed is below the KDP paperback 0.125 in requirement; verify this binding's generated template specifications.")
        }
        if project.layers.contains(where: { $0.visible && $0.kind == .text && !$0.text.isEmpty }) {
            warnings.append("Review cover fonts in the exported PDF; editable text must be embedded or converted to outlines.")
        }
        let summary = preflightSummary(errorCount: errors.count, warningCount: warnings.count)
        return PhysicalBookPublishingPreflight(pageCount: manuscriptPageCount, status: summary.status, errors: errors, warnings: warnings)
    }

    static func preflightSummary(
        errorCount: Int,
        warningCount: Int
    ) -> PhysicalBookPreflightSummary {
        let errors =
            max(
                0,
                errorCount
            )

        let warnings =
            max(
                0,
                warningCount
            )

        let status:
            PhysicalBookPreflightStatus

        if errors > 0 {
            status =
                .notReady
        } else if warnings > 0 {
            status =
                .review
        } else {
            status =
                .ready
        }

        return PhysicalBookPreflightSummary(
            status:
                status,
            errorCount:
                errors,
            warningCount:
                warnings
        )
    }

    static func hasUnmirroredMargins(pages: [PageSettings]) -> Bool {
        guard pages.count > 1 else { return false }
        for evenIndex in stride(from: 1, to: pages.count, by: 2) {
            let odd = pages[evenIndex - 1], even = pages[evenIndex]
            if abs(odd.leftMargin - odd.rightMargin) > 1,
               abs(even.leftMargin - odd.rightMargin) > 1,
               abs(even.rightMargin - odd.leftMargin) > 1 { return true }
        }
        return false
    }
    static func pageCountMessage(coverPages: Int?, manuscriptPages: Int) -> String? {
        guard let coverPages, coverPages != manuscriptPages else { return nil }
        return "Cover spine is based on \(coverPages) pages; manuscript currently has \(manuscriptPages) pages."
    }

    static func productionProfileRepairTemplate(
        project:
            CoverProject
    ) -> BookProductionTemplate? {
        if let stored =
            project.productionTemplate,
           stored != .custom
        {
            return stored
        }

        let inferred =
            BookProductionTemplate
                .inferred(
                    from:
                        project
                )

        return inferred == .custom
            ? nil
            : inferred
    }

    static func productionProfileNeedsRepair(
        project:
            CoverProject,
        manuscriptPages:
            Int,
        pageSettings:
            [PageSettings]
    ) -> Bool {
        guard
            let template =
                productionProfileRepairTemplate(
                    project:
                        project
                )
        else {
            return false
        }

        if !template.matches(
            project
        ) {
            return true
        }

        if manuscriptPages > 0,
           pageCountMessage(
                coverPages:
                    project.spinePageCount,
                manuscriptPages:
                    manuscriptPages
           )
            != nil
        {
            return true
        }

        if !trimMismatchPages(
            project:
                project,
            pages:
                pageSettings
        )
        .isEmpty
        {
            return true
        }

        if manuscriptPages > 0,
           expectedSpineMismatch(
                project:
                    project,
                manuscriptPages:
                    manuscriptPages
           )
            != nil
        {
            return true
        }

        return false
    }

    static func trimMatches(project: CoverProject, page: PageSettings, tolerance: Double = 0.01) -> Bool {
        let size = page.pageSize
        let width = Double(size.width / 72), height = Double(size.height / 72)
        return (abs(width - project.trimWidth) <= tolerance && abs(height - project.trimHeight) <= tolerance)
    }

    static func trimMismatchPages(
        project: CoverProject,
        pages: [PageSettings]
    ) -> [Int] {
        pages
            .enumerated()
            .compactMap {
                index,
                page in

                trimMatches(
                    project:
                        project,
                    page:
                        page
                )
                    ? nil
                    : index + 1
            }
    }


    static func expectedSpineMismatch(project: CoverProject, manuscriptPages: Int) -> Double? {
        guard let caliper = project.spineCaliperInches,
              let expected = PhysicalBookGeometry.expectedSpine(pageCount: manuscriptPages, caliper: caliper),
              abs(expected - project.spineWidth) > 0.00001 else { return nil }
        return expected - project.spineWidth
    }

    static func spineTextIssues(
        project: CoverProject
    ) -> [PhysicalBookSpineTextIssue] {
        guard
            project.type == .printFullWrap,
            project.canvasWidth > 0,
            project.canvasHeight > 0,
            project.spineWidth > 0
        else {
            return []
        }

        let geometry =
            CoverWrapGeometry(
                project: project
            )

        let spine =
            geometry.spineTrim

        let hiddenGroups =
            Set(
                project.layers
                    .filter {
                        $0.kind == .group
                            && !$0.visible
                    }
                    .map(\.id)
            )

        let textLayers =
            project.layers.filter { layer in
                layer.visible
                    && layer.opacity > 0
                    && layer.kind == .text
                    && !layer.text
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty
                    && !(
                        layer.groupID
                            .map(
                                hiddenGroups.contains
                            )
                        ?? false
                    )
            }

        let candidates =
            textLayers.compactMap {
                layer
                    -> (
                        CoverLayer,
                        CoverRect
                    )? in

                let bounds =
                    rotatedBounds(
                        frame: layer.frame,
                        degrees: layer.rotation
                    )

                guard
                    overlapArea(
                        bounds,
                        spine
                    ) > 0.0000001
                else {
                    return nil
                }

                return (
                    layer,
                    bounds
                )
            }

        guard !candidates.isEmpty else {
            return []
        }

        var issues:
            [PhysicalBookSpineTextIssue] = []

        // This is a BOLD Writer inspection threshold rather than a
        // printer-specific production rule. Very narrow spines leave
        // little practical room for text plus fold drift.
        let narrowSpineThreshold =
            0.25

        if project.spineWidth
            < narrowSpineThreshold {

            issues.append(
                PhysicalBookSpineTextIssue(
                    kind:
                        .spineTooNarrow,
                    layerName: nil,
                    message:
                        "The spine is only "
                        + formatInches(
                            project.spineWidth
                        )
                        + " in wide. Spine text may be unreliable at this width; inspect your printer's minimum spine-text requirements."
                )
            )
        }

        // Reserve up to 1/16 in from each fold. On very narrow
        // spines the allowance scales down so the safe region never
        // disappears entirely.
        let foldClearanceInches =
            min(
                0.0625,
                project.spineWidth
                    * 0.20
            )

        let foldClearance =
            foldClearanceInches
            / project.canvasWidth

        let safeMinX =
            spine.x
            + foldClearance

        let safeMaxX =
            spine.x
            + spine.width
            - foldClearance

        let safeWidth =
            max(
                0,
                safeMaxX
                    - safeMinX
            )

        for (
            layer,
            bounds
        ) in candidates {
            let name =
                layer.name.isEmpty
                    ? "Spine text"
                    : layer.name

            let minX =
                bounds.x

            let maxX =
                bounds.x
                + bounds.width

            let minY =
                bounds.y

            let maxY =
                bounds.y
                + bounds.height

            let spineMaxX =
                spine.x
                + spine.width

            let spineMaxY =
                spine.y
                + spine.height

            let contained =
                minX >= spine.x
                    && maxX <= spineMaxX
                    && minY >= spine.y
                    && maxY <= spineMaxY

            if !contained {
                issues.append(
                    PhysicalBookSpineTextIssue(
                        kind:
                            .outsideSpineTrim,
                        layerName:
                            layer.name,
                        message:
                            "Spine text “"
                            + name
                            + "” extends outside the spine trim or across a spine fold."
                    )
                )

                continue
            }

            if bounds.width
                > safeWidth
                    + 0.0000001 {

                issues.append(
                    PhysicalBookSpineTextIssue(
                        kind:
                            .widerThanSafeSpine,
                        layerName:
                            layer.name,
                        message:
                            "Spine text “"
                            + name
                            + "” is wider than the preview's fold-safe spine area."
                    )
                )

                continue
            }

            if minX < safeMinX
                || maxX > safeMaxX {

                issues.append(
                    PhysicalBookSpineTextIssue(
                        kind:
                            .insufficientFoldClearance,
                        layerName:
                            layer.name,
                        message:
                            "Spine text “"
                            + name
                            + "” is within "
                            + formatInches(
                                foldClearanceInches
                            )
                            + " in of a spine fold."
                    )
                )
            }
        }

        return issues
    }

    static func nextIssuePage(
        after currentPage: Int,
        issuePages: [Int]
    ) -> Int? {
        let pages =
            Array(
                Set(
                    issuePages.filter {
                        $0 > 0
                    }
                )
            )
            .sorted()

        guard !pages.isEmpty else {
            return nil
        }

        return pages.first {
            $0 > currentPage
        }
        ?? pages.first
    }

    static func interiorImageResolutionIssues(
        text: NSAttributedString,
        pageRanges: [NSRange],
        targetDPI: Double = 300
    ) -> [PhysicalBookInteriorImageResolutionIssue] {
        guard
            targetDPI.isFinite,
            targetDPI > 0,
            text.length > 0,
            !pageRanges.isEmpty
        else {
            return []
        }

        var issues:
            [PhysicalBookInteriorImageResolutionIssue] = []

        for (
            pageIndex,
            rawRange
        ) in pageRanges.enumerated() {
            guard rawRange.length > 0 else {
                continue
            }

            let location =
                min(
                    max(
                        0,
                        rawRange.location
                    ),
                    text.length
                )

            let remaining =
                max(
                    0,
                    text.length
                        - location
                )

            let length =
                min(
                    max(
                        0,
                        rawRange.length
                    ),
                    remaining
                )

            guard length > 0 else {
                continue
            }

            let range =
                NSRange(
                    location:
                        location,
                    length:
                        length
                )

            var imageNumber =
                0

            text.enumerateAttribute(
                .attachment,
                in:
                    range
            ) {
                value,
                _,
                _ in

                guard
                    let attachment =
                        value
                            as? NSTextAttachment
                else {
                    return
                }

                imageNumber +=
                    1

                guard
                    let metrics =
                        interiorImageMetrics(
                            attachment
                        )
                else {
                    return
                }

                let widthInches =
                    Double(
                        metrics.displaySize.width
                    )
                    / 72

                let heightInches =
                    Double(
                        metrics.displaySize.height
                    )
                    / 72

                guard
                    widthInches > 0,
                    heightInches > 0
                else {
                    return
                }

                let effective =
                    min(
                        Double(
                            metrics.pixelWidth
                        )
                            / widthInches,
                        Double(
                            metrics.pixelHeight
                        )
                            / heightInches
                    )

                guard
                    effective.isFinite,
                    effective
                        < targetDPI
                else {
                    return
                }

                let resolutionQuality =
                    CoverCalculator
                        .resolutionQuality(
                            effectiveDPI:
                                effective,
                            targetDPI:
                                targetDPI
                        )

                let severity:
                    PhysicalBookInteriorImageResolutionSeverity =
                        resolutionQuality == .marginal
                            ? .marginal
                            : .low

                let pageNumber =
                    pageIndex
                    + 1

                let name =
                    metrics.name
                        ?? "Image \(imageNumber)"

                let quality =
                    severity == .low
                        ? "Low-resolution"
                        : "Marginal-resolution"

                let effectiveText =
                    String(
                        format:
                            "%.0f",
                        effective
                    )

                let targetText =
                    String(
                        format:
                            "%.0f",
                        targetDPI
                    )

                issues.append(
                    PhysicalBookInteriorImageResolutionIssue(
                        pageNumber:
                            pageNumber,
                        imageName:
                            name,
                        effectiveDPI:
                            effective,
                        targetDPI:
                            targetDPI,
                        severity:
                            severity,
                        message:
                            quality
                            + " manuscript image “"
                            + name
                            + "” on page "
                            + String(
                                pageNumber
                            )
                            + " is approximately "
                            + effectiveText
                            + " effective DPI; "
                            + targetText
                            + " DPI is recommended for print."
                    )
                )
            }
        }

        return issues
    }

    private static func interiorImageMetrics(
        _ attachment: NSTextAttachment
    ) -> (
        pixelWidth: Int,
        pixelHeight: Int,
        displaySize: NSSize,
        name: String?
    )? {
        let original =
            attachment.fileWrapper?
                .regularFileContents
            ?? attachment.contents

        let cellImage =
            (
                attachment.attachmentCell
                    as? NSCell
            )?
            .image

        let image =
            attachment.image
            ?? cellImage
            ?? original.flatMap(
                NSImage.init(
                    data:
                )
            )

        let bitmap =
            original.flatMap {
                NSBitmapImageRep(
                    data:
                        $0
                )
            }
            ?? image?
                .representations
                .compactMap {
                    $0
                        as? NSBitmapImageRep
                }
                .first
            ?? image?
                .tiffRepresentation
                .flatMap {
                    NSBitmapImageRep(
                        data:
                            $0
                    )
                }

        guard
            let bitmap,
            bitmap.pixelsWide > 0,
            bitmap.pixelsHigh > 0
        else {
            // Vector-only attachments are intentionally not labeled
            // low-resolution because raster DPI is not meaningful.
            return nil
        }

        func valid(
            _ size: NSSize
        ) -> Bool {
            size.width.isFinite
                && size.height.isFinite
                && size.width > 0
                && size.height > 0
                && size.width < 100_000
                && size.height < 100_000
        }

        let displaySize =
            [
                attachment.bounds.size,
                attachment
                    .attachmentCell?
                    .cellSize()
                    ?? .zero,
                image?.size
                    ?? .zero
            ]
            .first(
                where:
                    valid
            )

        guard let displaySize else {
            return nil
        }

        let preferredName =
            attachment.fileWrapper?
                .preferredFilename?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        return (
            bitmap.pixelsWide,
            bitmap.pixelsHigh,
            displaySize,
            (
                preferredName?
                    .isEmpty
                    == false
            )
                ? preferredName
                : nil
        )
    }

    static func coverImageResolutionIssues(
        project: CoverProject
    ) -> [PhysicalBookImageResolutionIssue] {
        guard
            project.type == .printFullWrap,
            project.dpi.isFinite,
            project.dpi > 0
        else {
            return []
        }

        let geometry =
            CoverWrapGeometry(
                project: project
            )

        let hiddenGroups =
            Set(
                project.layers
                    .filter {
                        $0.kind == .group
                            && !$0.visible
                    }
                    .map(\.id)
            )

        let regions: [
            (
                region:
                    PhysicalBookImageResolutionRegion,
                rect:
                    CoverRect
            )
        ] = [
            (
                .back,
                geometry.backTrim
            ),
            (
                .spine,
                geometry.spineTrim
            ),
            (
                .front,
                geometry.frontTrim
            )
        ]

        var issues:
            [PhysicalBookImageResolutionIssue] = []

        for layer in project.layers {
            guard
                layer.visible,
                layer.opacity > 0,
                !layer.isReferenceLayer,
                (
                    layer.kind == .image
                    || layer.kind == .paint
                ),
                layer.imageData != nil,
                !(
                    layer.groupID
                        .map(
                            hiddenGroups.contains
                        )
                    ?? false
                ),
                let effective =
                    CoverEditorEngine
                        .effectiveDPI(
                            layer,
                            project: project
                        ),
                effective.isFinite
            else {
                continue
            }

            let target =
                project.dpi

            guard effective < target else {
                continue
            }

            let resolutionQuality =
                CoverCalculator
                    .resolutionQuality(
                        effectiveDPI:
                            effective,
                        targetDPI:
                            target
                    )

            let severity:
                PhysicalBookImageResolutionSeverity =
                    resolutionQuality == .marginal
                        ? .marginal
                        : .low

            let bounds =
                rotatedBounds(
                    frame: layer.frame,
                    degrees: layer.rotation
                )

            let affected =
                regions.compactMap {
                    item
                        -> PhysicalBookImageResolutionRegion? in

                    overlapArea(
                        bounds,
                        item.rect
                    ) > 0.0000001
                        ? item.region
                        : nil
                }

            guard !affected.isEmpty else {
                continue
            }

            let layerName =
                layer.name.isEmpty
                    ? "Image"
                    : layer.name

            let effectiveText =
                String(
                    format:
                        "%.0f",
                    effective
                )

            let targetText =
                String(
                    format:
                        "%.0f",
                    target
                )

            let quality =
                severity == .low
                    ? "Low-resolution"
                    : "Marginal-resolution"

            issues.append(
                PhysicalBookImageResolutionIssue(
                    layerName:
                        layerName,
                    effectiveDPI:
                        effective,
                    targetDPI:
                        target,
                    severity:
                        severity,
                    regions:
                        Array(
                            Set(
                                affected
                            )
                        )
                        .sorted {
                            resolutionRegionSortOrder(
                                $0
                            )
                            < resolutionRegionSortOrder(
                                $1
                            )
                        },
                    message:
                        quality
                        + " cover image “"
                        + layerName
                        + "” is approximately "
                        + effectiveText
                        + " effective DPI; this cover targets "
                        + targetText
                        + " DPI."
                )
            )
        }

        return issues
    }

    private static func resolutionRegionSortOrder(
        _ region:
            PhysicalBookImageResolutionRegion
    ) -> Int {
        switch region {
        case .back:
            return 0

        case .spine:
            return 1

        case .front:
            return 2
        }
    }

    static func coverContentSafeIssues(
        project: CoverProject
    ) -> [PhysicalBookCoverSafeIssue] {
        guard
            project.type == .printFullWrap,
            project.canvasWidth > 0,
            project.canvasHeight > 0
        else {
            return []
        }

        let geometry =
            CoverWrapGeometry(
                project: project
            )

        let hiddenGroups =
            Set(
                project.layers
                    .filter {
                        $0.kind == .group
                            && !$0.visible
                    }
                    .map(\.id)
            )

        let panels: [
            (
                panel: PhysicalBookCoverPanel,
                trim: CoverRect,
                safe: CoverRect
            )
        ] = [
            (
                .back,
                geometry.backTrim,
                geometry.backSafeArea
            ),
            (
                .front,
                geometry.frontTrim,
                geometry.frontSafeArea
            )
        ]

        var issues:
            [PhysicalBookCoverSafeIssue] = []

        for layer in project.layers {
            guard
                layer.visible,
                layer.opacity > 0,
                !(
                    layer.groupID
                        .map(
                            hiddenGroups.contains
                        )
                    ?? false
                )
            else {
                continue
            }

            let hasInspectableContent:
                Bool

            switch layer.kind {
            case .text:
                hasInspectableContent =
                    !layer.text
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty

            case .image, .paint, .smartObject:
                hasInspectableContent =
                    layer.imageData != nil

            case .shape, .gradient:
                hasInspectableContent =
                    (
                        layer.fillOpacity
                        ?? 1
                    ) > 0

            case .path:
                hasInspectableContent =
                    layer.pathPoints?
                        .isEmpty
                    == false

            case .template,
                 .adjustment,
                 .group:
                hasInspectableContent =
                    false
            }

            guard hasInspectableContent else {
                continue
            }

            let bounds =
                rotatedBounds(
                    frame: layer.frame,
                    degrees: layer.rotation
                )

            for panelData in panels {
                let overlap =
                    overlapArea(
                        bounds,
                        panelData.trim
                    )

                guard overlap > 0.0000001 else {
                    continue
                }

                let panelArea =
                    max(
                        0.0000001,
                        panelData.trim.width
                            * panelData.trim.height
                    )

                let coverage =
                    overlap
                    / panelArea

                // Large non-text artwork commonly exists precisely to run
                // through trim and bleed. Do not report that as unsafe
                // foreground content. Text is always inspected.
                if layer.kind != .text,
                   coverage >= 0.85 {
                    continue
                }

                let safe =
                    panelData.safe

                let safeMaxX =
                    safe.x
                    + safe.width

                let safeMaxY =
                    safe.y
                    + safe.height

                let minX =
                    bounds.x

                let maxX =
                    bounds.x
                    + bounds.width

                let minY =
                    bounds.y

                let maxY =
                    bounds.y
                    + bounds.height

                var riskyEdges:
                    [PhysicalBookCoverSafeEdge] = []

                if minY < safe.y {
                    riskyEdges.append(
                        .top
                    )
                }

                if maxY > safeMaxY {
                    riskyEdges.append(
                        .bottom
                    )
                }

                switch panelData.panel {
                case .front:
                    if minX < safe.x {
                        riskyEdges.append(
                            .spineSide
                        )
                    }

                    if maxX > safeMaxX {
                        riskyEdges.append(
                            .outer
                        )
                    }

                case .back:
                    if minX < safe.x {
                        riskyEdges.append(
                            .outer
                        )
                    }

                    if maxX > safeMaxX {
                        riskyEdges.append(
                            .spineSide
                        )
                    }
                }

                let uniqueEdges =
                    Array(
                        Set(
                            riskyEdges
                        )
                    )
                    .sorted {
                        edgeSortOrder(
                            $0
                        )
                        < edgeSortOrder(
                            $1
                        )
                    }

                guard !uniqueEdges.isEmpty else {
                    continue
                }

                let layerName =
                    layer.name.isEmpty
                        ? layer.kind
                            .rawValue
                            .capitalized
                        : layer.name

                let panelName =
                    panelData.panel
                        == .front
                        ? "Front"
                        : "Back"

                for edge in uniqueEdges {
                    let edgeDescription:
                        String

                    switch edge {
                    case .spineSide:
                        edgeDescription =
                            "spine-side fold"

                    case .outer:
                        edgeDescription =
                            "outer trim edge"

                    case .top:
                        edgeDescription =
                            "top trim edge"

                    case .bottom:
                        edgeDescription =
                            "bottom trim edge"
                    }

                    issues.append(
                        PhysicalBookCoverSafeIssue(
                            panel:
                                panelData.panel,
                            edge:
                                edge,
                            layerName:
                                layerName,
                            message:
                                panelName
                                + " cover layer “"
                                + layerName
                                + "” enters the 5% production safe margin at the "
                                + edgeDescription
                                + "."
                        )
                    )
                }
            }
        }

        return issues
    }

    private static func edgeSortOrder(
        _ edge: PhysicalBookCoverSafeEdge
    ) -> Int {
        switch edge {
        case .spineSide:
            return 0
        case .outer:
            return 1
        case .top:
            return 2
        case .bottom:
            return 3
        }
    }

    private static func rotatedBounds(
        frame: CoverRect,
        degrees: Double
    ) -> CoverRect {
        let radians =
            degrees
            * .pi
            / 180

        guard
            abs(
                radians
                    .truncatingRemainder(
                        dividingBy:
                            2 * .pi
                    )
            )
                > 0.0000001
        else {
            return frame
        }

        let centerX =
            frame.x
            + frame.width / 2

        let centerY =
            frame.y
            + frame.height / 2

        let halfWidth =
            frame.width / 2

        let halfHeight =
            frame.height / 2

        let cosine =
            cos(radians)

        let sine =
            sin(radians)

        let corners = [
            (-halfWidth, -halfHeight),
            (halfWidth, -halfHeight),
            (halfWidth, halfHeight),
            (-halfWidth, halfHeight)
        ]

        let transformed =
            corners.map { point in
                let x =
                    point.0

                let y =
                    point.1

                return (
                    centerX
                        + x * cosine
                        - y * sine,
                    centerY
                        + x * sine
                        + y * cosine
                )
            }

        let xs =
            transformed.map {
                $0.0
            }

        let ys =
            transformed.map {
                $0.1
            }

        let minimumX =
            xs.min()
            ?? frame.x

        let maximumX =
            xs.max()
            ?? (
                frame.x
                + frame.width
            )

        let minimumY =
            ys.min()
            ?? frame.y

        let maximumY =
            ys.max()
            ?? (
                frame.y
                + frame.height
            )

        return CoverRect(
            x: minimumX,
            y: minimumY,
            width:
                maximumX
                - minimumX,
            height:
                maximumY
                - minimumY
        )
    }

    private static func overlapArea(
        _ a: CoverRect,
        _ b: CoverRect
    ) -> Double {
        let width =
            max(
                0,
                min(
                    a.x + a.width,
                    b.x + b.width
                )
                - max(
                    a.x,
                    b.x
                )
            )

        let height =
            max(
                0,
                min(
                    a.y + a.height,
                    b.y + b.height
                )
                - max(
                    a.y,
                    b.y
                )
            )

        return width
            * height
    }

    private static func formatInches(
        _ value: Double
    ) -> String {
        String(
            format:
                "%.3f",
            value
        )
    }
}
