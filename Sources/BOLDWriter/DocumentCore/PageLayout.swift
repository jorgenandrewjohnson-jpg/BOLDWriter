import AppKit

/// Layout coordinates are always unscaled typographic points, shared by screen and PDF.
struct PageGeometry {
    let settings: PageSettings
    let size: NSSize
    let contentSize: NSSize
    var contentOrigin: NSPoint

    init(_ settings: PageSettings) throws {
        let size = settings.pageSize
        let gutter = settings.effectiveGutter
        let sideGutter =
            settings.usesGutterAtTop
            ? 0
            : gutter
        let topGutter =
            settings.usesGutterAtTop
            ? gutter
            : 0
        let margins = [
            settings.leftMargin,
            settings.rightMargin,
            settings.topMargin,
            settings.bottomMargin,
            gutter
        ]
        guard margins.allSatisfy({ $0.isFinite && $0 >= 0 }),
              size.width
                - settings.leftMargin
                - settings.rightMargin
                - sideGutter >= 72,
              size.height
                - settings.topMargin
                - settings.bottomMargin
                - topGutter >= 72 else {
            throw WriterError.message("The page margins leave too little room for writing. Reduce them in the Inspector.")
        }
        self.settings = settings
        self.size = size
        contentSize = NSSize(
            width:
                size.width
                - settings.leftMargin
                - settings.rightMargin
                - sideGutter,
            height:
                size.height
                - settings.topMargin
                - settings.bottomMargin
                - topGutter
        )
        contentOrigin = NSPoint(
            x:
                settings.leftMargin
                + sideGutter,
            y:
                settings.topMargin
                + topGutter
        )
    }

    /// Resolves Word mirrored facing-page margins for a specific
    /// physical page without changing the underlying section settings.
    func resolvingPhysicalPage(
        _ physicalPage: Int
    ) -> PageGeometry {
        guard
            settings.usesMirrorMargins,
            max(
                1,
                physicalPage
            )
            .isMultiple(
                of: 2
            )
        else {
            return self
        }

        var resolved =
            self

        resolved.contentOrigin.x =
            CGFloat(
                settings.rightMargin
            )

        return resolved
    }

    /// Returns the completed-page body offset for Word section
    /// vertical page alignment. TextKit must lay out the page first,
    /// because center and bottom depend on the final used body height.
    func verticalBodyOffset(
        usedHeight: CGFloat,
        availableHeight: CGFloat? = nil
    ) -> CGFloat {
        let available =
            max(
                0,
                availableHeight
                    ?? contentSize.height
            )

        let safeUsed =
            min(
                available,
                max(
                    0,
                    usedHeight.isFinite
                        ? usedHeight
                        : 0
                )
            )

        let remaining =
            max(
                0,
                available
                    - safeUsed
            )

        switch settings.effectiveVerticalPageAlignment {
        case .top:
            return 0

        case .center:
            return remaining / 2

        case .bottom:
            return remaining

        case .both:
            // Word's vertically justified page alignment is not a
            // whole-body translation. Its residual printable height
            // must be distributed between eligible TextKit lines.
            return 0
        }
    }

    /// Returns the additional vertical distance available between
    /// adjacent paragraphs for Word w:vAlign='both'.
    ///
    /// Word vertical justification preserves normal visual-line leading
    /// within a paragraph and consumes residual printable height only
    /// between distinct paragraph groups.
    func verticalJustificationInterparagraphExpansion(
        usedHeight: CGFloat,
        availableHeight: CGFloat? = nil,
        paragraphCount: Int,
        isEligiblePage: Bool
    ) -> CGFloat {
        guard
            settings.effectiveVerticalPageAlignment == .both,
            isEligiblePage,
            paragraphCount > 1
        else {
            return 0
        }

        let available =
            max(
                0,
                availableHeight
                    ?? contentSize.height
            )

        let safeUsed =
            min(
                available,
                max(
                    0,
                    usedHeight.isFinite
                        ? usedHeight
                        : 0
                )
            )

        let remaining =
            max(
                0,
                available
                    - safeUsed
            )

        return remaining
            / CGFloat(
                paragraphCount - 1
            )
    }

    var columnCount: Int {
        settings.effectiveColumnCount
    }

    var columnSpacing: CGFloat {
        CGFloat(settings.effectiveColumnSpacing)
    }

    var columnWidth: CGFloat {
        let count = CGFloat(columnCount)
        let totalSpacing =
            columnSpacing
            * CGFloat(
                max(
                    0,
                    columnCount - 1
                )
            )

        return max(
            1,
            (
                contentSize.width
                - totalSpacing
            ) / count
        )
    }

    func columnOriginX(
        for index: Int
    ) -> CGFloat {
        let safeIndex =
            min(
                max(
                    0,
                    index
                ),
                columnCount - 1
            )

        return contentOrigin.x
            + CGFloat(safeIndex)
                * (
                    columnWidth
                    + columnSpacing
                )
    }

    func furniture(
        page: Int,
        sectionPage: Int? = nil
    ) -> (
        headerText: String,
        footerText: String,
        hidden: Bool
    ) {
        let resolvedSectionPage =
            max(
                1,
                sectionPage
                    ?? page
            )

        if resolvedSectionPage == 1 {
            if settings
                .hidesHeaderFooterOnFirstPage {

                return (
                    headerText: "",
                    footerText: "",
                    hidden: true
                )
            }

            if settings
                .hasDistinctFirstPageHeaderFooter {

                return (
                    headerText:
                        settings
                            .effectiveFirstPageHeaderText,
                    footerText:
                        settings
                            .effectiveFirstPageFooterText,
                    hidden: false
                )
            }
        }

        if settings
            .usesDifferentOddEvenHeaderFooter,
           page.isMultiple(of: 2) {

            return (
                headerText:
                    settings
                        .effectiveEvenPageHeaderText,
                footerText:
                    settings
                        .effectiveEvenPageFooterText,
                hidden: false
            )
        }

        return (
            headerText:
                settings
                    .effectiveHeaderText,
            footerText:
                settings
                    .footerText,
            hidden: false
        )
    }

    func drawFooter(
        page: Int,
        sectionPage: Int? = nil,
        displayPage: Int? = nil
    ) {
        drawHeaderAndFooter(
            page:
                page,
            sectionPage:
                sectionPage,
            displayPage:
                displayPage
        )
    }

    func drawHeaderAndFooter(
        page: Int,
        sectionPage: Int? = nil,
        displayPage: Int? = nil
    ) {
        let furniture =
            furniture(
                page:
                    page,
                sectionPage:
                    sectionPage
            )

        let usesFirst = (sectionPage ?? page) == 1 && settings.hasDistinctFirstPageHeaderFooter
        let settings = self.settings.resolvingEvenFooter(
            !usesFirst && self.settings.usesDifferentOddEvenHeaderFooter && page.isMultiple(of: 2)
        )

        let pageNumberText =
            settings.formattedPageNumber(
                displayPage
                ?? page
            )

        guard
            !furniture.hidden
        else {
            return
        }

        let attributes:
            [NSAttributedString.Key: Any] = [
                .font:
                    NSFont.systemFont(
                        ofSize: 9
                    ),
                .foregroundColor:
                    NSColor.darkGray
            ]

        // AppKit's string drawing origin is a typographic line origin. A
        // zero-distance Word footer therefore places the descender below
        // the physical page edge. Keep the historical placement whenever
        // the configured distance is sufficient, and only raise it enough
        // to fit the complete 9 pt line box on the page, with one point of
        // clearance for PDF text-matrix rounding.
        let footerBaselineOffset: CGFloat = 5
        let footerLineHeight =
            (NSFont.systemFont(ofSize: 9).boundingRectForFont.height)
        let minimumFooterDistance =
            max(0, ceil(footerLineHeight) - footerBaselineOffset + 1)
        let footerDistance =
            max(settings.effectiveFooterDistance, Double(minimumFooterDistance))

        if settings
            .usesLegacyFooterLayout {

            guard
                (settings.footerDistance != nil || settings.bottomMargin >= 18)
            else {
                return
            }

            let parts = [
                furniture.footerText,
                settings.showsPageNumbers
                    ? pageNumberText
                    : ""
            ]
            .filter {
                !$0.isEmpty
            }

            guard
                !parts.isEmpty
            else {
                return
            }

            (
                parts.joined(
                    separator:
                        "   •   "
                )
                as NSString
            )
            .draw(
                at:
                    NSPoint(
                        x:
                            contentOrigin.x,
                        y:
                            size.height
                            - footerDistance
                            - footerBaselineOffset
                    ),
                withAttributes:
                    attributes
            )

            return
        }

        if (settings.headerDistance != nil || settings.topMargin >= 18),
           !furniture.headerText.isEmpty {

            drawFurnitureText(
                furniture.headerText,
                position:
                    settings
                        .effectiveHeaderPosition,
                y:
                    settings.effectiveHeaderDistance
                    - 5,
                attributes:
                    attributes
            )
        }

        guard
            (settings.footerDistance != nil || settings.bottomMargin >= 18)
        else {
            return
        }

        let footerY =
            size.height
            - footerDistance
            - footerBaselineOffset

        if settings.showsPageNumbers {
            let number =
                pageNumberText

            if !furniture.footerText.isEmpty
                && settings
                    .effectiveFooterPosition
                    == settings
                        .effectivePageNumberPosition {

                drawFurnitureText(
                    furniture.footerText
                    + "   •   "
                    + number,
                    position:
                        settings
                            .effectiveFooterPosition,
                    y:
                        footerY,
                    attributes:
                        attributes
                )

            } else {
                if !furniture.footerText.isEmpty {
                    drawFurnitureText(
                        furniture.footerText,
                        position:
                            settings
                                .effectiveFooterPosition,
                        y:
                            footerY,
                        attributes:
                            attributes
                    )
                }

                drawFurnitureText(
                    number,
                    position:
                        settings
                            .effectivePageNumberPosition,
                    y:
                        footerY,
                    attributes:
                        attributes
                )
            }
        } else if !furniture.footerText.isEmpty {
            drawFurnitureText(
                furniture.footerText,
                position:
                    settings
                        .effectiveFooterPosition,
                y:
                    footerY,
                attributes:
                    attributes
            )
        }
    }

    private func drawFurnitureText(
        _ text: String,
        position: PageSettings.HorizontalPosition,
        y: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard !text.isEmpty else { return }

        let string = text as NSString
        let measured = string.size(withAttributes: attributes)

        let x: CGFloat

        switch position {
        case .left:
            x = contentOrigin.x

        case .center:
            x = contentOrigin.x
                + max(0, (contentSize.width - measured.width) / 2)

        case .right:
            x = contentOrigin.x
                + max(0, contentSize.width - measured.width)
        }

        string.draw(
            at: NSPoint(x: x, y: y),
            withAttributes: attributes
        )
    }
}

/// One storage and one layout manager. Each finite container continues the same
/// glyph stream; no page contains an independent copy or substring of the document.
final class PageLayout: NSObject, NSLayoutManagerDelegate {
    let storage: NSTextStorage
    let manager: NSLayoutManager
    var paginated = true
    var sectionBreakLocations: Set<Int> = []
    private var paragraphKeepBreakLocations: Set<Int> = []

    // Tracks containers whose real NSLayoutManager line-fragment
    // geometry has been redistributed for Word w:vAlign='both'.
    // Any later pagination pass restores normal TextKit geometry first.
    private var verticallyJustifiedContainers:
        Set<ObjectIdentifier> = []

    func resetParagraphKeepBreaks() {
        paragraphKeepBreakLocations.removeAll()
    }

    init(storage: NSTextStorage, manager: NSLayoutManager) {
        self.storage = storage; self.manager = manager
        super.init()
        manager.delegate = self
        manager.allowsNonContiguousLayout = false
        manager.backgroundLayoutEnabled = false
    }

    convenience init(text: NSAttributedString) {
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        self.init(storage: storage, manager: manager)
    }

    private func isSectionBreakControlCharacter(
        _ character: UInt16
    ) -> Bool {
        character == 10
            || character == 13
            || character == 0x2028
            || character == 0x2029
    }

    func pageBreakBeforeBoundary(
        near location: Int
    ) -> Int? {
        guard storage.length > 0 else {
            return nil
        }

        let lower =
            max(
                1,
                location - 1
            )

        let upper =
            min(
                storage.length - 1,
                location + 1
            )

        guard lower <= upper else {
            return nil
        }

        for candidate
            in lower...upper {

            guard
                storage.attribute(
                    .boldWriterPageBreakBefore,
                    at:
                        candidate,
                    effectiveRange:
                        nil
                ) as? Bool == true
            else {
                continue
            }

            let previous =
                (
                    storage.string
                        as NSString
                )
                .character(
                    at:
                        candidate - 1
                )

            if isSectionBreakControlCharacter(
                previous
            ) {
                return candidate
            }
        }

        return nil
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action:
            NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard
            charIndex < storage.length
        else {
            return action
        }

        let character =
            (
                storage.string
                as NSString
            )
            .character(
                at:
                    charIndex
            )

        if character == 12 {
            return paginated
                ? .containerBreak
                : .paragraphBreak
        }

        if paginated,
           sectionBreakLocations.contains(
                charIndex + 1
           ),
           isSectionBreakControlCharacter(
                character
           ) {

            return .containerBreak
        }

        if paginated,
           paragraphKeepBreakLocations.contains(
                charIndex + 1
           ),
           isSectionBreakControlCharacter(
                character
           ) {

            return .containerBreak
        }

        if paginated,
           charIndex + 1 < storage.length,
           isSectionBreakControlCharacter(
                character
           ),
           storage.attribute(
                .boldWriterPageBreakBefore,
                at:
                    charIndex + 1,
                effectiveRange:
                    nil
           ) as? Bool == true {

            return .containerBreak
        }

        return action
    }

    /// Returns true when a container ended because of a structural
    /// pagination boundary rather than because printable height was full.
    ///
    /// Word w:vAlign='both' must not stretch a page whose early ending
    /// is caused by a manual page break, section break, explicit
    /// page-break-before setting, or BOLD paragraph keep rule.
    func hasStructuralBreak(
        atEndOf characters: NSRange
    ) -> Bool {
        guard
            characters.location != NSNotFound,
            characters.length > 0,
            storage.length > 0
        else {
            return false
        }

        let boundary =
            min(
                storage.length,
                NSMaxRange(
                    characters
                )
            )

        if let _ =
            pageBreakBeforeBoundary(
                near:
                    boundary
            ) {

            return true
        }

        if paragraphKeepBreakLocations
            .contains(
                boundary
            ) {

            return true
        }

        let finalIndex =
            min(
                storage.length - 1,
                max(
                    0,
                    boundary - 1
                )
            )

        let character =
            (
                storage.string
                as NSString
            )
            .character(
                at:
                    finalIndex
            )

        if character == 12 {
            return true
        }

        return sectionBreakLocations
            .contains(
                boundary
            )
            && isSectionBreakControlCharacter(
                character
            )
    }

    /// Restores ordinary TextKit geometry for a container that was
    /// previously redistributed for Word w:vAlign='both'.
    func restoreVerticalJustification(
        in container: NSTextContainer
    ) {
        let identifier =
            ObjectIdentifier(
                container
            )

        guard
            verticallyJustifiedContainers
                .remove(
                    identifier
                )
                != nil
        else {
            return
        }

        let glyphRange =
            manager.glyphRange(
                for:
                    container
            )

        guard
            glyphRange.location
                != NSNotFound,
            glyphRange.length > 0
        else {
            return
        }

        let characterRange =
            manager.characterRange(
                forGlyphRange:
                    glyphRange,
                actualGlyphRange:
                    nil
            )

        guard
            characterRange.location
                != NSNotFound,
            characterRange.length > 0
        else {
            return
        }

        manager.invalidateLayout(
            forCharacterRange:
                characterRange,
            actualCharacterRange:
                nil
        )

        manager.ensureLayout(
            for:
                container
        )
    }

    /// Redistributes the residual printable height between real
    /// NSLayoutManager line fragments for Word w:vAlign='both'.
    ///
    /// This runs only after normal pagination has established the
    /// glyph/character range. It changes layout geometry, not text or
    /// container size, so selection, caret placement, hit testing and
    /// drawing all read the same TextKit positions.
    @discardableResult
    func applyVerticalJustification(
        in container: NSTextContainer,
        geometry: PageGeometry,
        availableHeight: CGFloat,
        isEligiblePage: Bool
    ) -> CGFloat {
        restoreVerticalJustification(
            in:
                container
        )

        guard
            geometry
                .settings
                .effectiveVerticalPageAlignment
                == .both,
            isEligiblePage,
            availableHeight.isFinite,
            availableHeight > 0
        else {
            return 0
        }

        let glyphRange =
            manager.glyphRange(
                for:
                    container
            )

        guard
            glyphRange.location
                != NSNotFound,
            glyphRange.length > 0
        else {
            return 0
        }

        guard
            storage.length > 0
        else {
            return 0
        }

        struct Fragment {
            let fragmentRect: NSRect
            let usedRect: NSRect
            let glyphRange: NSRange
            let paragraphStart: Int
        }

        struct NeighborFragment {
            let fragmentRect: NSRect
            let usedRect: NSRect
            let glyphRange: NSRange
        }

        var fragments:
            [Fragment] = []

        let string =
            storage.string
                as NSString

        manager.enumerateLineFragments(
            forGlyphRange:
                glyphRange
        ) {
            fragmentRect,
            usedRect,
            textContainer,
            lineGlyphRange,
            _ in

            guard
                textContainer === container,
                lineGlyphRange.location
                    != NSNotFound,
                lineGlyphRange.length > 0
            else {
                return
            }

            let characters =
                self.manager
                    .characterRange(
                        forGlyphRange:
                            lineGlyphRange,
                        actualGlyphRange:
                            nil
                    )

            guard
                characters.location
                    != NSNotFound
            else {
                return
            }

            let characterLocation =
                min(
                    max(
                        0,
                        characters.location
                    ),
                    max(
                        0,
                        self.storage.length - 1
                    )
                )

            let paragraph =
                string.paragraphRange(
                    for:
                        NSRange(
                            location:
                                characterLocation,
                            length:
                                0
                        )
                )

            fragments.append(
                Fragment(
                    fragmentRect:
                        fragmentRect,
                    usedRect:
                        usedRect,
                    glyphRange:
                        lineGlyphRange,
                    paragraphStart:
                        paragraph.location
                )
            )
        }

        guard
            fragments.count > 1
        else {
            return 0
        }

        var paragraphOrder:
            [Int] = []

        var seenParagraphs:
            Set<Int> = []

        for fragment in fragments {
            if seenParagraphs
                .insert(
                    fragment.paragraphStart
                )
                .inserted {

                paragraphOrder.append(
                    fragment.paragraphStart
                )
            }
        }

        // A page containing only one wrapped paragraph keeps its normal
        // line leading. There is no inter-paragraph gap to expand.
        guard
            paragraphOrder.count > 1
        else {
            return 0
        }

        let usedHeight =
            manager.usedRect(
                for:
                    container
            )
            .height

        // A balanced final multi-column page can leave a tiny
        // sub-point residual because minimumBalancedColumnHeight uses a
        // floating-point threshold. Redistributing that microscopic slack
        // is visually meaningless and can perturb a linked TextKit
        // neighbor container.
        //
        // Treat half a point or less of TOTAL residual height as zero.
        let residualHeight =
            availableHeight
                - usedHeight

        guard
            residualHeight.isFinite,
            residualHeight > 0.5
        else {
            return 0
        }

        let expansion =
            geometry
                .verticalJustificationInterparagraphExpansion(
                    usedHeight:
                        usedHeight,
                    availableHeight:
                        availableHeight,
                    paragraphCount:
                        paragraphOrder.count,
                    isEligiblePage:
                        isEligiblePage
                )

        guard
            expansion.isFinite,
            expansion > 0
        else {
            return 0
        }

        let paragraphOffsets =
            Dictionary(
                uniqueKeysWithValues:
                    paragraphOrder
                        .enumerated()
                        .map {
                            paragraphIndex,
                            paragraphStart in

                            (
                                paragraphStart,
                                expansion
                                    * CGFloat(
                                        paragraphIndex
                                    )
                            )
                        }
            )

        // NSTextContainers share one NSLayoutManager. AppKit may update
        // downstream fragment origins when an earlier container changes.
        // Preserve already-laid-out neighboring geometry while this page
        // receives its Word paragraph spacing.
        var neighborFragments:
            [ObjectIdentifier:
                [NeighborFragment]] =
                    [:]

        for otherContainer
            in manager.textContainers {

            guard
                otherContainer !== container
            else {
                continue
            }

            let otherGlyphs =
                manager.glyphRange(
                    for:
                        otherContainer
                )

            guard
                otherGlyphs.location
                    != NSNotFound,
                otherGlyphs.length > 0
            else {
                continue
            }

            var snapshots:
                [NeighborFragment] = []

            manager.enumerateLineFragments(
                forGlyphRange:
                    otherGlyphs
            ) {
                fragmentRect,
                usedRect,
                textContainer,
                lineGlyphRange,
                _ in

                guard
                    textContainer === otherContainer,
                    lineGlyphRange.location
                        != NSNotFound,
                    lineGlyphRange.length > 0
                else {
                    return
                }

                snapshots.append(
                    NeighborFragment(
                        fragmentRect:
                            fragmentRect,
                        usedRect:
                            usedRect,
                        glyphRange:
                            lineGlyphRange
                    )
                )
            }

            if !snapshots.isEmpty {
                neighborFragments[
                    ObjectIdentifier(
                        otherContainer
                    )
                ] =
                    snapshots
            }
        }

        for fragment in fragments {
            let shift =
                paragraphOffsets[
                    fragment.paragraphStart
                ]
                ?? 0

            var fragmentRect =
                fragment.fragmentRect

            fragmentRect.origin.y +=
                shift

            var usedRect =
                fragment.usedRect

            usedRect.origin.y +=
                shift

            manager.setLineFragmentRect(
                fragmentRect,
                forGlyphRange:
                    fragment.glyphRange,
                usedRect:
                    usedRect
            )
        }

        for snapshots
            in neighborFragments.values {

            for snapshot in snapshots {
                manager.setLineFragmentRect(
                    snapshot.fragmentRect,
                    forGlyphRange:
                        snapshot.glyphRange,
                    usedRect:
                        snapshot.usedRect
                )
            }
        }

        verticallyJustifiedContainers
            .insert(
                ObjectIdentifier(
                    container
                )
            )

        return expansion
    }

    func addContainer(size: NSSize) -> NSTextContainer {
        let container = NSTextContainer(containerSize: size)
        container.widthTracksTextView = false; container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        return container
    }

    func addColumnContainer(
        geometry: PageGeometry
    ) -> NSTextContainer {
        addContainer(
            size:
                NSSize(
                    width:
                        geometry.columnWidth,
                    height:
                        geometry.contentSize.height
                )
        )
    }

    private func requiredParagraphKeepBreak(
        for characters: NSRange
    ) -> Int? {
        guard
            paginated,
            characters.length > 0,
            NSMaxRange(characters) < storage.length
        else {
            return nil
        }

        let string =
            storage.string
                as NSString

        let boundary =
            NSMaxRange(
                characters
            )

        let finalCharacter =
            max(
                characters.location,
                boundary - 1
            )

        let finalParagraph =
            string.paragraphRange(
                for:
                    NSRange(
                        location:
                            finalCharacter,
                        length:
                            0
                    )
            )

        if boundary
            < NSMaxRange(
                finalParagraph
            ),
           finalParagraph.location
            > characters.location,
           storage.attribute(
            .boldWriterKeepLinesTogether,
            at:
                finalParagraph.location,
            effectiveRange:
                nil
           ) as? Bool == true {

            return finalParagraph.location
        }

        if boundary
            < NSMaxRange(
                finalParagraph
            ),
           finalParagraph.location
            > characters.location,
           storage.attribute(
            .boldWriterWidowControl,
            at:
                finalParagraph.location,
            effectiveRange:
                nil
           ) as? Bool == true {

            let paragraphGlyphs =
                manager.glyphRange(
                    forCharacterRange:
                        finalParagraph,
                    actualCharacterRange:
                        nil
                )

            var lineRanges:
                [NSRange] = []

            manager.enumerateLineFragments(
                forGlyphRange:
                    paragraphGlyphs
            ) {
                _,
                _,
                _,
                lineGlyphRange,
                _ in

                let lineCharacters =
                    self.manager
                        .characterRange(
                            forGlyphRange:
                                lineGlyphRange,
                            actualGlyphRange:
                                nil
                        )

                if lineCharacters.length > 0 {
                    lineRanges.append(
                        lineCharacters
                    )
                }
            }

            if lineRanges.count >= 3 {
                let before =
                    lineRanges.filter {
                        NSMaxRange(
                            $0
                        ) <= boundary
                    }
                    .count

                let after =
                    lineRanges.count
                    - before

                if before < 2
                    || after < 2 {

                    return finalParagraph.location
                }
            }
        }

        if boundary > 0 {
            let previousParagraph =
                string.paragraphRange(
                    for:
                        NSRange(
                            location:
                                boundary - 1,
                            length:
                                0
                        )
                )

            if NSMaxRange(
                previousParagraph
            ) == boundary,
               previousParagraph.location
                > characters.location,
               storage.attribute(
                .boldWriterKeepWithNext,
                at:
                    previousParagraph.location,
                effectiveRange:
                    nil
               ) as? Bool == true {

                return previousParagraph.location
            }
        }

        return nil
    }

    private func enforceParagraphKeepRules(
        in container: NSTextContainer
    ) {
        for _
            in 0..<32 {

            manager.ensureLayout(
                for:
                    container
            )

            let glyphs =
                manager.glyphRange(
                    for:
                        container
                )

            let characters =
                manager.characterRange(
                    forGlyphRange:
                        glyphs,
                    actualGlyphRange:
                        nil
                )

            guard
                let breakLocation =
                    requiredParagraphKeepBreak(
                        for:
                            characters
                    ),
                breakLocation > 0,
                !paragraphKeepBreakLocations.contains(
                    breakLocation
                )
            else {
                return
            }

            paragraphKeepBreakLocations.insert(
                breakLocation
            )

            let invalidationStart =
                max(
                    0,
                    breakLocation - 1
                )

            manager.invalidateLayout(
                forCharacterRange:
                    NSRange(
                        location:
                            invalidationStart,
                        length:
                            storage.length
                                - invalidationStart
                    ),
                actualCharacterRange:
                    nil
            )
        }
    }

    /// Lays out only through this container. Earlier valid TextKit layout is reused.
    func layout(_ container: NSTextContainer, geometry: PageGeometry) throws -> (glyphs: NSRange, characters: NSRange, finished: Bool) {
        restoreVerticalJustification(
            in:
                container
        )
        manager.ensureLayout(for: container)
        enforceParagraphKeepRules(
            in:
                container
        )
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        if glyphs.length == 0 && manager.firstUnlaidCharacterIndex() < storage.length {
            throw WriterError.message("A paragraph, table row, or image cannot fit on this page. Use Continuous mode to reduce its size or increase the printable area.")
        }
        var oversized = false
        storage.enumerateAttribute(.attachment, in: characters) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            let bounds = attachment.bounds.size
            let size = bounds.width > 0 && bounds.height > 0 ? bounds : attachment.attachmentCell?.cellSize() ?? .zero
            if size.width > geometry.contentSize.width + 0.5 || size.height > geometry.contentSize.height + 0.5 { oversized = true }
        }
        guard !oversized else {
            throw WriterError.message("An inline image is larger than the printable page. Use Continuous mode to resize it or adjust the page settings. The image has not been changed.")
        }
        let atEnd =
            NSMaxRange(
                characters
            ) >= storage.length

        let terminalControlCharacter:
            UInt16? =
                storage.length > 0
                ? (
                    storage.string
                    as NSString
                )
                .character(
                    at:
                        storage.length - 1
                )
                : nil

        let terminalManualBreak =
            atEnd
            && characters.length > 0
            && terminalControlCharacter == 12

        let terminalSectionBreak =
            atEnd
            && characters.length > 0
            && sectionBreakLocations.contains(
                storage.length
            )
            && terminalControlCharacter.map {
                isSectionBreakControlCharacter(
                    $0
                )
            } == true

        return (
            glyphs,
            characters,
            atEnd
                && !terminalManualBreak
                && !terminalSectionBreak
        )
    }


    /// Finds the minimum common TextKit container height that lets the
    /// supplied final-section text range finish within the configured
    /// number of columns.
    ///
    /// The search is intentionally performed in temporary TextKit state.
    /// Live screen/PDF containers are never resized or mutated while the
    /// candidate heights are being evaluated.
    ///
    /// Returning nil means balancing is inapplicable or disabled:
    /// - single-column geometry
    /// - Word w:noColumnBalance
    /// - empty/invalid text range
    /// - the supplied text does not fit within all configured columns
    ///   even at the maximum permitted height
    func minimumBalancedColumnHeight(
        for characters: NSRange,
        geometry: PageGeometry,
        maximumHeight: CGFloat? = nil,
        searchIterations: Int = 28
    ) throws -> CGFloat? {
        guard
            geometry.columnCount > 1,
            !geometry
                .settings
                .disablesColumnBalancing,
            characters.location
                != NSNotFound,
            characters.location >= 0,
            characters.length > 0,
            NSMaxRange(
                characters
            ) <= storage.length
        else {
            return nil
        }

        let fullHeight =
            min(
                geometry.contentSize.height,
                maximumHeight
                    ?? geometry.contentSize.height
            )

        guard
            fullHeight.isFinite,
            fullHeight > 1
        else {
            return nil
        }

        let attributed =
            storage.attributedSubstring(
                from:
                    characters
            )

        guard attributed.length > 0 else {
            return nil
        }

        func finishes(
            at height: CGFloat,
            suppressLayoutFailure: Bool
        ) throws -> Bool {
            guard
                height.isFinite,
                height > 0
            else {
                return false
            }

            let candidate =
                PageLayout(
                    text:
                        attributed
                )

            candidate.paginated =
                true

            do {
                for _
                    in 0..<geometry.columnCount {

                    let container =
                        candidate.addContainer(
                            size:
                                NSSize(
                                    width:
                                        geometry.columnWidth,
                                    height:
                                        height
                                )
                        )

                    let result =
                        try candidate.layout(
                            container,
                            geometry:
                                geometry
                        )

                    if result.finished {
                        return true
                    }
                }
            } catch {
                if suppressLayoutFailure {
                    return false
                }

                throw error
            }

            return false
        }

        // If the bounded section content cannot finish within all
        // configured columns at full printable height, this is not an
        // eligible final-page balancing problem.
        guard
            try finishes(
                at:
                    fullHeight,
                suppressLayoutFailure:
                    false
            )
        else {
            return nil
        }

        var lower:
            CGFloat = 1

        var upper =
            fullHeight

        let iterations =
            max(
                1,
                min(
                    40,
                    searchIterations
                )
            )

        for _
            in 0..<iterations {

            let candidateHeight =
                (
                    lower
                    + upper
                )
                / 2

            if try finishes(
                at:
                    candidateHeight,
                suppressLayoutFailure:
                    true
            ) {
                upper =
                    candidateHeight
            } else {
                lower =
                    candidateHeight
            }
        }

        // Keep the returned height microscopically above the binary
        // threshold so AppKit floating-point rounding cannot push the
        // last line into an additional container.
        let resolved =
            min(
                fullHeight,
                upper + 0.05
            )

        guard
            try finishes(
                at:
                    resolved,
                suppressLayoutFailure:
                    false
            )
        else {
            return nil
        }

        return resolved
    }

}
