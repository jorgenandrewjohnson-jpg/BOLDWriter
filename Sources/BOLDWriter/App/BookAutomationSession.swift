#if !APP_STORE
import AppKit
import CryptoKit
import PDFKit
import SceneKit
import UniformTypeIdentifiers

/// File-based adapter for the existing command bus. It never targets the active
/// window and never overwrites the input document. Terminal and AI use the same
/// action schema, production cover renderer and manuscript PDF pagination.
@MainActor
final class BookAutomationSession {
    struct Request: Codable {
        var input: String
        var output: String?
        var projectID: UUID?
        var commands: [[String]]?
        var actions: [BOLDProjectAction]?
        var coverTemplate: String?
        var coverArtwork: String?
        var coverBinding: BookBinding?
        var caliperInches: Double?
    }
    struct Response: Codable {
        var input: String
        var output: String?
        var supported: [String]
        var results: [BOLDCommandResult]
        var images: [String]
    }

    static let supported: Set<BOLDProjectActionKind> = [
        .documentFind, .coverOpen, .coverInspect, .coverUpdateLayer, .coverEdit, .applicationUndo, .applicationRedo, .coverAddText, .coverPlaceImage,
        .coverSetBackground, .coverExport, .coverConvertPaperback, .studioOpen, .studioSetBinding,
        .studioApplyPreset, .studioSetCamera, .studioSetLighting, .studioRenderStill,
        .publishingPreflight, .publishingExportPDF, .manuscriptSetTrimSize,
        .manuscriptSetMetadata
    ]
    let document: BOLDWriterDocument
    let input: URL
    var selectedProjectID: UUID?
    private(set) var images: [String] = []
    private var coverUndo: [CoverProject] = []
    private var coverRedo: [CoverProject] = []
    private var cachedPagination: (PDFDocument, Data, [PageSettings])?

    init(input: URL, projectID: UUID? = nil) throws {
        self.input = input.resolvingSymlinksInPath().standardizedFileURL
        let type: UTType
        switch input.pathExtension.lowercased() {
        case "boldwriter": type = .boldWriterDocument
        case "docx": type = .docx
        case "pdf": type = .pdf
        default: throw WriterError.message("Automation input must be a .boldwriter, .docx or .pdf document.")
        }
        document = try BOLDWriterDocument(fileWrapper: FileWrapper(url: self.input), contentType: type)
        selectedProjectID = projectID ?? document.metadata.activeCoverProjectID
    }

    static func run(requestURL: URL) throws {
        let request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        let session = try BookAutomationSession(input: absoluteURL(request.input), projectID: request.projectID)
        if let template = request.coverTemplate {
            try session.importMeasuredCover(template: absoluteURL(template), artwork: request.coverArtwork.map(absoluteURL))
        } else if let artwork = request.coverArtwork {
            try session.createPrintCover(artwork: absoluteURL(artwork), binding: request.coverBinding ?? .softcover,
                caliper: request.caliperInches ?? PrintCoverSpecification.kdpBlackAndWhiteWhitePaperCaliper)
        }
        let actions = try (request.commands ?? []).map { try BOLDTerminalCommandParser.parse($0) }
            + (request.actions ?? [])
        guard actions.count <= 100 else { throw WriterError.message("Limit automation batches to 100 actions.") }
        for action in actions where !supported.contains(action.kind) {
            throw BOLDCommandError.unsupportedAction(action.kind)
        }
        var registry = BOLDCommandHandlerRegistry()
        for kind in supported {
            try registry.register(kind) { action in try session.execute(action) }
        }
        let runtime = try BOLDCommandRuntime(registry: registry)
        let results = try runtime.execute(actions)
        if let output = request.output {
            let url = try session.newOutput(output)
            guard url.pathExtension == "boldwriter" else {
                throw WriterError.message("Document output must end in .boldwriter.")
            }
            let wrapper = try BOLDWriterDocument.packageWrapper(text: session.document.text, metadata: session.document.metadata)
            try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        }
        let response = Response(input: session.input.path, output: request.output,
                                supported: supported.map(\.rawValue).sorted(), results: results, images: session.images)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(response), as: UTF8.self))
        for path in session.images { print("BOLD_AUTOPILOT_IMAGE=\(path)") }
    }

    static func absoluteURL(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), !path.contains("\n"), !path.contains("\r") else {
            throw WriterError.message("Use an absolute path without line breaks: \(path)")
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private func newOutput(_ path: String) throws -> URL {
        let url = try Self.absoluteURL(path).resolvingSymlinksInPath()
        guard url != input, !url.path.hasPrefix(input.path + "/"),
              !FileManager.default.fileExists(atPath: url.path) else {
            throw WriterError.message("Output must be a new path outside the input document: \(path)")
        }
        return url
    }

    private func projectIndex() throws -> Int {
        let projects = document.metadata.coverProjects ?? []
        if let selectedProjectID {
            guard let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
                throw WriterError.message("Requested cover project was not found.")
            }
            return index
        }
        guard let index = projects.firstIndex(where: { $0.type == .printFullWrap }) else {
            throw WriterError.message("Create a print full wrap in Cover Creator before rendering this book.")
        }
        return index
    }

    private func mutateProject(_ body: (inout CoverProject) throws -> Void) throws {
        let index = try projectIndex()
        var projects = document.metadata.coverProjects ?? []
        let previous = projects[index]
        try body(&projects[index])
        try CoverProject.validate(projects)
        if previous != projects[index] {
            coverUndo.append(previous); if coverUndo.count > 50 { coverUndo.removeFirst() }; coverRedo = []
            document.metadata.coverProjects = projects
        }
    }

    func pagination() throws -> (PDFDocument, Data, [PageSettings]) {
        if let cachedPagination { return cachedPagination }
        var settings: [PageSettings] = []
        let bytes = try PDFExporter.data(from: document.text, settings: document.metadata.page,
            sections: document.metadata.sections, pageLayoutSink: { settings = $0 },
            floatingImages: document.metadata.floatingImages ?? [])
        guard let pdf = PDFDocument(data: bytes), pdf.pageCount > 0 else {
            throw WriterError.message("Manuscript pagination produced no pages.")
        }
        let result = (pdf, bytes, settings)
        cachedPagination = result
        return result
    }

    private struct BOLDSourceWrapSpecV3 {
        let trimWidth: Double
        let trimHeight: Double
        let pageCount: Int
    }

    private struct BOLDSourceWrapRegionsV3 {
        let activeHeight: CGFloat
        let activeMinY: CGFloat
        let back: CGRect
        let spine: CGRect
        let front: CGRect
    }

    private static func boldSourceWrapSpecV3(
        filename: String
    ) -> BOLDSourceWrapSpecV3? {
        let pattern =
            #"([0-9]+(?:\.[0-9]+)?)x([0-9]+(?:\.[0-9]+)?)_([0-9]+)"#

        guard let expression =
                try? NSRegularExpression(
                    pattern:
                        pattern
                )
        else {
            return nil
        }

        let ns =
            filename
            as NSString

        let range =
            NSRange(
                location:
                    0,
                length:
                    ns.length
            )

        guard let match =
                expression.firstMatch(
                    in:
                        filename,
                    range:
                        range
                ),
              match.numberOfRanges == 4,
              let trimWidth =
                Double(
                    ns.substring(
                        with:
                            match.range(
                                at:
                                    1
                            )
                    )
                ),
              let trimHeight =
                Double(
                    ns.substring(
                        with:
                            match.range(
                                at:
                                    2
                            )
                    )
                ),
              let pageCount =
                Int(
                    ns.substring(
                        with:
                            match.range(
                                at:
                                    3
                            )
                    )
                ),
              trimWidth.isFinite,
              trimHeight.isFinite,
              trimWidth > 0,
              trimHeight > 0,
              pageCount > 0
        else {
            return nil
        }

        return BOLDSourceWrapSpecV3(
            trimWidth:
                trimWidth,
            trimHeight:
                trimHeight,
            pageCount:
                pageCount
        )
    }

    private static func boldActiveArtworkBoundsV3(
        image: NSImage,
        cgImage: CGImage
    ) -> CGRect {
        guard let bitmap =
                NSBitmapImageRep(
                    data:
                        image.tiffRepresentation
                    ?? Data()
                )
        else {
            return CGRect(
                x:
                    0,
                y:
                    0,
                width:
                    cgImage.width,
                height:
                    cgImage.height
            )
        }

        let width =
            bitmap.pixelsWide

        let height =
            bitmap.pixelsHigh

        guard width > 0,
              height > 0
        else {
            return CGRect(
                x:
                    0,
                y:
                    0,
                width:
                    cgImage.width,
                height:
                    cgImage.height
            )
        }

        let xStep =
            max(
                1,
                width / 220
            )

        func rowHasArtwork(
            y: Int
        ) -> Bool {
            var sampled =
                0

            var darkEnough =
                0

            var x =
                0

            while x < width {
                defer {
                    x +=
                        xStep
                }

                guard let color =
                        bitmap.colorAt(
                            x:
                                x,
                            y:
                                y
                        )?
                        .usingColorSpace(
                            .deviceRGB
                        )
                else {
                    continue
                }

                sampled +=
                    1

                let maximum =
                    max(
                        color.redComponent,
                        color.greenComponent,
                        color.blueComponent
                    )

                let minimum =
                    min(
                        color.redComponent,
                        color.greenComponent,
                        color.blueComponent
                    )

                if maximum < 0.94
                    || maximum - minimum > 0.10
                {
                    darkEnough +=
                        1
                }
            }

            guard sampled > 0 else {
                return false
            }

            return Double(
                darkEnough
            )
            / Double(
                sampled
            )
            >= 0.12
        }

        var first =
            0

        var last =
            height - 1

        var found =
            false

        for y in 0 ..< height {
            if rowHasArtwork(
                y:
                    y
            ) {
                first =
                    y

                found =
                    true

                break
            }
        }

        if found {
            for y in stride(
                from:
                    height - 1,
                through:
                    first,
                by:
                    -1
            ) {
                if rowHasArtwork(
                    y:
                        y
                ) {
                    last =
                        y

                    break
                }
            }
        }

        let detectedHeight =
            max(
                1,
                last - first + 1
            )

        let fraction =
            Double(
                detectedHeight
            )
            / Double(
                height
            )

        if found == false
            || fraction < 0.55
            || fraction > 0.99
        {
            return CGRect(
                x:
                    0,
                y:
                    0,
                width:
                    width,
                height:
                    height
            )
        }

        return CGRect(
            x:
                0,
            y:
                first,
            width:
                width,
            height:
                detectedHeight
        )
    }

    private static func boldSourceRegionsV3(
        image: NSImage,
        cgImage: CGImage,
        spec: BOLDSourceWrapSpecV3,
        caliper: Double
    ) -> BOLDSourceWrapRegionsV3? {
        guard spec.trimWidth > 0,
              spec.trimHeight > 0,
              spec.pageCount > 0,
              caliper.isFinite,
              caliper > 0
        else {
            return nil
        }

        let active =
            boldActiveArtworkBoundsV3(
                image:
                    image,
                cgImage:
                    cgImage
            )

        let activeHeight =
            active.height

        let pixelsPerInch =
            activeHeight
            / CGFloat(
                spec.trimHeight
            )

        let panelWidth =
            pixelsPerInch
            * CGFloat(
                spec.trimWidth
            )

        let sourceSpineInches =
            Double(
                spec.pageCount
            )
            * caliper

        let sourceSpineWidth =
            max(
                1,
                pixelsPerInch
                * CGFloat(
                    sourceSpineInches
                )
            )

        let imageWidth =
            CGFloat(
                cgImage.width
            )

        let imageHeight =
            CGFloat(
                cgImage.height
            )

        let centerX =
            imageWidth / 2

        let spineMinX =
            centerX
            - sourceSpineWidth / 2

        let spineMaxX =
            centerX
            + sourceSpineWidth / 2

        let backMinX =
            spineMinX
            - panelWidth

        let frontMinX =
            spineMaxX

        let cgY =
            imageHeight
            - active.maxY

        let back =
            CGRect(
                x:
                    backMinX,
                y:
                    cgY,
                width:
                    panelWidth,
                height:
                    activeHeight
            )
            .integral

        let spine =
            CGRect(
                x:
                    spineMinX,
                y:
                    cgY,
                width:
                    sourceSpineWidth,
                height:
                    activeHeight
            )
            .integral

        let front =
            CGRect(
                x:
                    frontMinX,
                y:
                    cgY,
                width:
                    panelWidth,
                height:
                    activeHeight
            )
            .integral

        let bounds =
            CGRect(
                x:
                    0,
                y:
                    0,
                width:
                    imageWidth,
                height:
                    imageHeight
            )

        guard bounds.contains(
                  back
              ),
              bounds.contains(
                  spine
              ),
              bounds.contains(
                  front
              )
        else {
            return nil
        }

        return BOLDSourceWrapRegionsV3(
            activeHeight:
                activeHeight,
            activeMinY:
                active.minY,
            back:
                back,
            spine:
                spine,
            front:
                front
        )
    }

    private static func boldCropPNGV3(
        cgImage: CGImage,
        rect: CGRect
    ) throws -> Data {
        let bounds =
            CGRect(
                x:
                    0,
                y:
                    0,
                width:
                    cgImage.width,
                height:
                    cgImage.height
            )

        let safe =
            rect
                .integral
                .intersection(
                    bounds
                )

        guard safe.width >= 1,
              safe.height >= 1,
              let cropped =
                cgImage.cropping(
                    to:
                        safe
                )
        else {
            throw WriterError.message(
                "Could not crop a full-wrap source panel."
            )
        }

        let bitmap =
            NSBitmapImageRep(
                cgImage:
                    cropped
            )

        guard let data =
                bitmap.representation(
                    using:
                        .png,
                    properties:
                        [:]
                )
        else {
            throw WriterError.message(
                "Could not encode a cropped cover panel."
            )
        }

        return data
    }

    private static func boldResizeSpineV3(
        data: Data,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> Data {
        guard targetWidth > 0,
              targetHeight > 0,
              let input =
                NSImage(
                    data:
                        data
                )
        else {
            throw WriterError.message(
                "Could not decode the source spine."
            )
        }

        let size =
            NSSize(
                width:
                    targetWidth,
                height:
                    targetHeight
            )

        let output =
            NSImage(
                size:
                    size
            )

        output.lockFocus()

        NSGraphicsContext.current?
            .imageInterpolation =
            .high

        input.draw(
            in:
                NSRect(
                    origin:
                        .zero,
                    size:
                        size
                ),
            from:
                NSRect(
                    origin:
                        .zero,
                    size:
                        input.size
                ),
            operation:
                .copy,
            fraction:
                1
        )

        output.unlockFocus()

        guard let tiff =
                output.tiffRepresentation,
              let bitmap =
                NSBitmapImageRep(
                    data:
                        tiff
                ),
              let png =
                bitmap.representation(
                    using:
                        .png,
                    properties:
                        [:]
                )
        else {
            throw WriterError.message(
                "Could not encode the resized spine."
            )
        }

        return png
    }

    private static func boldAssembleCanonicalWrapV5(
        sourceData: Data,
        sourceRegions: BOLDSourceWrapRegionsV3,
        project: CoverProject,
        totalWidthInches: Double,
        totalHeightInches: Double
    ) throws -> Data {
        guard totalWidthInches.isFinite,
              totalHeightInches.isFinite,
              totalWidthInches > 0,
              totalHeightInches > 0,
              let sourceImage =
                NSImage(
                    data:
                        sourceData
                ),
              let sourceCG =
                sourceImage.cgImage(
                    forProposedRect:
                        nil,
                    context:
                        nil,
                    hints:
                        nil
                )
        else {
            throw WriterError.message(
                "Could not prepare canonical cover artwork."
            )
        }

        let backData =
            try boldCropPNGV3(
                cgImage:
                    sourceCG,
                rect:
                    sourceRegions.back
            )

        let spineData =
            try boldCropPNGV3(
                cgImage:
                    sourceCG,
                rect:
                    sourceRegions.spine
            )

        let frontData =
            try boldCropPNGV3(
                cgImage:
                    sourceCG,
                rect:
                    sourceRegions.front
            )

        guard let backImage =
                NSImage(
                    data:
                        backData
                ),
              let spineImage =
                NSImage(
                    data:
                        spineData
                ),
              let frontImage =
                NSImage(
                    data:
                        frontData
                )
        else {
            throw WriterError.message(
                "Could not decode canonical cover panels."
            )
        }

        let outputHeight =
            CGFloat(
                2400
            )

        let outputWidth =
            max(
                CGFloat(
                    2
                ),
                (
                    outputHeight
                    * CGFloat(
                        totalWidthInches
                        / totalHeightInches
                    )
                )
                .rounded()
            )

        let outputSize =
            NSSize(
                width:
                    outputWidth,
                height:
                    outputHeight
            )

        let canvas =
            NSImage(
                size:
                    outputSize
            )

        canvas.lockFocus()

        guard let graphics =
                NSGraphicsContext.current
        else {
            canvas.unlockFocus()

            throw WriterError.message(
                "Could not create canonical cover drawing context."
            )
        }

        graphics.imageInterpolation =
            .high

        let wholeCanvas =
            NSRect(
                origin:
                    .zero,
                size:
                    outputSize
            )

        let sourceSize =
            sourceImage.size

        if sourceSize.width > 0,
           sourceSize.height > 0
        {
            let sourceAspect =
                sourceSize.width
                / sourceSize.height

            let destinationAspect =
                outputSize.width
                / outputSize.height

            var sourceRect =
                NSRect(
                    origin:
                        .zero,
                    size:
                        sourceSize
                )

            if sourceAspect > destinationAspect {
                let wantedWidth =
                    sourceSize.height
                    * destinationAspect

                sourceRect.origin.x =
                    (
                        sourceSize.width
                        - wantedWidth
                    )
                    / 2

                sourceRect.size.width =
                    wantedWidth
            } else if sourceAspect < destinationAspect {
                let wantedHeight =
                    sourceSize.width
                    / destinationAspect

                sourceRect.origin.y =
                    (
                        sourceSize.height
                        - wantedHeight
                    )
                    / 2

                sourceRect.size.height =
                    wantedHeight
            }

            sourceImage.draw(
                in:
                    wholeCanvas,
                from:
                    sourceRect,
                operation:
                    .copy,
                fraction:
                    1
            )
        }

        let geometry =
            CoverWrapGeometry(
                project:
                    project
            )

        func destination(
            _ frame: CoverRect
        ) -> NSRect {
            NSRect(
                x:
                    CGFloat(
                        frame.x
                    )
                    * outputSize.width,
                y:
                    CGFloat(
                        frame.y
                    )
                    * outputSize.height,
                width:
                    CGFloat(
                        frame.width
                    )
                    * outputSize.width,
                height:
                    CGFloat(
                        frame.height
                    )
                    * outputSize.height
            )
        }

        func aspectFillSourceRect(
            image: NSImage,
            destination: NSRect
        ) -> NSRect {
            guard image.size.width > 0,
                  image.size.height > 0,
                  destination.width > 0,
                  destination.height > 0
            else {
                return NSRect(
                    origin:
                        .zero,
                    size:
                        image.size
                )
            }

            let sourceAspect =
                image.size.width
                / image.size.height

            let destinationAspect =
                destination.width
                / destination.height

            var sourceRect =
                NSRect(
                    origin:
                        .zero,
                    size:
                        image.size
                )

            if sourceAspect > destinationAspect {
                let wantedWidth =
                    image.size.height
                    * destinationAspect

                sourceRect.origin.x =
                    (
                        image.size.width
                        - wantedWidth
                    )
                    / 2

                sourceRect.size.width =
                    wantedWidth
            } else if sourceAspect < destinationAspect {
                let wantedHeight =
                    image.size.width
                    / destinationAspect

                sourceRect.origin.y =
                    (
                        image.size.height
                        - wantedHeight
                    )
                    / 2

                sourceRect.size.height =
                    wantedHeight
            }

            return sourceRect
        }

        let backDestination =
            destination(
                geometry.backTrim
            )

        let spineDestination =
            destination(
                geometry.spineTrim
            )

        let frontDestination =
            destination(
                geometry.frontTrim
            )

        backImage.draw(
            in:
                backDestination,
            from:
                aspectFillSourceRect(
                    image:
                        backImage,
                    destination:
                        backDestination
                ),
            operation:
                .copy,
            fraction:
                1
        )

        spineImage.draw(
            in:
                spineDestination,
            from:
                NSRect(
                    origin:
                        .zero,
                    size:
                        spineImage.size
                ),
            operation:
                .copy,
            fraction:
                1
        )

        frontImage.draw(
            in:
                frontDestination,
            from:
                aspectFillSourceRect(
                    image:
                        frontImage,
                    destination:
                        frontDestination
                ),
            operation:
                .copy,
            fraction:
                1
        )

        canvas.unlockFocus()

        guard let tiff =
                canvas.tiffRepresentation,
              let bitmap =
                NSBitmapImageRep(
                    data:
                        tiff
                ),
              let png =
                bitmap.representation(
                    using:
                        .png,
                    properties:
                        [:]
                )
        else {
            throw WriterError.message(
                "Could not encode canonical full-wrap artwork."
            )
        }

        return png
    }


    private static func boldDeclaredCoverTrimV7(
        filename: String
    ) -> CGSize? {
        let pattern =
            #"(?i)(?:^|[_\\- ])([0-9]+(?:\\.[0-9]+)?)x([0-9]+(?:\\.[0-9]+)?)(?:[_\\- ]|$)"#

        guard
            let expression =
                try? NSRegularExpression(
                    pattern:
                        pattern
                )
        else {
            return nil
        }

        let source =
            filename
            as NSString

        let matches =
            expression.matches(
                in:
                    filename,
                range:
                    NSRange(
                        location:
                            0,
                        length:
                            source.length
                    )
            )

        for match in
            matches.reversed()
        {
            guard
                match.numberOfRanges >= 3
            else {
                continue
            }

            let widthText =
                source.substring(
                    with:
                        match.range(
                            at:
                                1
                        )
                )

            let heightText =
                source.substring(
                    with:
                        match.range(
                            at:
                                2
                        )
                )

            guard
                let width =
                    Double(
                        widthText
                    ),
                let height =
                    Double(
                        heightText
                    ),
                width.isFinite,
                height.isFinite,
                (1...30).contains(
                    width
                ),
                (1...30).contains(
                    height
                )
            else {
                continue
            }

            return CGSize(
                width:
                    width,
                height:
                    height
            )
        }

        return nil
    }

    /// Measured-template import never derives or changes manuscript geometry.
    func importMeasuredCover(template: URL, artwork: URL?) throws {
        var project = try CoverImport.project(from: template, asTemplate: true)
        guard project.activeKDPHardcoverLayout != nil else {
            throw WriterError.message("Use a recognized measured KDP hardcover PDF template.")
        }
        if let artwork {
            var layer = try CoverImport.layer(from: artwork, template: false, project: project)
            guard let pixels = layer.imageData else { throw WriterError.message("Cover artwork has no raster pixels.") }
            let image = try CoverArtwork.decodedRaster(pixels)
            let height = Double(image.height)/Double(image.width)*project.canvasWidth/project.canvasHeight
            layer.frame = CoverRect(x:0,y:(1-height)/2,width:1,height:height)
            project.layers.append(layer)
            for i in project.layers.indices where project.layers[i].isReferenceLayer { project.layers[i].visible = false }
        }
        var projects = document.metadata.coverProjects ?? []
        projects.append(project); try CoverProject.validate(projects)
        document.metadata.coverProjects = projects
        document.metadata.activeCoverProjectID = project.id; selectedProjectID = project.id
    }

    func createPrintCover(artwork: URL, binding: BookBinding, caliper: Double) throws {

        guard caliper.isFinite,
              caliper > 0,
              caliper < 0.1
        else {
            throw WriterError.message(
                "Invalid paper caliper in inches per page."
            )
        }

        let (pdf, _, pages) =
            try pagination()

        let page =
            pages.first
            ?? document.metadata.page

        let width =
            Double(
                page.pageSize.width
                / 72
            )

        let height =
            Double(
                page.pageSize.height
                / 72
            )

        let spine =
            Double(
                pdf.pageCount
            )
            * caliper

        let dimensions =
            try CoverCalculator.fullWrap(
                trimWidth:
                    width,
                trimHeight:
                    height,
                spineWidth:
                    spine,
                bleed:
                    0.125
            )

        var project =
            CoverProject(
                type:
                    .printFullWrap,
                width:
                    dimensions.totalWidthInches,
                height:
                    dimensions.totalHeightInches
            )

        project.trimWidth =
            width

        project.backWidth =
            width

        project.trimHeight =
            height

        project.spineWidth =
            spine

        project.bleed =
            0.125

        project.spinePageCount =
            pdf.pageCount

        project.spineCaliperInches =
            caliper

        project.productionBinding =
            binding

        project.name =
            artwork
                .deletingPathExtension()
                .lastPathComponent

        project.backgroundHex =
            "#111111"

        let sourceData =
            try Data(
                contentsOf:
                    artwork
            )

        var canonicalData =
            sourceData

        if let spec =
                Self.boldSourceWrapSpecV3(
                    filename:
                        artwork.lastPathComponent
                ),
           let sourceImage =
                NSImage(
                    data:
                        sourceData
                ),
           let sourceCG =
                sourceImage.cgImage(
                    forProposedRect:
                        nil,
                    context:
                        nil,
                    hints:
                        nil
                ),
           let sourceRegions =
                Self.boldSourceRegionsV3(
                    image:
                        sourceImage,
                    cgImage:
                        sourceCG,
                    spec:
                        spec,
                    caliper:
                        caliper
                )
        {
            canonicalData =
                try Self.boldAssembleCanonicalWrapV5(
                    sourceData:
                        sourceData,
                    sourceRegions:
                        sourceRegions,
                    project:
                        project,
                    totalWidthInches:
                        dimensions.totalWidthInches,
                    totalHeightInches:
                        dimensions.totalHeightInches
                )
        }

        var layer =
            try CoverArtwork.imageLayer(
                data:
                    canonicalData,
                filename:
                    "Canonical-"
                    + artwork.lastPathComponent
            )

        layer.name =
            "Canonical Full Wrap"

        layer.cropMode =
            .fill

        project.layers = [
            layer
        ]

        var projects =
            document.metadata.coverProjects
            ?? []

        projects.append(
            project
        )

        try CoverProject.validate(
            projects
        )

        document.metadata.coverProjects =
            projects

        document.metadata.activeCoverProjectID =
            project.id

        selectedProjectID =
            project.id
    }

    func execute(_ action: BOLDProjectAction) throws -> BOLDCommandResult {
        func required(_ key: String) throws -> String {
            guard let value = action.arguments[key], !value.isEmpty else {
                throw BOLDCommandError.missingArgument(key)
            }
            return value
        }
        var values: [String: String] = [:]
        var studio = document.metadata.bookStudioPresentation ?? .restingOpenPreviewDefault
        switch action.kind {
        case .documentFind:
            let query = try required("query")
            let text = document.text.string as NSString
            var ranges: [String] = []; var start = 0
            while start < text.length {
                let range = text.range(of: query, range: NSRange(location: start, length: text.length - start))
                if range.location == NSNotFound { break }
                ranges.append("\(range.location):\(range.length)"); start = NSMaxRange(range)
            }
            values["utf16Ranges"] = ranges.joined(separator: ",")
        case .manuscriptSetMetadata:
            document.metadata.title = try required("title")
        case .manuscriptSetTrimSize:
            let preset = try required("preset")
            let size = preset.lowercased().split(separator: "x").compactMap { Double($0) }
            guard size.count == 2, size.allSatisfy({ $0.isFinite && (1...30).contains($0) }) else {
                throw WriterError.message("Trim must be width x height in inches, such as 6x9.")
            }
            var metadata = document.metadata
            func apply(_ page: inout PageSettings) {
                page.paper = .custom; page.landscape = false
                page.customPaperSize = CGSize(width: size[0] * 72, height: size[1] * 72)
            }
            apply(&metadata.page)
            if var sections = metadata.sections {
                for i in sections.indices { apply(&sections[i].page) }; metadata.sections = sections
            }
            _ = try PageGeometry(metadata.page)
            document.metadata = metadata
            cachedPagination = nil
        case .coverOpen, .studioOpen:
            let index = try projectIndex(), project = document.metadata.coverProjects![index]
            values["projectID"] = project.id.uuidString
            values["layers"] = String(decoding: try JSONEncoder().encode(project.layers.map {
                ["id": $0.id.uuidString, "name": $0.name, "kind": $0.kind.rawValue, "text": $0.text]
            }), as: UTF8.self)
            values["trimInches"] = "\(project.trimWidth)x\(project.trimHeight)"
        case .coverInspect:
            values["snapshot"] = try CoverLayerCommands.inspect(document.metadata.coverProjects![try projectIndex()])
        case .coverUpdateLayer:
            try mutateProject { project in
                let id = try CoverLayerCommands.update(&project, arguments: action.arguments)
                values["layerID"] = id.uuidString
            }
            values["snapshot"] = try CoverLayerCommands.inspect(document.metadata.coverProjects![try projectIndex()])
        case .coverEdit:
            let operation = try required("operation")
            try mutateProject { project in
                let ids = try CoverProjectOperations.apply(operation, to: &project, arguments: action.arguments)
                values["layerIDs"] = ids.map(\.uuidString).joined(separator: ",")
            }
            values["snapshot"] = try CoverLayerCommands.inspect(document.metadata.coverProjects![try projectIndex()])
        case .applicationUndo, .applicationRedo:
            let index = try projectIndex()
            var project = document.metadata.coverProjects![index]
            if action.kind == .applicationUndo {
                guard coverUndo.last?.id == project.id else { throw WriterError.message("No cover edit to undo in this session.") }
                CoverProjectHistory.undo(project:&project, undo:&coverUndo, redo:&coverRedo)
            } else {
                guard coverRedo.last?.id == project.id else { throw WriterError.message("No cover edit to redo in this session.") }
                CoverProjectHistory.redo(project:&project, undo:&coverUndo, redo:&coverRedo)
            }
            document.metadata.coverProjects![index] = project
        case .coverAddText:
            let text = try required("text")
            try mutateProject { project in
                let panel = CoverWrapGeometry(project: project).frontTrim
                var layer = CoverLayer(kind: .text, name: "Automation text", frame: panel)
                layer.text = text; project.layers.append(layer)
                values["layerID"] = layer.id.uuidString
            }
        case .coverPlaceImage:
            let url = try Self.absoluteURL(required("path")), data = try Data(contentsOf: url)
            try mutateProject { project in
                if PSDImporter.recognizes(data) {
                    try CoverImport.replacePSD(data:data,filename:url.lastPathComponent,in:&project)
                    values["layerIDs"] = project.layers.map { $0.id.uuidString }.joined(separator:",")
                    return
                }
                let layer = try CoverArtwork.imageLayer(data: data, filename: url.lastPathComponent,
                    frame: CoverWrapGeometry(project: project).frontTrim)
                project.layers.append(layer); values["layerID"] = layer.id.uuidString
            }
        case .coverSetBackground:
            let color = try required("value")
            guard color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else {
                throw WriterError.message("Use a #RRGGBB background color.")
            }
            try mutateProject { $0.backgroundHex = color }
        case .studioSetBinding:
            let raw = try required("binding")
            guard let binding = BookBinding.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() || String(describing: $0) == raw.lowercased() }) else {
                throw WriterError.message("Binding must be softcover or hardcover.")
            }
            studio.binding = binding; try mutateProject { $0.productionBinding = binding }
        case .studioApplyPreset:
            let raw = try required("preset")
            guard let preset = BookStudioPreset.allCases.first(where: { $0.rawValue == raw || String(describing: $0) == raw }) else {
                throw WriterError.message("Unknown studio preset. Use front, back, spine, reading, paperback or hardcover.")
            }
            studio = preset.apply(to: studio)
        case .studioSetCamera:
            if let raw=action.arguments["productionMargins"] {
                guard ["true","false"].contains(raw) else { throw WriterError.message("productionMargins must be true or false.") }
                studio.showProductionMargins = raw == "true"
                values["productionMargins"] = raw
            }

            // BOLD_WRITER_V25_TRUE_CLOSED_AUTOMATION

            let raw = try required("camera")

            guard let preset = BookViewPreset.fromStudioCameraInput(raw) else {
                throw WriterError.message(
                    "Unknown camera. Available views: \(BookViewPreset.studioCameraChoices.joined(separator: ", "))."
                )
            }
            studio.cameraPreset = preset

            studio.savedCamera = nil



            let requestedOpen:

                Bool?



            if let rawOpen = action.arguments["open"] {

                switch rawOpen.lowercased() {

                case "true", "1", "yes", "open":

                    requestedOpen = true



                case "false", "0", "no", "closed":

                    requestedOpen = false



                default:

                    throw WriterError.message(

                        "Open must be true or false."

                    )

                }

            } else {

                requestedOpen = nil

            }



            if let rawAngle = action.arguments["openAngle"] {

                guard

                    let angle = Double(rawAngle),

                    angle.isFinite

                else {

                    throw WriterError.message(

                        "Open angle must be a number."

                    )

                }



                if requestedOpen == false {

                    guard (0...180).contains(angle) else {

                        throw WriterError.message(

                            "Closed-book angle must be between 0 and 180 degrees."

                        )

                    }



                    studio.open = false

                    studio.openAngle = 0

                } else {

                    guard (15...180).contains(angle) else {

                        throw WriterError.message(

                            "Open angle must be between 15 and 180 degrees."

                        )

                    }



                    studio.open =

                        requestedOpen

                        ?? true



                    studio.openAngle = angle

                }

            } else if let requestedOpen {

                studio.open = requestedOpen



                if !requestedOpen {

                    studio.openAngle = 0

                }

            }

case .studioSetLighting:
            let raw = try required("lighting")
            guard let preset = BookLightingPreset.allCases.first(where: { $0.rawValue == raw || String(describing: $0) == raw }) else {
                throw WriterError.message("Unknown lighting preset.")
            }
            studio.lighting = preset
        case .publishingPreflight:
            let (pdf, _, pages) = try pagination()
            let project = document.metadata.coverProjects![try projectIndex()]
            let assessment = PhysicalBookDiagnostics.publishingPreflight(
                project: project,
                manuscriptPageCount: pdf.pageCount,
                pageSettings: pages
            )
            values["pageCount"] = String(pdf.pageCount)
            values["coverPageCount"] = project.spinePageCount.map(String.init) ?? "unspecified"
            values["pageCountMismatch"] = PhysicalBookDiagnostics.pageCountMessage(coverPages:project.spinePageCount,manuscriptPages:pdf.pageCount) ?? "none"
            values["trimMismatchPages"] = PhysicalBookDiagnostics.trimMismatchPages(project: project, pages: pages).map(String.init).joined(separator: ",")
            values["spineMismatchInches"] = PhysicalBookDiagnostics.expectedSpineMismatch(project: project, manuscriptPages: pdf.pageCount).map(String.init(describing:)) ?? "none"
            values["productionStatus"] = assessment.status.rawValue
            values["productionReady"] = assessment.isReady ? "true" : "false"
            values["preflightErrors"] = assessment.errors.joined(separator: " | ")
            values["preflightWarnings"] = assessment.warnings.joined(separator: " | ")
        case .publishingExportPDF:
            let url = try newOutput(required("path"))
            try pagination().1.write(to: url, options: .atomic); values["path"] = url.path
        case .coverExport:
            let url = try newOutput(required("path")), project = document.metadata.coverProjects![try projectIndex()]
            if url.pathExtension.lowercased() == "pdf", project.type == .printFullWrap {
                let (pdf, _, pages) = try pagination()
                let assessment = PhysicalBookDiagnostics.publishingPreflight(
                    project: project,
                    manuscriptPageCount: pdf.pageCount,
                    pageSettings: pages
                )
                guard assessment.isReady else {
                    let detail = assessment.errors.joined(separator: " ")
                    throw WriterError.message("Print cover PDF export blocked: \(detail)")
                }
            }
            try CoverArtwork.export(project, format: url.pathExtension.lowercased()).write(to: url, options: .atomic)
            values["path"] = url.path
        case .coverConvertPaperback:
            let paper: PrintPaperStockPreset
            switch try required("paper").lowercased() {
            case "white": paper = .kdpWhite
            case "cream": paper = .kdpCream
            default: throw WriterError.message("Paperback paper must be white or cream.")
            }
            let (pdf, _, pages) = try pagination()
            guard let first = pages.first else { throw WriterError.message("The manuscript has no export-ready page settings.") }
            let width = Double(first.pageSize.width / 72)
            let height = Double(first.pageSize.height / 72)
            let trimInconsistent = pages.contains {
                abs(Double($0.pageSize.width / 72) - width) > 0.01
                    || abs(Double($0.pageSize.height / 72) - height) > 0.01
            }
            guard !trimInconsistent else { throw WriterError.message("Manuscript pages use mixed trim sizes. Resolve pagination before generating a print wrap.") }
            let source = document.metadata.coverProjects![try projectIndex()]
            guard let converted = PhysicalBookGeometry.adaptingArtworkToKDPPaperback(
                source,
                pageCount: pdf.pageCount,
                trimWidth: width,
                trimHeight: height,
                paperStock: paper
            ) else { throw WriterError.message("Could not generate a paperback wrap from this artwork and production profile.") }
            var projects = document.metadata.coverProjects ?? []
            projects.append(converted)
            try CoverProject.validate(projects)
            document.metadata.coverProjects = projects
            document.metadata.activeCoverProjectID = converted.id
            selectedProjectID = converted.id
            values["projectID"] = converted.id.uuidString
            values["pageCount"] = String(pdf.pageCount)
            values["trim"] = String(format: "%.4f × %.4f in", width, height)
            values["paper"] = paper.rawValue
            values["spineInches"] = String(converted.spineWidth)
            values["wrapInches"] = String(format: "%.4f × %.4f in", converted.canvasWidth, converted.canvasHeight)
        case .studioRenderStill:
            values = try render(action: action, studio: studio)
        default: throw BOLDCommandError.unsupportedAction(action.kind)
        }
        if [.studioSetBinding, .studioApplyPreset, .studioSetCamera, .studioSetLighting].contains(action.kind) {
            document.metadata.bookStudioPresentation = studio.normalized(pageCount: Int.max / 2)
        }
        return BOLDCommandResult(actionID: action.id, message: "Completed \(action.kind.rawValue)", values: values)
    }

    private func render(action: BOLDProjectAction, studio: BookStudioPresentation) throws -> [String: String] {
        guard let path = action.arguments["path"] else { throw BOLDCommandError.missingArgument("path") }
        let url = try newOutput(path)
        guard url.pathExtension.lowercased() == "png" else { throw WriterError.message("Studio still output must be PNG.") }
        let project = document.metadata.coverProjects![try projectIndex()]
        guard project.type == .printFullWrap else { throw WriterError.message("3D rendering requires a print full wrap.") }
        let (pdf, _, pages) = try pagination()
        let index = action.arguments["spread"].flatMap(Int.init) ?? studio.spreadIndex
        guard index >= 0, index <= pdf.pageCount / 2 else { throw WriterError.message("Spread is outside the manuscript.") }
        let spread = PhysicalBookGeometry.spread(at: index, pageCount: pdf.pageCount)
        func texture(_ number: Int?) -> NSImage? {
            number.flatMap { pdf.page(at: $0 - 1) }.flatMap { PhysicalBookPreview.renderManuscriptPage($0, maximumPixelSize: 2400) }
        }
        func settings(_ number: Int?) -> PageSettings {
            guard let number, pages.indices.contains(number - 1) else { return document.metadata.page }
            return pages[number - 1]
        }
        let scene = BookPreviewScene.make(project: project, workingLayers: false, open: studio.open, angle: studio.openAngle,
            leftPage: spread.leftPage, rightPage: spread.rightPage, pageCount: pdf.pageCount, spreadIndex: index,
            leftTexture: texture(spread.leftPage), rightTexture: texture(spread.rightPage), margins: false, thumbMode: .off,
            leftPageSettings: settings(spread.leftPage), rightPageSettings: settings(spread.rightPage),
            preset: studio.cameraPreset, revisionID: UUID(), binding: project.productionBinding ?? studio.binding,
            presentation: studio)
        let view = BookPreviewInteractionView(frame: NSRect(x: 0, y: 0, width: 1600, height: 1200))
        BookStudioCustomLightScene.apply(to: scene, presentation: studio, selectedCustomLightID: nil)
        BookStudioTransformScene.apply(to: scene, presentation: studio, selectedCustomLightID: nil)
        view.scene = scene; view.cameraNode = scene.rootNode.childNode(withName: "preview-camera", recursively: true)
        var camera = studio.savedCamera.map(BookPreviewCameraState.init(saved:))
            ?? BookPreviewCameraMath.state(project: project, open: studio.open, preset: studio.cameraPreset, focus: .automatic)
        if studio.savedCamera == nil {
            camera = BookPreviewCameraMath.fitBook(camera, in: scene, presentation: studio, viewportAspect: 4.0 / 3)
        }
        view.setCamera(camera)
        view.configureCamera(camera, projection: studio.projection, fieldOfView: studio.cameraFieldOfView)
        let handle = BookStudioViewportHandle(); handle.view = view; handle.coverProject = project
        guard let image = handle.image(size: CGSize(width: 1600, height: 1200), highQualityCover: true),
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            throw WriterError.message("3D renderer did not produce image pixels.")
        }
        try data.write(to: url, options: .atomic); images.append(url.path)
        return ["path": url.path, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                "pageCount": String(pdf.pageCount), "projectID": project.id.uuidString,
                "leftPage": spread.leftPage.map(String.init) ?? "inside cover",
                "rightPage": spread.rightPage.map(String.init) ?? "inside cover"]
    }
}
#endif
