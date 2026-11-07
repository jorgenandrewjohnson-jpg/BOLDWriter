import AppKit
import Foundation

/// Scene dimensions are expressed in inches. Cover panel locations always come
/// from CoverWrapGeometry; this type only maps those panels into a book model.
struct PhysicalBookGeometry: Equatable {
    /// KDP calculator output for the verified 5.5 × 8.5 inch, 391-page,
    /// black-ink white-paper case laminate profile.
    static let kdpMeasured391HardcoverLayout = KDPHardcoverLayout(
        canvasWidth: 13.644, canvasHeight: 9.917,
        trimWidth: 5.5, trimHeight: 8.5,
        spineWidth: 1.07, pageCount: 391
    )
    let cover: CoverWrapGeometry
    let trimWidth: Double
    let trimHeight: Double
    let spineWidth: Double

    init(project: CoverProject) {
        // BOLD_KDP_PHYSICAL_DEPTH_V24B
        //
        // A named KDP template is authoritative for its own physical wrap.
        // Repair stale project metadata in-memory before deriving panel geometry.
        let effectiveProject:
            CoverProject

        if
            project.activeKDPHardcoverLayout == nil,
            let specification =
                Self
                .importedKDPTemplateSpecification(
                    name:
                        project.name
                ),
            let exactSpine =
                Self
                .expectedSpine(
                    pageCount:
                        specification
                            .pageCount,
                    caliper:
                        specification
                            .caliper
                ),
            let repaired =
                Self
                .resizedPrintCover(
                    project,
                    spineWidth:
                        exactSpine,
                    pageCount:
                        specification
                            .pageCount,
                    caliper:
                        specification
                            .caliper
                )
        {
            effectiveProject =
                repaired
        } else {
            effectiveProject =
                project
        }

        cover =
            CoverWrapGeometry(
                project:
                    effectiveProject
            )

        trimWidth =
            effectiveProject
                .trimWidth

        trimHeight =
            effectiveProject
                .trimHeight

        // A measured PDF gives the outside case spine. Subtract board thickness
        // once; outerBookDepth adds it back. Legacy paper-caliper projects retain
        // their original interpretation.
        spineWidth = effectiveProject.activeKDPHardcoverLayout.map {
            max(0, $0.spineWidth - Self.kdpHardcoverCaseDepthAllowanceInches)
        } ?? cover.spineWidth
    }

    /// Exact physical paper-stack depth. For KDP print projects this is the
    /// authoritative page-count × paper-caliper spine measurement.
    var paperBlockDepth:
        Double
    {
        max(
            0,
            spineWidth
        )
    }

    /// The closed outside thickness includes the paper block PLUS the two
    /// physical cover boards. The old model incorrectly subtracted boards from
    /// the KDP spine measurement.
    func outerBookDepth(
        for binding:
            BookBinding
    ) -> Double {
        paperBlockDepth
        + 2
        * coverThickness(
            for:
                binding
        )
    }


    // BOLD_WRITER_V27_EXACT_KDP_HARDCOVER_CASE
    static let kdpHardcoverCaseDepthAllowanceInches =
        4.8 / 25.4

    static let kdpHardcoverBoardThicknessInches =
        2.4 / 25.4

    static let kdpHardcoverHorizontalOverhangInches =
        2.5 / 25.4

    static let kdpHardcoverVerticalOverhangInches =
        3.0 / 25.4

    static let kdpHardcoverHingeChannelInches =
        10.0 / 25.4

    var coverBoardThickness: Double { coverThickness(for: .hardcover) }
    func coverThickness(
        for binding: BookBinding
    ) -> Double {
        switch binding {
        case .hardcover:
            return Self
                .kdpHardcoverBoardThicknessInches

        case .softcover:
            return min(
                0.016,
                paperBlockDepth / 4
            )
        }
    }
    /// Book-local axes: X is across the spread, Y is vertical (trim height), Z is thickness/depth.
    /// The gutter and spine hinge are the shared origin at X=0.
    var gutterOrigin: (x: Double, y: Double, z: Double) { (0, trimHeight / 2, 0) }
    var closedFrontCoverCenter: (x: Double, y: Double, z: Double) {
        (
            trimWidth / 2,
            trimHeight / 2,
            outerBookDepth(for: .hardcover) / 2
                - coverBoardThickness / 2
        )
    }
    var frontCoverHinge: (x: Double, y: Double, z: Double) { (0, trimHeight / 2, closedFrontCoverCenter.z) }
    /// Casebound boards project beyond the trimmed paper on all four edges.
    /// A paperback cover is cut flush with the book block.
    func coverOverhang(
        for binding: BookBinding
    ) -> Double {
        coverHorizontalOverhang(
            for:
                binding
        )
    }

    func coverHorizontalOverhang(
        for binding: BookBinding
    ) -> Double {
        binding == .hardcover
            ? Self
                .kdpHardcoverHorizontalOverhangInches
            : 0
    }

    func coverVerticalOverhang(
        for binding: BookBinding
    ) -> Double {
        binding == .hardcover
            ? Self
                .kdpHardcoverVerticalOverhangInches
            : 0
    }

    func hardcoverHingeChannelWidth(
        for binding: BookBinding
    ) -> Double {
        binding == .hardcover
            ? Self
                .kdpHardcoverHingeChannelInches
            : 0
    }
    var pageBlockNearZ: Double { pageBlockNearZ(for: .hardcover) }
    func pageBlockNearZ(for binding: BookBinding) -> Double {
        -outerBookDepth(for: binding) / 2
        + coverThickness(for: binding)
    }
    func pageBlockDepth(for binding: BookBinding) -> Double {
        paperBlockDepth
    }
    func pageBounds(side: ThumbSide) -> (minX: Double, maxX: Double) {
        side == .left ? (-trimWidth, 0) : (0, trimWidth)
    }
    func stackCenterZ(side: ThumbSide, pageCount: Int, spreadIndex: Int, binding: BookBinding = .hardcover) -> Double {
        let stacks = Self.pageStacks(pageCount: pageCount, spreadIndex: spreadIndex, totalDepth: pageBlockDepth(for: binding))
        let depth = side == .left ? stacks.leftDepth : stacks.rightDepth
        // Each stack grows from its own cover board. The right stack gets
        // thinner as leaves move left; it must not remain at the closed front face.
        return pageBlockNearZ(for: binding) + depth / 2
    }
    var pageBlock: BookBox { BookBox(width: trimWidth, depth: pageBlockDepth(for: .hardcover), height: trimHeight) }
    var closedBook: BookBox {
        BookBox(
            width: trimWidth,
            depth: outerBookDepth(for: .hardcover),
            height: trimHeight
        )
    }
    var fullWrapDimensions: CoverDimensions {
        CoverDimensions(totalWidthInches: cover.physicalWidth, totalHeightInches: cover.physicalHeight)
    }

    /// Returns closed-shell panel coordinates in the full-wrap canvas' normalized space.
    var panelMapping: BookCoverPanelMapping {
        BookCoverPanelMapping(back: cover.backTrim, spine: cover.spineTrim, front: cover.frontTrim)
    }

    func openedFrontCoverCenter(angleDegrees: Double, binding: BookBinding = .hardcover) -> (x: Double, y: Double) {
        let safeAngle = angleDegrees.isFinite ? angleDegrees : 0
        let clamped = min(180, max(0, safeAngle))
        let radians = clamped * .pi / 180
        let radius = trimWidth / 2
        let frontZ =
            outerBookDepth(
                for:
                    binding
            )
            / 2
            - coverThickness(
                for:
                    binding
            )
            / 2
        let openZ =
            -outerBookDepth(
                for:
                    binding
            )
            / 2
            + coverThickness(
                for:
                    binding
            )
            / 2
        let hingeZ = frontZ + (openZ - frontZ) * (clamped / 180)
        return (radius * cos(radians), hingeZ + radius * sin(radians))
    }

    // BOLD_KDP_IMPORTED_TEMPLATE_SPEC_V24B
    //
    // KDP-generated artwork commonly carries its production specification in
    // the filename. Example:
    //
    // CASE_LAMINATE_8.250x11.000_535_BW_WHITE_en_US
    //
    // That specification belongs to the physical cover artwork and must not be
    // silently replaced with the manuscript's current pagination.
    struct ImportedKDPTemplateSpecification:
        Equatable
    {
        let trimWidth:
            Double

        let trimHeight:
            Double

        let pageCount:
            Int

        let caliper:
            Double

        let binding:
            BookBinding
    }

    static func importedKDPTemplateSpecification(
        name:
            String
    ) -> ImportedKDPTemplateSpecification? {
        let upper =
            name
            .uppercased()

        guard
            let range =
                upper
                .range(
                    of:
                        "CASE_LAMINATE_"
                )
        else {
            return nil
        }

        let tail =
            String(
                upper[
                    range.upperBound...
                ]
            )

        let tokens =
            tail
            .split(
                separator:
                    "_",
                omittingEmptySubsequences:
                    true
            )
            .map(
                String.init
            )

        guard
            tokens.count >= 4
        else {
            return nil
        }

        let dimensions =
            tokens[0]
            .split(
                separator:
                    "X",
                maxSplits:
                    1,
                omittingEmptySubsequences:
                    true
            )

        guard
            dimensions.count == 2,
            let trimWidth =
                Double(
                    dimensions[0]
                ),
            let trimHeight =
                Double(
                    dimensions[1]
                ),
            trimWidth > 0,
            trimHeight > 0,
            let pageCount =
                Int(
                    tokens[1]
                ),
            pageCount > 0
        else {
            return nil
        }

        let ink =
            tokens[2]

        let paper =
            tokens[3]

        let caliper:
            Double

        if
            ink == "BW",
            paper == "WHITE"
        {
            caliper =
                0.002252
        } else if
            ink == "BW",
            paper == "CREAM"
        {
            caliper =
                0.0025
        } else if
            ink.contains(
                "PREMIUM"
            )
            || paper.contains(
                "PREMIUM"
            )
        {
            caliper =
                0.002347
        } else {
            return nil
        }

        return
            ImportedKDPTemplateSpecification(
                trimWidth:
                    trimWidth,
                trimHeight:
                    trimHeight,
                pageCount:
                    pageCount,
                caliper:
                    caliper,
                binding:
                    .hardcover
            )
    }


    static func expectedSpine(pageCount: Int, caliper: Double) -> Double? {
        guard pageCount > 0, caliper.isFinite, caliper > 0 else { return nil }
        return Double(pageCount) * caliper
    }

    static func resizedPrintCover(
        _ project: CoverProject,
        spineWidth: Double,
        pageCount: Int?,
        caliper: Double?
    ) -> CoverProject? {
        guard project.activeKDPHardcoverLayout == nil else { return nil }
        guard
            project.type == .printFullWrap,
            spineWidth.isFinite,
            spineWidth >= 0,
            let dimensions = try? CoverCalculator.fullWrap(
                backWidth:
                    project.backWidth,
                frontWidth:
                    project.trimWidth,
                trimHeight:
                    project.trimHeight,
                spineWidth:
                    spineWidth,
                bleed:
                    project.bleed
            )
        else {
            return nil
        }

        var result =
            project

        result.spineWidth =
            spineWidth

        result.canvasWidth =
            dimensions.totalWidthInches

        result.canvasHeight =
            dimensions.totalHeightInches

        result.spinePageCount =
            pageCount

        result.spineCaliperInches =
            caliper

        result.layers =
            CoverCalculator.reanchoredLayers(
                from:
                    project,
                to:
                    result
            )

        return result == project
            ? nil
            : result
    }

    static func applyingProductionTemplate(
        _ template:
            BookProductionTemplate,
        to project:
            CoverProject,
        pageCount:
            Int
    ) -> CoverProject? {
        guard
            project.type
                == .printFullWrap,
            template != .custom,
            pageCount > 0,
            let trimWidth =
                template.trimWidthInches,
            let trimHeight =
                template.trimHeightInches,
            let bleed =
                template.bleedInches,
            let paperStock =
                template.paperStockPreset,
            let binding =
                template.productionBinding,
            let caliper =
                paperStock.caliperInches,
            let spine =
                expectedSpine(
                    pageCount:
                        pageCount,
                    caliper:
                        caliper
                ),
            let dimensions =
                try? CoverCalculator
                    .fullWrap(
                        backWidth:
                            trimWidth,
                        frontWidth:
                            trimWidth,
                        trimHeight:
                            trimHeight,
                        spineWidth:
                            spine,
                        bleed:
                            bleed
                    )
        else {
            return nil
        }

        var result =
            project

        result.trimWidth =
            trimWidth

        result.backWidth =
            trimWidth

        result.trimHeight =
            trimHeight

        result.bleed =
            bleed

        result.spineWidth =
            spine

        result.spinePageCount =
            pageCount

        result.spineCaliperInches =
            caliper

        result.paperStockPreset =
            paperStock

        result.productionBinding =
            binding

        result.productionTemplate =
            template

        result.canvasWidth =
            dimensions.totalWidthInches

        result.canvasHeight =
            dimensions.totalHeightInches

        result.layers =
            CoverCalculator
                .reanchoredLayers(
                    from:
                        project,
                    to:
                        result
                )

        return result == project
            ? nil
            : result
    }

    /// Builds a separate KDP paperback project from existing editable wrap art.
    /// The source remains unchanged; panel-anchored artwork is reanchored rather
    /// than flattened or resampled. Hardcover projects require a measured KDP
    /// case template and must use that separate workflow.
    static func adaptingArtworkToKDPPaperback(
        _ original: CoverProject,
        pageCount: Int,
        trimWidth: Double,
        trimHeight: Double,
        paperStock: PrintPaperStockPreset
    ) -> CoverProject? {
        guard original.type == .printFullWrap,
              pageCount >= 24,
              paperStock == .kdpWhite || paperStock == .kdpCream,
              let caliper = paperStock.caliperInches,
              let dimensions = try? CoverCalculator.fullWrap(
                backWidth: trimWidth,
                frontWidth: trimWidth,
                trimHeight: trimHeight,
                spineWidth: Double(pageCount) * caliper,
                bleed: 0.125
              ) else { return nil }

        var result = original
        result.id = UUID()
        result.name = original.name + " — KDP Paperback \(pageCount) pages"
        result.kdpHardcoverLayout = nil
        result.productionBinding = .softcover
        result.productionTemplate = .custom
        result.paperStockPreset = paperStock
        result.trimWidth = trimWidth
        result.backWidth = trimWidth
        result.trimHeight = trimHeight
        result.bleed = 0.125
        result.spineWidth = Double(pageCount) * caliper
        result.spinePageCount = pageCount
        result.spineCaliperInches = caliper
        result.canvasWidth = dimensions.totalWidthInches
        result.canvasHeight = dimensions.totalHeightInches
        result.layers = CoverCalculator.reanchoredLayers(from: original, to: result)
        for index in result.layers.indices where result.layers[index].isReferenceLayer {
            result.layers[index].visible = false
        }
        return result
    }

    /// Adapts editable panel artwork to measurements returned by the official
    /// KDP cover calculator. Unlike paperback, the hardcover spine is the
    /// measured case spine and must never be derived from paperback caliper.
    static func adaptingArtworkToKDPHardcover(
        _ original: CoverProject,
        pageCount: Int,
        trimWidth: Double,
        trimHeight: Double,
        paperStock: PrintPaperStockPreset,
        measuredLayout: KDPHardcoverLayout
    ) -> CoverProject? {
        guard original.type == .printFullWrap,
              pageCount >= 76,
              pageCount <= 550,
              paperStock == .kdpWhite || paperStock == .kdpCream,
              measuredLayout.pageCount == pageCount,
              abs(measuredLayout.trimWidth - trimWidth) < 0.001,
              abs(measuredLayout.trimHeight - trimHeight) < 0.001,
              abs(measuredLayout.wrapX - 15 / 25.4) < 0.0015,
              abs(measuredLayout.wrapY - 15 / 25.4) < 0.0015 else { return nil }

        var result = original
        result.id = UUID()
        result.name = original.name + " — KDP Hardcover \(pageCount) pages"
        result.canvasWidth = measuredLayout.canvasWidth
        result.canvasHeight = measuredLayout.canvasHeight
        result.trimWidth = trimWidth
        result.backWidth = trimWidth
        result.trimHeight = trimHeight
        result.spineWidth = measuredLayout.spineWidth
        result.bleed = 0
        result.spinePageCount = pageCount
        result.spineCaliperInches = nil
        result.paperStockPreset = paperStock
        result.productionBinding = .hardcover
        result.productionTemplate = .custom
        result.kdpHardcoverLayout = measuredLayout
        result.layers = CoverCalculator.reanchoredLayers(from: original, to: result)
        for index in result.layers.indices where result.layers[index].isReferenceLayer {
            result.layers[index].visible = false
        }
        return result.activeKDPHardcoverLayout == nil ? nil : result
    }

    static func synchronizedPrintCover(
        _ project: CoverProject,
        manuscriptPageCount: Int
    ) -> CoverProject? {
        guard
            project.type
                == .printFullWrap,
            manuscriptPageCount > 0
        else {
            return nil
        }

        guard project.activeKDPHardcoverLayout == nil else { return nil }

        // BOLD_KDP_TEMPLATE_SYNC_V24B
        //
        // If the cover itself came from a KDP template, the template's encoded
        // page count belongs to that artwork. Do not squeeze/stretch the cover
        // merely because the current manuscript pagination changed.
        // Converted projects retain the imported template's descriptive name
        // for traceability, but their explicit paperback profile and page count
        // now govern the physical wrap geometry.
        let isConvertedKDPpaperback =
            project.productionBinding == .softcover
            && (project.paperStockPreset == .kdpWhite || project.paperStockPreset == .kdpCream)
            && project.productionTemplate == .custom
            && project.spinePageCount != nil

        if
            !isConvertedKDPpaperback,
            let specification =
                importedKDPTemplateSpecification(
                    name:
                        project.name
                ),
            let spine =
                expectedSpine(
                    pageCount:
                        specification
                            .pageCount,
                    caliper:
                        specification
                            .caliper
                )
        {
            return
                resizedPrintCover(
                    project,
                    spineWidth:
                        spine,
                    pageCount:
                        specification
                            .pageCount,
                    caliper:
                        specification
                            .caliper
                )
        }

        guard
            project.spinePageCount
                != nil,
            let caliper =
                project
                .spineCaliperInches,
            let spine =
                expectedSpine(
                    pageCount:
                        manuscriptPageCount,
                    caliper:
                        caliper
                )
        else {
            return nil
        }

        return
            resizedPrintCover(
                project,
                spineWidth:
                    spine,
                pageCount:
                    manuscriptPageCount,
                caliper:
                    caliper
            )
    }

    /// Residual board lifts and binding separation share the same opening
    /// domain. Zero is the mechanically closed shell; after 90 degrees the
    /// paper hinges meet and both sides settle toward their reading supports.
    /// The opened case needs room for its real spine width. The printed
    /// leaves still meet at X=0 above this space; the two supporting boards
    /// settle on either side instead of crushing the wrap into a hanging loop.
    func openSpineHingeOffset(angleDegrees: Double, binding: BookBinding = .softcover) -> Double {
        let angle = angleDegrees.isFinite ? min(180,max(0,angleDegrees)):180
        let t = angle/180
        return outerBookDepth(for:binding) / 2 * t*t*(3-2*t)
    }

    func openingPose(angleDegrees: Double) -> BookOpeningPose {
        let angle = angleDegrees.isFinite ? min(180, max(0, angleDegrees)) : 180
        let progress = angle / 180
        let residual = 180 - angle
        // A resting book opens its front over the supported back. Splitting
        // this rotation between both boards stood the book on its spine and
        // produced a crossed-plate silhouette from low camera angles.
        let right = 0.0
        return BookOpeningPose(leftLiftDegrees: residual - right, rightLiftDegrees: right,
            leftHingeDepth: paperBlockDepth * max(0, 1 - progress * 2))
    }

    func physicalPose(
        open: Bool,
        angleDegrees: Double,
        pageCount: Int,
        spreadIndex: Int,
        binding: BookBinding
    ) -> BookPhysicalPose {
        let safeAngle =
            angleDegrees.isFinite
            ? min(
                180,
                max(
                    0,
                    angleDegrees
                )
            )
            : 180

        let openProgress =
            open
            ? safeAngle / 180
            : 0

        let stacks =
            Self.pageStacks(
                pageCount:
                    pageCount,
                spreadIndex:
                    spreadIndex,
                totalDepth:
                    pageBlockDepth(
                        for:
                            binding
                    )
            )

        let totalDepth =
            max(
                0.000_001,
                stacks.leftDepth
                + stacks.rightDepth
            )

        let pageBalance =
            (
                stacks.leftDepth
                - stacks.rightDepth
            )
            / totalDepth

        let easedOpen =
            sin(
                openProgress
                * .pi
                / 2
            )

        // BOLD WRITER V9:
        // Material/hinge flex must return to zero when the book reaches
        // a fully-open 180° spread. The previous monotonic easedOpen value
        // reached its maximum at 180°, permanently forcing both page stacks
        // into a V even when the requested opening angle was completely flat.
        //
        // sin(progress * pi) gives the physical flex a proper rest envelope:
        // zero closed, strongest mid-opening, zero fully open.
        let hingeFlexEnvelope =
            sin(
                openProgress
                * .pi
            )

        let backCoverLiftDegrees =
            (
                binding == .hardcover
                ? 1.75
                : 3.25
            )
            * hingeFlexEnvelope

        let pageStackLiftDegrees =
            (
                binding == .hardcover
                ? 2.75
                : 4.75
            )
            * hingeFlexEnvelope

        let pageBalanceDegrees =
            pageBalance
            * (
                binding == .hardcover
                ? 1.5
                : 2.5
            )
            * hingeFlexEnvelope

        let gutterDrop =
            min(
                trimWidth
                    * (
                        binding == .hardcover
                        ? 0.035
                        : 0.055
                    ),
                binding == .hardcover
                ? 0.18
                : 0.28
            )
            * easedOpen

        let foreEdgeLift =
            trimWidth
            * sin(
                pageStackLiftDegrees
                * .pi
                / 180
            )

        return BookPhysicalPose(
            stacks:
                stacks,
            openProgress:
                openProgress,
            backCoverLiftDegrees:
                backCoverLiftDegrees,
            pageStackLiftDegrees:
                pageStackLiftDegrees,
            pageBalanceDegrees:
                pageBalanceDegrees,
            gutterDrop:
                gutterDrop,
            foreEdgeLift:
                foreEdgeLift
        )
    }

    func pageTurnMassTransfer(
        pageCount: Int,
        fromSpread: Int,
        toSpread: Int,
        progress: Double,
        binding: BookBinding
    ) -> BookPageTurnMassTransfer {
        let safeProgress =
            progress.isFinite
            ? min(
                1,
                max(
                    0,
                    progress
                )
            )
            : 0

        let totalDepth =
            pageBlockDepth(
                for:
                    binding
            )

        let sourceStacks =
            Self.pageStacks(
                pageCount:
                    pageCount,
                spreadIndex:
                    fromSpread,
                totalDepth:
                    totalDepth
            )

        let destinationStacks =
            Self.pageStacks(
                pageCount:
                    pageCount,
                spreadIndex:
                    toSpread,
                totalDepth:
                    totalDepth
            )

        let releaseProgress =
            min(
                1,
                safeProgress
                * 2
            )

        let landingProgress =
            max(
                0,
                min(
                    1,
                    (
                        safeProgress
                        - 0.5
                    )
                    * 2
                )
            )

        func transientDepth(
            source:
                Double,
            destination:
                Double
        ) -> Double {
            let delta =
                destination
                - source

            if delta < 0 {
                return source
                    + delta
                    * releaseProgress
            }

            if delta > 0 {
                return source
                    + delta
                    * landingProgress
            }

            return source
        }

        let leftDepth =
            max(
                0,
                transientDepth(
                    source:
                        sourceStacks.leftDepth,
                    destination:
                        destinationStacks.leftDepth
                )
            )

        let rightDepth =
            max(
                0,
                transientDepth(
                    source:
                        sourceStacks.rightDepth,
                    destination:
                        destinationStacks.rightDepth
                )
            )

        let leftDelta =
            destinationStacks.leftDepth
            - sourceStacks.leftDepth

        let rightDelta =
            destinationStacks.rightDepth
            - sourceStacks.rightDepth

        let transferDepth =
            max(
                abs(
                    leftDelta
                ),
                abs(
                    rightDelta
                )
            )

        let movingSheetDepth =
            max(
                0,
                totalDepth
                - leftDepth
                - rightDepth
            )

        let forward =
            toSpread
            >= fromSpread

        return BookPageTurnMassTransfer(
            leftDepth:
                leftDepth,
            rightDepth:
                rightDepth,
            movingSheetDepth:
                movingSheetDepth,
            transferDepth:
                transferDepth,
            totalDepth:
                totalDepth,
            progress:
                safeProgress,
            sourceSide:
                forward
                ? .right
                : .left,
            destinationSide:
                forward
                ? .left
                : .right
        )
    }

    func openSilhouette(
        open: Bool,
        angleDegrees: Double,
        pageCount: Int,
        spreadIndex: Int,
        binding: BookBinding
    ) -> BookOpenSilhouette {
        let pose =
            physicalPose(
                open:
                    open,
                angleDegrees:
                    angleDegrees,
                pageCount:
                    pageCount,
                spreadIndex:
                    spreadIndex,
                binding:
                    binding
            )

        let totalDepth =
            max(
                0.000_001,
                pose.stacks.leftDepth
                + pose.stacks.rightDepth
            )

        let leftFraction =
            pose.stacks.leftDepth
            / totalDepth

        let rightFraction =
            pose.stacks.rightDepth
            / totalDepth

        let asymmetry =
            leftFraction
            - rightFraction

        let thinFlexMaximum =
            binding == .hardcover
            ? 1.0
            : 2.0

        let heavyCompressionMaximum =
            binding == .hardcover
            ? 0.35
            : 0.60

        func stackLift(
            fraction:
                Double
        ) -> Double {
            let thinness =
                max(
                    0,
                    (
                        0.5
                        - fraction
                    )
                    * 2
                )

            let heaviness =
                max(
                    0,
                    (
                        fraction
                        - 0.5
                    )
                    * 2
                )

            return max(
                0,
                pose.pageStackLiftDegrees
                + thinFlexMaximum
                * thinness
                * pose.openProgress
                - heavyCompressionMaximum
                * heaviness
                * pose.openProgress
            )
        }

        func thinness(
            fraction:
                Double
        ) -> Double {
            max(
                0,
                (
                    0.5
                    - fraction
                )
                * 2
            )
        }

        let leftStackLiftDegrees =
            stackLift(
                fraction:
                    leftFraction
            )

        let rightStackLiftDegrees =
            stackLift(
                fraction:
                    rightFraction
            )

        let shoulderBase =
            trimWidth
            * (
                binding == .hardcover
                ? 0.0016
                : 0.0030
            )
            * pose.openProgress

        let leftShoulderDepth =
            shoulderBase
            * (
                1
                + 0.30
                * thinness(
                    fraction:
                        leftFraction
                )
            )

        let rightShoulderDepth =
            shoulderBase
            * (
                1
                + 0.30
                * thinness(
                    fraction:
                        rightFraction
                )
            )

        let pageValleyDepth =
            pose.gutterDrop
            * (
                binding == .hardcover
                ? 0.10
                : 0.09
            )

        func residualForeEdgeLift(
            degrees:
                Double
        ) -> Double {
            trimWidth
            * sin(
                degrees
                * .pi
                / 180
            )
            * 0.055
            * pose.openProgress
        }

        let leftForeEdgeLift =
            residualForeEdgeLift(
                degrees:
                    leftStackLiftDegrees
            )

        let rightForeEdgeLift =
            residualForeEdgeLift(
                degrees:
                    rightStackLiftDegrees
            )

        return BookOpenSilhouette(
            stacks:
                pose.stacks,
            openProgress:
                pose.openProgress,
            leftStackLiftDegrees:
                leftStackLiftDegrees,
            rightStackLiftDegrees:
                rightStackLiftDegrees,
            leftShoulderDepth:
                leftShoulderDepth,
            rightShoulderDepth:
                rightShoulderDepth,
            gutterDrop:
                pose.gutterDrop,
            pageValleyDepth:
                pageValleyDepth,
            leftForeEdgeLift:
                leftForeEdgeLift,
            rightForeEdgeLift:
                rightForeEdgeLift,
            asymmetry:
                asymmetry
        )
    }

    func stackSupportPose(
        open: Bool,
        angleDegrees: Double,
        pageCount: Int,
        spreadIndex: Int,
        binding: BookBinding
    ) -> BookStackSupportPose {
        let silhouette =
            openSilhouette(
                open:
                    open,
                angleDegrees:
                    angleDegrees,
                pageCount:
                    pageCount,
                spreadIndex:
                    spreadIndex,
                binding:
                    binding
            )

        let follow =
            binding == .hardcover
            ? 0.970
            : 0.990

        return BookStackSupportPose(
            leftCoverLiftDegrees:
                max(
                    0,
                    silhouette.leftStackLiftDegrees
                    * follow
                ),
            rightCoverLiftDegrees:
                max(
                    0,
                    silhouette.rightStackLiftDegrees
                    * follow
                )
        )
    }

    static func pageStacks(pageCount: Int, spreadIndex: Int, totalDepth: Double) -> BookPageStacks {
        let count = max(0, pageCount)
        // Clamp before multiplying so huge automation inputs cannot
        // overflow Int while producing the same valid page masses.
        let positiveSpread = max(0, spreadIndex)
        let turned = positiveSpread > count / 2
            ? count
            : positiveSpread * 2
        let leftFraction = count == 0 ? 0 : Double(turned) / Double(count)
        // Reject invalid print thickness before it enters paper geometry.
        // Keep the original proportional left/right depth formula.
        let safeDepth = totalDepth.isFinite
            ? max(0, totalDepth)
            : 0

        return BookPageStacks(turnedPages: turned, remainingPages: count - turned,
                              leftDepth: safeDepth * leftFraction,
                              rightDepth: safeDepth * (1 - leftFraction))
    }

    static func naturalReadingSpread(
        pageCount:
            Int
    ) -> Int {
        let maximumSpread =
            max(
                0,
                pageCount / 2
            )

        guard
            maximumSpread > 1
        else {
            return 0
        }

        let suggested =
            Int(
                (
                    Double(
                        maximumSpread
                    )
                    * 0.43
                )
                .rounded()
            )

        return min(
            maximumSpread - 1,
            max(
                1,
                suggested
            )
        )
    }

    static func pageTurnDirection(fromSpread: Int, toSpread: Int) -> BookPageTurnDirection? {
        guard fromSpread != toSpread else { return nil }
        return toSpread > fromSpread ? .forward : .backward
    }

    static func pageTurnRotation(direction: BookPageTurnDirection) -> Double {
        // Positive Y rotation sends a right-hand leaf down into the block.
        direction == .forward ? -.pi : .pi
    }

    static func pageTurnFaces(direction: BookPageTurnDirection, fromSpread: Int, toSpread: Int, pageCount: Int) -> BookPageTurnFaces {
        let from = spread(at: fromSpread, pageCount: pageCount)
        let to = spread(at: toSpread, pageCount: pageCount)
        if direction == .forward { return BookPageTurnFaces(front: from.rightPage, reverse: to.leftPage) }
        return BookPageTurnFaces(front: from.leftPage, reverse: to.rightPage)
    }

    static func spread(forPage page: Int, pageCount: Int) -> BookSpread {
        guard pageCount > 0 else { return BookSpread(index: 0, leftPage: nil, rightPage: nil) }
        let clamped = min(max(1, page), pageCount)
        // Page one is the first recto. Spread zero is the inside cover / page one.
        if clamped == 1 { return BookSpread(index: 0, leftPage: nil, rightPage: 1) }
        if clamped.isMultiple(of: 2) {
            return BookSpread(index: clamped / 2, leftPage: clamped, rightPage: clamped + 1 <= pageCount ? clamped + 1 : nil)
        }
        return BookSpread(index: clamped / 2, leftPage: clamped - 1, rightPage: clamped)
    }

    static func spread(at index: Int, pageCount: Int) -> BookSpread {
        guard pageCount > 0 else { return BookSpread(index: 0, leftPage: nil, rightPage: nil) }
        let lastIndex = pageCount / 2
        let safe = min(max(0, index), lastIndex)
        if safe == 0 { return BookSpread(index: 0, leftPage: nil, rightPage: 1) }
        let left = safe * 2
        return BookSpread(index: safe, leftPage: left <= pageCount ? left : nil, rightPage: left + 1 <= pageCount ? left + 1 : nil)
    }

    static func thumbZone(pageWidth: Double, pageHeight: Double = 1, depth: Double, side: ThumbSide, mode: ThumbZoneMode) -> CoverRect {
        let reach = min(max(0, depth), max(0, pageWidth))
        return CoverRect(x: side == .left ? 0 : pageWidth - reach, y: 0, width: reach, height: max(0, pageHeight))
    }

    static func insideEdge(side: ThumbSide) -> ThumbSide { side == .left ? .right : .left }
    static func outsideEdge(side: ThumbSide) -> ThumbSide { side == .left ? .left : .right }
    static func mirroredMargins(pageNumber: Int, left: Double, right: Double) -> (left: Double, right: Double) {
        pageNumber.isMultiple(of: 2) ? (right, left) : (left, right)
    }

    /// One trim-sized page on either side of the common gutter.
    static func scenePageOriginX(pageWidth: Double, side: ThumbSide) -> Double {
        side == .left ? -pageWidth / 2 : pageWidth / 2
    }

    static func intersects(_ content: CoverRect, zone: CoverRect) -> Double {
        let x = max(0, min(content.x + content.width, zone.x + zone.width) - max(content.x, zone.x))
        let y = max(0, min(content.y + content.height, zone.y + zone.height) - max(content.y, zone.y))
        return x > 0 && y > 0 ? x : 0
    }

    static func marginIntrusions(content: CoverRect, pageWidth: Double, pageHeight: Double, left: Double, right: Double, top: Double, bottom: Double) -> PageMarginIntrusions {
        PageMarginIntrusions(left: max(0, left - content.x), right: max(0, content.x + content.width - (pageWidth - right)),
                             top: max(0, content.y + content.height - (pageHeight - top)), bottom: max(0, bottom - content.y))
    }
}

struct BookBox: Equatable { let width: Double; let depth: Double; let height: Double }
struct BookPageStacks: Equatable { let turnedPages: Int; let remainingPages: Int; let leftDepth: Double; let rightDepth: Double }

struct BookPhysicalPose: Equatable {
    let stacks: BookPageStacks
    let openProgress: Double
    let backCoverLiftDegrees: Double
    let pageStackLiftDegrees: Double
    let pageBalanceDegrees: Double
    let gutterDrop: Double
    let foreEdgeLift: Double

    var leftPageLiftDegrees: Double {
        pageStackLiftDegrees
        + max(
            0,
            -pageBalanceDegrees
        )
    }

    var rightPageLiftDegrees: Double {
        pageStackLiftDegrees
        + max(
            0,
            pageBalanceDegrees
        )
    }
}

struct BookOpenSilhouette: Equatable {
    let stacks: BookPageStacks
    let openProgress: Double
    let leftStackLiftDegrees: Double
    let rightStackLiftDegrees: Double
    let leftShoulderDepth: Double
    let rightShoulderDepth: Double
    let gutterDrop: Double
    let pageValleyDepth: Double
    let leftForeEdgeLift: Double
    let rightForeEdgeLift: Double
    let asymmetry: Double

    var leftOuterRiseFromGutter: Double {
        pageValleyDepth
        + leftForeEdgeLift
    }

    var rightOuterRiseFromGutter: Double {
        pageValleyDepth
        + rightForeEdgeLift
    }
}


struct BookStackSupportPose: Equatable {
    let leftCoverLiftDegrees: Double
    let rightCoverLiftDegrees: Double
}


struct BookPageTurnMassTransfer: Equatable {
    let leftDepth: Double
    let rightDepth: Double
    let movingSheetDepth: Double
    let transferDepth: Double
    let totalDepth: Double
    let progress: Double
    let sourceSide: ThumbSide
    let destinationSide: ThumbSide

    var conservedDepth: Double {
        leftDepth
        + rightDepth
        + movingSheetDepth
    }
}


enum BookPageTurnDirection: Equatable { case forward, backward }
enum BookBinding: String, Codable, CaseIterable, Identifiable {
    case softcover = "Softcover", hardcover = "Hardcover"
    var id: String { rawValue }
}
struct BookTextureVerticalTransform: Equatable {
    let scale: Double
    let offset: Double
    func apply(_ coordinate: Double) -> Double { scale * coordinate + offset }
    static let frontCover = BookTextureVerticalTransform(scale: 1, offset: 0)
    static let backCover = BookTextureVerticalTransform(scale: 1, offset: 0)
    static let spine = BookTextureVerticalTransform(scale: 1, offset: 0)
}
struct BookPageTurnTransition: Equatable {
    let fromSpread: Int
    let toSpread: Int
    let direction: BookPageTurnDirection
    let rotation: Double
}

struct BookPageTurnState: Equatable {
    private(set) var spreadIndex = 0
    private(set) var activeTransition: BookPageTurnTransition?

    mutating func begin(to requestedSpread: Int, maximumSpread: Int) -> BookPageTurnTransition? {
        guard activeTransition == nil else { return nil }
        let target = min(max(0, requestedSpread), max(0, maximumSpread))
        guard let direction = PhysicalBookGeometry.pageTurnDirection(fromSpread: spreadIndex, toSpread: target) else { return nil }
        let transition = BookPageTurnTransition(fromSpread: spreadIndex, toSpread: target, direction: direction,
                                                rotation: PhysicalBookGeometry.pageTurnRotation(direction: direction))
        activeTransition = transition
        spreadIndex = target
        return transition
    }

    mutating func finish() { activeTransition = nil }
    mutating func jump(to requestedSpread: Int, maximumSpread: Int) {
        guard activeTransition == nil else { return }
        spreadIndex = min(max(0, requestedSpread), max(0, maximumSpread))
    }
    mutating func reset() { spreadIndex = 0; activeTransition = nil }
}
struct BookCoverPanelMapping: Equatable { let back: CoverRect; let spine: CoverRect; let front: CoverRect }
struct BookSpread: Equatable { let index: Int; let leftPage: Int?; let rightPage: Int? }
struct BookPageTurnFaces: Equatable { let front: Int?; let reverse: Int? }
struct PageMarginIntrusions: Equatable { let left: Double; let right: Double; let top: Double; let bottom: Double; var isEmpty: Bool { left == 0 && right == 0 && top == 0 && bottom == 0 } }
enum ThumbSide: Equatable { case left, right }
enum ThumbZoneMode: String, CaseIterable, Identifiable { case off = "Off", standard = "Standard", conservative = "Conservative"; var id: String { rawValue } }

struct BookOpeningPose: Equatable {
    let leftLiftDegrees: Double
    let rightLiftDegrees: Double
    let leftHingeDepth: Double
}
