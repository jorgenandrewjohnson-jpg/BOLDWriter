import AppKit
import Foundation

enum PDFExporter {
    static func data(
        from text: NSAttributedString,
        settings: PageSettings,
        sections: [DocumentSection]? = nil,
        pageLayoutSink: (([PageSettings]) -> Void)? = nil,
        pageColumnHeightSink: (([[CGFloat]]) -> Void)? = nil,
        pageColumnBottomSink: (([[CGFloat]]) -> Void)? = nil,
        pageRangeSink: (([NSRange]) -> Void)? = nil,
        floatingImages: [FloatingImage] = []
    ) throws -> Data {
        let footnotePrintable = NSMutableAttributedString(attributedString: text)
        try Footnotes.renumber(footnotePrintable)

        let printable =
            try Endnotes.printable(
                footnotePrintable
            )

        let printableSections =
            try sectionsForPrintableText(
                original:
                    text,
                printable:
                    printable,
                sections:
                    sections ?? [],
                fallbackPage:
                    settings
            )

        let firstSettings =
            printableSections.first?
                .page
            ?? settings

        let firstGeometry =
            try PageGeometry(
                firstSettings
            )

        let result =
            NSMutableData()

        guard
            let consumer =
                CGDataConsumer(
                    data:
                        result
                        as CFMutableData
                )
        else {
            throw CocoaError(
                .fileWriteUnknown
            )
        }

        var mediaBox =
            CGRect(
                origin:
                    .zero,
                size:
                    firstGeometry.size
            )

        guard
            let context =
                CGContext(
                    consumer:
                        consumer,
                    mediaBox:
                        &mediaBox,
                    nil
                )
        else {
            throw CocoaError(
                .fileWriteUnknown
            )
        }

        var failure:
            Error?
        var renderedPageSettings: [PageSettings] = []
        var renderedPageRanges: [NSRange] = []
        var renderedPageColumnHeights: [[CGFloat]] = []
        var renderedPageColumnBottoms: [[CGFloat]] = []

        NSAppearance(
            named:
                .aqua
        )!
        .performAsCurrentDrawingAppearance {
            do {
                try render(
                    printable,
                    sections:
                        printableSections,
                    fallbackPage:
                        settings,
                    renderedPageSettings:
                        &renderedPageSettings,
                        renderedPageRanges:
                        &renderedPageRanges,
                    renderedPageColumnHeights:
                        &renderedPageColumnHeights,
                    renderedPageColumnBottoms:
                        &renderedPageColumnBottoms,
                    floatingImages:
                        floatingImages,
                    context:
                        context
                )
            } catch {
                failure =
                    error
            }
        }

        context.closePDF()

        if let failure {
            throw failure
        }

        pageLayoutSink?(renderedPageSettings)
        pageColumnHeightSink?(
            renderedPageColumnHeights
        )
        pageColumnBottomSink?(
            renderedPageColumnBottoms
        )
        pageRangeSink?(renderedPageRanges)

        return result
            as Data
    }

    private static func sectionsForPrintableText(
        original: NSAttributedString,
        printable: NSAttributedString,
        sections: [DocumentSection],
        fallbackPage: PageSettings
    ) throws -> [DocumentSection] {
        let normalized =
            DocumentSection.normalized(
                sections,
                textLength:
                    original.length,
                fallbackPage:
                    fallbackPage
            )

        let originalFootnotes =
            try Footnotes.records(
                in:
                    original
            )

        let originalEndnotes =
            try Endnotes.records(
                in:
                    original
            )

        guard
            !originalFootnotes.isEmpty
                || !originalEndnotes.isEmpty
        else {
            return DocumentSection.normalized(
                normalized,
                textLength:
                    printable.length,
                fallbackPage:
                    fallbackPage
            )
        }

        let printableFootnotes =
            try Footnotes.records(
                in:
                    printable
            )

        let printableEndnotes =
            try Endnotes.records(
                in:
                    printable
            )

        var printableByID:
            [UUID: NSRange] = [:]

        for note in printableFootnotes {
            printableByID[
                note.id
            ] =
                NSRange(
                    location:
                        note.location,
                    length:
                        note.length
                )
        }

        for note in printableEndnotes {
            printableByID[
                note.id
            ] =
                NSRange(
                    location:
                        note.location,
                    length:
                        note.length
                )
        }

        var originalReferences:
            [
                (
                    id: UUID,
                    location: Int,
                    length: Int
                )
            ] = []

        originalReferences.append(
            contentsOf:
                originalFootnotes.map {
                    (
                        id:
                            $0.id,
                        location:
                            $0.location,
                        length:
                            $0.length
                    )
                }
        )

        originalReferences.append(
            contentsOf:
                originalEndnotes.map {
                    (
                        id:
                            $0.id,
                        location:
                            $0.location,
                        length:
                            $0.length
                    )
                }
        )

        originalReferences.sort {
            if $0.location == $1.location {
                return $0.id.uuidString
                    < $1.id.uuidString
            }

            return $0.location
                < $1.location
        }

        let rebased =
            normalized.map {
                section
                -> DocumentSection in

                var delta =
                    0

                for note in originalReferences {
                    let end =
                        note.location
                        + note.length

                    guard
                        end
                            <= section.location,
                        let printableNote =
                            printableByID[
                                note.id
                            ]
                    else {
                        continue
                    }

                    delta +=
                        printableNote.length
                        - note.length
                }

                return DocumentSection(
                    location:
                        min(
                            printable.length,
                            max(
                                0,
                                section.location
                                + delta
                            )
                        ),
                    page:
                        section.page,
                    breakType:
                        section.breakType
                )
            }

        return DocumentSection.normalized(
            rebased,
            textLength:
                printable.length,
            fallbackPage:
                fallbackPage
        )
    }

    private static func section(
        at character: Int,
        in sections: [DocumentSection]
    ) -> DocumentSection {
        sections.last(
            where: {
                $0.location
                    <= character
            }
        )
        ?? sections[0]
    }

    private static func pageInfo(
        size: CGSize
    ) -> CFDictionary {
        var mediaBox =
            CGRect(
                origin:
                    .zero,
                size:
                    size
            )

        let mediaBoxData =
            NSData(
                bytes:
                    &mediaBox,
                length:
                    MemoryLayout<CGRect>
                        .size
            )

        return [
            kCGPDFContextMediaBox
                as String:
                    mediaBoxData
        ]
        as CFDictionary
    }

    private static func requiresParityBlank(
        for section: DocumentSection,
        physicalPage: Int
    ) -> Bool {
        switch section.effectiveBreakType {
        case .oddPage:
            return physicalPage
                .isMultiple(
                    of: 2
                )

        case .evenPage:
            return !physicalPage
                .isMultiple(
                    of: 2
                )

        case .nextPage,
             .continuous,
             .nextColumn:
            return false
        }
    }

    private static func drawBlankPage(
        geometry: PageGeometry,
        pageNumber: Int,
        sectionPageNumber: Int,
        displayPageNumber: Int,
        context: CGContext
    ) {
        context.beginPDFPage(
            pageInfo(
                size:
                    geometry.size
            )
        )

        context.saveGState()

        context.translateBy(
            x:
                0,
            y:
                geometry.size.height
        )

        context.scaleBy(
            x:
                1,
            y:
                -1
        )

        NSGraphicsContext
            .saveGraphicsState()

        NSGraphicsContext.current =
            NSGraphicsContext(
                cgContext:
                    context,
                flipped:
                    true
            )

        geometry.drawFooter(
            page:
                pageNumber,
            sectionPage:
                sectionPageNumber,
            displayPage:
                displayPageNumber
        )

        NSGraphicsContext
            .restoreGraphicsState()

        context.restoreGState()

        context.endPDFPage()
    }

    /// The same finite containers and explicit-break policy
    /// as onscreen Print Layout. Parity-only physical pages are
    /// emitted directly to the PDF context and never enter TextKit.
    private static func render(
        _ text: NSAttributedString,
        sections: [DocumentSection],
        fallbackPage: PageSettings,
        renderedPageSettings: inout [PageSettings],
        renderedPageRanges: inout [NSRange],
        renderedPageColumnHeights: inout [[CGFloat]],
        renderedPageColumnBottoms: inout [[CGFloat]],
        floatingImages: [FloatingImage],
        context: CGContext
    ) throws {
        let flow =
            PageLayout(
                text:
                    text
            )
        let footnotes = try Footnotes.records(in: text)
        var continuingFootnotes: [FootnoteContinuation] = []

        flow.sectionBreakLocations =
            Set(
                sections
                    .dropFirst()
                    .filter {
                        $0.effectiveBreakType
                            != .continuous
                    }
                    .map(
                        \.location
                    )
            )

        var pageNumber =
            0

        var sectionPageNumber =
            0

        var displayPageNumber =
            0

        var activeSectionLocation:
            Int?

        var startCharacter =
            0

        // Text anchors are resolved from the first page layout that does not
        // yet include their own wrap exclusion. Keeping that snapshot fixed
        // during subsequent wrapped passes prevents a self-referential
        // anchor/exclusion cycle. The editor uses the same shared policy.
        var resolvedAnchorSnapshots: [UUID: FloatingImage] = [:]

        var finished =
            false

        repeat {
            let currentSection =
                section(
                    at:
                        startCharacter,
                    in:
                        sections
                )

            let startsNewSection =
                activeSectionLocation
                    != currentSection.location

            if startsNewSection,
               activeSectionLocation != nil,
               startCharacter
                    == currentSection.location,
               requiresParityBlank(
                for:
                    currentSection,
                physicalPage:
                    pageNumber + 1
               ) {

                let previousSection =
                    section(
                        at:
                            max(
                                0,
                                startCharacter - 1
                            ),
                        in:
                            sections
                    )

                let blankGeometry =
                    try PageGeometry(
                        previousSection.page
                    )
                    .resolvingPhysicalPage(
                        pageNumber + 1
                    )

                renderedPageSettings.append(previousSection.page)
                renderedPageRanges.append(
                    NSRange(
                        location: 0,
                        length: 0
                    )
                )
                renderedPageColumnHeights.append(
                    []
                )
                renderedPageColumnBottoms.append(
                    []
                )

                pageNumber +=
                    1

                displayPageNumber +=
                    1

                sectionPageNumber +=
                    1

                guard
                    pageNumber <= 20_000
                else {
                    throw WriterError.message(
                        "This export exceeds 20,000 pages. Export smaller sections."
                    )
                }

                drawBlankPage(
                    geometry:
                        blankGeometry,
                    pageNumber:
                        pageNumber,
                    sectionPageNumber:
                        max(
                            1,
                            sectionPageNumber
                        ),
                    displayPageNumber:
                        displayPageNumber,
                    context:
                        context
                )
            }

            if startsNewSection {
                activeSectionLocation =
                    currentSection.location

                sectionPageNumber =
                    1

            } else {
                sectionPageNumber +=
                    1
            }

            let geometry =
                try PageGeometry(
                    currentSection.page
                )
                .resolvingPhysicalPage(
                    pageNumber + 1
                )

            renderedPageSettings.append(currentSection.page)

            var columns: [(glyphs: NSRange, characters: NSRange)] = []
            var containers: [NSTextContainer] = []
            var pageFinished = false
            var pageCharacters = NSRange(location: startCharacter, length: 0)
            var pageNotes = PageFootnotePlan()
            var reserved: CGFloat = 0
            let columnCount = max(1, geometry.columnCount)
            var converged = false
            var activePageImages = floatingImages.compactMap { image -> FloatingImage? in
                let textAnchored = image.anchor == .paragraph || image.anchor == .character
                guard image.pageIndex == pageNumber,
                      !textAnchored || (image.anchorOffsetX == nil && image.anchorOffsetY == nil) else { return nil }
                guard image.horizontalAlignment != nil || image.verticalAlignment != nil else { return image }
                return FloatingImageLayout.positionedAtAnchor(image, pageIndex: pageNumber, origin: .zero,
                                                               pageContentOrigin: geometry.contentOrigin,
                                                               pageGeometry: geometry)
            }
            var seenAnchorStates = Set<String>()

            for _ in 0..<32 {
                columns.removeAll(keepingCapacity: true)
                pageFinished = false
                let target = NSSize(width: geometry.columnWidth,
                                    height: geometry.contentSize.height - reserved)
                for columnIndex in 0..<columnCount {
                    let container: NSTextContainer
                    if columnIndex < containers.count {
                        container = containers[columnIndex]
                        if container.containerSize != target { container.containerSize = target }
                    } else {
                        container = flow.addContainer(size: target)
                        containers.append(container)
                    }
                    container.exclusionPaths = FloatingImageLayout.exclusionPaths(
                        images: activePageImages,
                        pageIndex: pageNumber,
                        geometry: geometry,
                        columnIndex: columnIndex,
                        font: FloatingImageLayout.representativeFont(in: flow.storage, at: startCharacter)
                    )
                    let column = try flow.layout(container, geometry: geometry)
                    columns.append((column.glyphs, column.characters))
                    if columnIndex < columnCount - 1,
                       flow.pageBreakBeforeBoundary(near: NSMaxRange(column.characters)) != nil { break }
                    if column.finished { pageFinished = true; break }
                }
                guard let firstColumn = columns.first, let lastColumn = columns.last else {
                    throw WriterError.message("PDF pagination produced no text column.")
                }
                pageCharacters = NSRange(location: firstColumn.characters.location,
                                         length: max(0, NSMaxRange(lastColumn.characters) - firstColumn.characters.location))
                let dynamicCandidateImages = resolvedFloatingImages(
                    floatingImages,
                    pageIndex: pageNumber,
                    pageRange: pageCharacters,
                    columnCharacterRanges: columns.map(\.characters),
                    containers: containers,
                    manager: flow.manager,
                    text: text.string,
                    geometry: geometry
                )
                for image in dynamicCandidateImages where image.anchor == .paragraph || image.anchor == .character {
                    if image.anchorOffsetX != nil, image.anchorOffsetY != nil,
                       resolvedAnchorSnapshots[image.id] == nil {
                        resolvedAnchorSnapshots[image.id] = image
                    }
                }
                let candidateImages = FloatingImageLayout.applyingAnchorSnapshots(
                    dynamicCandidateImages,
                    snapshots: resolvedAnchorSnapshots,
                    pageIndex: pageNumber
                )
                if !sameFloatingImageLayout(activePageImages, candidateImages) {
                    let signature = candidateImages
                        .filter { $0.anchor == .paragraph || $0.anchor == .character }
                        .sorted { $0.id.uuidString < $1.id.uuidString }
                        .map { "\($0.id.uuidString):\(Int(($0.x * 10).rounded())):\(Int(($0.y * 10).rounded()))" }
                        .joined(separator: "|")
                    guard seenAnchorStates.insert(signature).inserted else {
                        throw WriterError.message("Text-anchored image wrapping oscillated on page \(pageNumber + 1). No PDF was written.")
                    }
                    activePageImages = candidateImages
                    continue
                }
                activePageImages = candidateImages
                pageNotes = try PageFootnotes.plan(
                    geometry: geometry,
                    references: PageFootnotes.notes(on: pageCharacters, from: footnotes),
                    incoming: continuingFootnotes
                )
                if pageNotes.reservedHeight <= reserved + 0.5 {
                    converged = true
                    break
                }
                reserved = pageNotes.reservedHeight
            }
            guard converged else {
                throw WriterError.message("Footnote pagination did not converge within 32 passes. No PDF was written.")
            }

            // Word balances the terminal page of a multi-column
            // final section unless w:noColumnBalance disables it.
            //
            // Stage 2C deliberately excludes structural cases that
            // have not yet had independent ownership semantics proven:
            // footnotes, continuous section starts, next-column starts,
            // and explicit terminal structural breaks.
            if pageFinished,
               columnCount > 1,
               reserved <= 0.5,
               continuingFootnotes.isEmpty,
               pageNotes.outgoing.isEmpty,
               text.length > startCharacter,
               !flow.hasStructuralBreak(
                    atEndOf:
                        pageCharacters
               ) {

                let finalSection =
                    section(
                        at:
                            max(
                                0,
                                text.length - 1
                            ),
                        in:
                            sections
                    )

                if finalSection.location
                    == currentSection.location {

                    let remainingCharacters =
                        NSRange(
                            location:
                                startCharacter,
                            length:
                                text.length
                                - startCharacter
                        )

                    if let balancedHeight =
                        try flow
                            .minimumBalancedColumnHeight(
                                for:
                                    remainingCharacters,
                                geometry:
                                    geometry,
                                maximumHeight:
                                    geometry
                                        .contentSize
                                        .height
                            ),
                       balancedHeight.isFinite,
                       balancedHeight > 0,
                       balancedHeight
                        < geometry
                            .contentSize
                            .height
                            - 0.5 {

                        // Full-height sequential flow can reach the end
                        // before TextKit needs every configured column.
                        // Final-page balancing must redistribute across
                        // all configured columns, so materialize any
                        // missing live containers first.
                        while containers.count
                            < columnCount {

                            containers.append(
                                flow.addContainer(
                                    size:
                                        NSSize(
                                            width:
                                                geometry
                                                    .columnWidth,
                                            height:
                                                balancedHeight
                                        )
                                )
                            )
                        }

                        let balancedTarget =
                            NSSize(
                                width:
                                    geometry
                                        .columnWidth,
                                height:
                                    balancedHeight
                            )

                        for container
                            in containers
                                .prefix(
                                    columnCount
                                ) {

                            if container.containerSize
                                != balancedTarget {

                                container.containerSize =
                                    balancedTarget
                            }
                        }

                        flow.manager.invalidateLayout(
                            forCharacterRange:
                                remainingCharacters,
                            actualCharacterRange:
                                nil
                        )

                        columns.removeAll(
                            keepingCapacity:
                                true
                        )

                        pageFinished =
                            false

                        for columnIndex
                            in 0..<columnCount {

                            let container =
                                containers[
                                    columnIndex
                                ]

                            let column =
                                try flow.layout(
                                    container,
                                    geometry:
                                        geometry
                                )

                            columns.append(
                                (
                                    column.glyphs,
                                    column.characters
                                )
                            )

                            if columnIndex
                                < columnCount - 1,
                               flow.pageBreakBeforeBoundary(
                                near:
                                    NSMaxRange(
                                        column.characters
                                    )
                               ) != nil {

                                break
                            }

                            if column.finished {
                                pageFinished =
                                    true
                                break
                            }
                        }

                        guard
                            let firstColumn =
                                columns.first,
                            let lastColumn =
                                columns.last
                        else {
                            throw WriterError.message(
                                "Balanced PDF pagination produced no text column."
                            )
                        }

                        pageCharacters =
                            NSRange(
                                location:
                                    firstColumn
                                        .characters
                                        .location,
                                length:
                                    max(
                                        0,
                                        NSMaxRange(
                                            lastColumn
                                                .characters
                                        )
                                        - firstColumn
                                            .characters
                                            .location
                                    )
                            )

                        guard
                            pageFinished,
                            NSMaxRange(
                                pageCharacters
                            ) >= text.length
                        else {
                            throw WriterError.message(
                                "Balanced PDF final-column layout did not reach the end of the document."
                            )
                        }
                    }
                }
            }

            if !containers.isEmpty,
               reserved <= 0.5,
               continuingFootnotes.isEmpty,
               pageNotes.outgoing.isEmpty,
               !flow.hasStructuralBreak(
                    atEndOf:
                        pageCharacters
               ) {

                for container
                    in containers
                        .prefix(
                            columns.count
                        ) {

                    _ =
                        flow.applyVerticalJustification(
                            in:
                                container,
                            geometry:
                                geometry,
                            availableHeight:
                                min(
                                    geometry
                                        .contentSize
                                        .height,
                                    container
                                        .containerSize
                                        .height
                                ),
                            isEligiblePage:
                                true
                        )
                }
            }

            renderedPageRanges.append(
                pageCharacters
            )

            renderedPageColumnHeights.append(
                Array(
                    containers
                        .prefix(
                            columns.count
                        )
                )
                .map {
                    $0.containerSize.height
                }
            )

            renderedPageColumnBottoms.append(
                Array(
                    containers
                        .prefix(
                            columns.count
                        )
                )
                .map {
                    container in

                    let glyphs =
                        flow.manager
                            .glyphRange(
                                for:
                                    container
                            )

                    var bottom:
                        CGFloat = 0

                    flow.manager
                        .enumerateLineFragments(
                            forGlyphRange:
                                glyphs
                        ) {
                            _,
                            usedRect,
                            textContainer,
                            lineGlyphRange,
                            _ in

                            if textContainer === container,
                               lineGlyphRange.length > 0 {

                                bottom =
                                    max(
                                        bottom,
                                        usedRect.maxY
                                    )
                            }
                        }

                    return bottom
                }
            )

            let resolvedPageImages = activePageImages

            if pageNumber == 0 {
                displayPageNumber =
                    max(
                        1,
                        currentSection.page
                            .pageNumberStart
                        ?? 1
                    )

            } else if startsNewSection,
                      let restart =
                        currentSection.page
                            .pageNumberStart {

                displayPageNumber =
                    max(
                        1,
                        restart
                    )

            } else {
                displayPageNumber +=
                    1
            }

            pageNumber +=
                1

            guard
                pageNumber <= 20_000
            else {
                throw WriterError.message(
                    "This export exceeds 20,000 pages. Export smaller sections."
                )
            }

            context.beginPDFPage(
                pageInfo(
                    size:
                        geometry.size
                )
            )

            context.saveGState()

            context.translateBy(
                x:
                    0,
                y:
                    geometry.size.height
            )

            context.scaleBy(
                x:
                    1,
                y:
                    -1
            )

            NSGraphicsContext
                .saveGraphicsState()

            NSGraphicsContext.current =
                NSGraphicsContext(
                    cgContext:
                        context,
                    flipped:
                        true
                )

            drawFloatingImages(resolvedPageImages, pageIndex: pageNumber - 1,
                               geometry: geometry, layer: .behindText)

            let usedBodyHeight =
                containers
                .prefix(
                    columns.count
                )
                .map {
                    flow.manager
                        .usedRect(
                            for:
                                $0
                        )
                        .height
                }
                .max()
                ?? 0

            let bodyVerticalOffset =
                geometry
                .verticalBodyOffset(
                    usedHeight:
                        usedBodyHeight,
                    availableHeight:
                        max(
                            0,
                            geometry
                                .contentSize
                                .height
                                - reserved
                        )
                )

            for (
                columnIndex,
                column
            ) in columns.enumerated() {

                let origin =
                    NSPoint(
                        x:
                            geometry.columnOriginX(
                                for:
                                    columnIndex
                            ),
                        y:
                            geometry.contentOrigin.y
                            + bodyVerticalOffset
                    )

                flow.manager
                    .drawBackground(
                        forGlyphRange:
                            column.glyphs,
                        at:
                            origin
                    )

                flow.manager
                    .drawGlyphs(
                        forGlyphRange:
                            column.glyphs,
                        at:
                            origin
                    )
            }

            PageFootnotes.draw(pageNotes, in: geometry)

            drawFloatingImages(resolvedPageImages, pageIndex: pageNumber - 1,
                               geometry: geometry, layer: .inFrontOfText)

            geometry.drawFooter(
                page:
                    pageNumber,
                sectionPage:
                    sectionPageNumber,
                displayPage:
                    displayPageNumber
            )

            NSGraphicsContext
                .restoreGraphicsState()

            context.restoreGState()

            context.endPDFPage()

            startCharacter =
                min(
                    text.length,
                    NSMaxRange(
                        pageCharacters
                    )
                )

            continuingFootnotes = pageNotes.outgoing
            finished = pageFinished && continuingFootnotes.isEmpty

        } while !finished
    }

    private static func drawFloatingImages(_ images: [FloatingImage], pageIndex: Int,
                                           geometry: PageGeometry, layer: FloatingImage.Layer) {
        for item in images.filter({ $0.pageIndex == pageIndex && $0.layer == layer })
            .sorted(by: { $0.zOrder < $1.zOrder }) {
            guard let image = item.displayImage() else { continue }
            let origin = item.anchor == .margins
                ? CGPoint(x: geometry.contentOrigin.x + item.x, y: geometry.contentOrigin.y + item.y)
                : CGPoint(x: item.x, y: item.y)
            let rect = CGRect(origin: origin, size: CGSize(width: item.width, height: item.height))
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: item.rotationDegrees)
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Resolves text anchors from the final page containers used for this PDF
    /// page. The same TextKit line-fragment geometry feeds the editor resolver.
    private static func resolvedFloatingImages(
        _ images: [FloatingImage],
        pageIndex: Int,
        pageRange: NSRange,
        columnCharacterRanges: [NSRange],
        containers: [NSTextContainer],
        manager: NSLayoutManager,
        text: String,
        geometry: PageGeometry
    ) -> [FloatingImage] {
        images.compactMap { image in
            guard image.anchor == .paragraph || image.anchor == .character else {
                guard image.pageIndex == pageIndex else { return nil }
                guard image.horizontalAlignment != nil || image.verticalAlignment != nil else { return image }
                return FloatingImageLayout.positionedAtAnchor(image, pageIndex: pageIndex, origin: .zero,
                                                               pageContentOrigin: geometry.contentOrigin,
                                                               pageGeometry: geometry)
            }
            guard image.anchorOffsetX != nil, image.anchorOffsetY != nil else {
                return image.pageIndex == pageIndex ? image : nil
            }
            let target = FloatingImageLayout.textAnchorLocation(anchor: image.anchor,
                                                                location: image.anchorLocation,
                                                                in: text)
            guard NSLocationInRange(target, pageRange),
                  image.anchorOffsetX != nil, image.anchorOffsetY != nil else { return nil }
            for column in columnCharacterRanges.indices where containers.indices.contains(column) {
                let range = columnCharacterRanges[column]
                guard target >= range.location && target <= NSMaxRange(range) else { continue }
                let character = min(target, max(0, manager.textStorage?.length ?? 1) - 1)
                let glyph = manager.glyphIndexForCharacter(at: character)
                guard glyph < manager.numberOfGlyphs else { continue }
                var effective = NSRange(location: 0, length: 0)
                let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective)
                let anchorRect = image.anchor == .character
                    ? manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: containers[column])
                    : line
                let origin = CGPoint(x: geometry.contentOrigin.x + geometry.columnOriginX(for: column) + anchorRect.minX,
                                     y: geometry.contentOrigin.y + anchorRect.minY)
                let paragraphOrigin = CGPoint(x: geometry.contentOrigin.x + geometry.columnOriginX(for: column) + line.minX,
                                              y: geometry.contentOrigin.y + line.minY)
                return FloatingImageLayout.positionedAtAnchor(image, pageIndex: pageIndex, origin: origin,
                                                               pageContentOrigin: geometry.contentOrigin,
                                                               paragraphOrigin: paragraphOrigin,
                                                               pageGeometry: geometry)
            }
            return nil
        }
    }

    private static func sameFloatingImageLayout(_ lhs: [FloatingImage], _ rhs: [FloatingImage]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let left = Dictionary(uniqueKeysWithValues: lhs.map { ($0.id, $0) })
        let right = Dictionary(uniqueKeysWithValues: rhs.map { ($0.id, $0) })
        guard left.count == right.count else { return false }
        return left.allSatisfy { id, image in
            guard let candidate = right[id] else { return false }
            return abs(image.x - candidate.x) < 0.05 && abs(image.y - candidate.y) < 0.05
                && image.pageIndex == candidate.pageIndex
        }
    }

}
