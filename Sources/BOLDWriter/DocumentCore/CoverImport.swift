import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Imports are embedded artwork. Templates are reference overlays, not project documents.
enum CoverImport {
    static var imageTypes: [UTType] {
        let decoders=Set(CGImageSourceCopyTypeIdentifiers() as! [String])
        var types=[UTType.png,.jpeg,.heic,.heif,.tiff].filter { decoders.contains($0.identifier) }
        if decoders.contains("com.adobe.photoshop-image"),let photoshop=UTType(filenameExtension:"psd") {
            types.append(photoshop)
        }
        return types
    }

    static func replacingImageContents(in layer: CoverLayer, from url: URL) throws -> CoverLayer {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try CoverEditorEngine.replacingImageContents(in: layer, data: Data(contentsOf: url))
    }

    /// Replace artwork atomically, preserving the existing print-panel measurements.
    /// Rounded PSD pixels do not redefine exact physical trim/spine geometry.
    static func replacePSD(data: Data, filename: String, in project: inout CoverProject) throws {
        guard !project.layers.contains(where: { $0.locked || $0.positionLocked == true || $0.pixelsLocked == true || ($0.isReferenceLayer && project.templateLocked) }) else {
            throw WriterError.message("Unlock existing cover layers before replacing artwork with a PSD.")
        }
        let imported = try PSDImporter.read(data, filename: filename)
        guard imported.project.rasterPixelSize == project.rasterPixelSize,
              abs(imported.project.dpi-project.dpi) < 0.00001 else {
            throw WriterError.message("PSD canvas pixels and resolution must match this cover. Use Open Image as Cover for a different canvas.")
        }
        var next = project; next.layers = imported.project.layers
        next.psdImportWarnings = imported.warnings
        try CoverProject.validate([next]); project = next
    }

    static var smartObjectTypes:
        [UTType]
    {
        var types:
            [UTType] =
            [
                .pdf
            ]

        if let svg =
                UTType(
                    filenameExtension:
                        "svg"
                )
        {
            types.append(
                svg
            )
        }

        for type
            in imageTypes
            where !types.contains(
                where: {
                    $0.identifier
                        == type.identifier
                }
            )
        {
            types.append(
                type
            )
        }

        return types
    }


    /// Opening an image creates a canvas at its pixel dimensions and resolution.
    /// Photoshop files preserve supported editable layers; templates remain reference overlays.
    static func project(from url: URL, asTemplate: Bool = false) throws -> CoverProject {
        let scoped=url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try project(data:Data(contentsOf:url),filename:url.lastPathComponent,asTemplate:asTemplate)
    }

    static func project(data: Data, filename: String, asTemplate: Bool = false) throws -> CoverProject {
        if PSDImporter.recognizes(data), !asTemplate {
            let imported = try PSDImporter.read(data, filename: filename)
            var project = imported.project; project.psdImportWarnings = imported.warnings
            return project
        }
        let isPDF=filename.lowercased().hasSuffix(".pdf")
        let layout = isPDF ? try hardcoverLayout(data: data) : nil
        let isTemplate = asTemplate || layout != nil
        let raster=isPDF ? nil : try CoverArtwork.decodedRaster(data)
        let pdfTemplate=isPDF && layout == nil ? try CoverArtwork.importedTemplate(data:data,filename:filename) : nil
        let source=isPDF ? nil : CGImageSourceCreateWithData(data as CFData,nil)
        let properties=source.flatMap { CGImageSourceCopyPropertiesAtIndex($0,0,nil) as? [CFString:Any] }
        let psdResolution = try photoshopResolution(data: data)
        let resolution = psdResolution ?? (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 300
        let dpi=resolution.isFinite && resolution >= 1 && resolution <= 2400 ? resolution : 300
        let safeDPI:Double
        let width:Double, height:Double
        if let raster {
            safeDPI=max(dpi,Double(raster.width)/100,Double(raster.height)/100)
            width=Double(raster.width)/safeDPI
            height=Double(raster.height)/safeDPI
        } else {
            safeDPI=300
            width=layout?.canvasWidth ?? pdfTemplate?.frame.width ?? 0
            height=layout?.canvasHeight ?? pdfTemplate?.frame.height ?? 0
        }
        guard safeDPI <= 2400 else { throw WriterError.message("The image is too large for a cover canvas.") }
        var project=CoverProject(type:isTemplate ? .printFullWrap : .ebookFront,width:width,height:height)
        project.name=URL(fileURLWithPath:filename).deletingPathExtension().lastPathComponent
        project.dpi=safeDPI
        let layer:CoverLayer
        if isTemplate {
            var reference=pdfTemplate ?? CoverLayer(kind:.template,name:filename)
            reference.frame=CoverRect()
            if let raster { reference.imageData=raster.data }
            reference.locked=true
            reference.opacity=0.45
            layer=reference
            // The image establishes the canvas; print trim and spine measurements
            // must be set from the printer's specification before final export.
            project.backWidth=width/2
            project.trimWidth=width/2
            project.spineWidth=0
            project.guidesVisible=false
        } else {
            var image=CoverLayer(kind:.image,name:filename)
            image.imageData=raster?.data ?? pdfTemplate?.imageData
            layer=image
        }
        if let layout {
            project.canvasWidth=layout.canvasWidth
            project.canvasHeight=layout.canvasHeight
            project.trimWidth=layout.trimWidth
            project.backWidth=layout.trimWidth
            project.trimHeight=layout.trimHeight
            project.spineWidth=layout.spineWidth
            project.spinePageCount=layout.pageCount
            project.productionBinding = .hardcover
            project.kdpHardcoverLayout=layout
            project.guidesVisible=true
        }
        project.layers = layout != nil ? try CoverPDFLayers.layers(data: data) : [layer]
        try CoverProject.validate([project])
        return project
    }

    /// ImageIO does not expose PSD ResolutionInfo on every macOS version.
    /// Read the bounded standard image-resource section so composite imports
    /// retain their physical size. Editable Photoshop layers are still unsupported.
    static func photoshopResolution(data: Data) throws -> Double? {
        guard data.starts(with: Data("8BPS".utf8)) else { return nil }
        func integer(_ offset: Int, _ count: Int, limit: Int) throws -> Int {
            guard offset >= 0, count <= limit, offset <= limit - count else {
                throw WriterError.message("The Photoshop image-resource section is truncated.")
            }
            return data[offset..<(offset + count)].reduce(0) { ($0 << 8) | Int($1) }
        }
        let colorLength = try integer(26, 4, limit: data.count)
        guard colorLength <= data.count - 30 else {
            throw WriterError.message("The Photoshop color-data section is truncated.")
        }
        var cursor = 30 + colorLength
        let resourceLength = try integer(cursor, 4, limit: data.count)
        cursor += 4
        guard resourceLength <= data.count - cursor else {
            throw WriterError.message("The Photoshop image-resource section is truncated.")
        }
        let end = cursor + resourceLength
        while cursor < end {
            guard try integer(cursor, 4, limit: end) == 0x3842494D else {
                throw WriterError.message("The Photoshop image-resource signature is invalid.")
            }
            let identifier = try integer(cursor + 4, 2, limit: end)
            let nameLength = try integer(cursor + 6, 1, limit: end)
            cursor += 6 + ((nameLength + 2) / 2) * 2
            let length = try integer(cursor, 4, limit: end)
            cursor += 4
            guard length <= end - cursor else {
                throw WriterError.message("The Photoshop image-resource payload is truncated.")
            }
            if identifier == 1005 {
                guard length == 16 else {
                    throw WriterError.message("The Photoshop resolution resource is invalid.")
                }
                func axis(_ offset: Int) throws -> Double {
                    let value = Double(try integer(offset, 4, limit: end)) / 65_536
                    let unit = try integer(offset + 4, 2, limit: end)
                    guard unit == 1 || unit == 2, value.isFinite, value > 0 else {
                        throw WriterError.message("The Photoshop resolution units are unsupported.")
                    }
                    return unit == 2 ? value * 2.54 : value
                }
                let horizontal = try axis(cursor), vertical = try axis(cursor + 8)
                guard abs(horizontal - vertical) < 0.001 else {
                    throw WriterError.message("This Photoshop image has unequal horizontal and vertical resolution; BOLD Writer cannot preserve its physical geometry.")
                }
                guard (1...2400).contains(horizontal) else {
                    throw WriterError.message("The Photoshop resolution is outside the supported print range.")
                }
                return horizontal
            }
            cursor += length + length % 2
            guard cursor <= end else {
                throw WriterError.message("The Photoshop image-resource padding is truncated.")
            }
        }
        return nil
    }

    /// Read the document content, not its filename: renamed templates still work.
    static func hardcoverLayout(data: Data) throws -> KDPHardcoverLayout? {
        guard let pdf = PDFDocument(data: data), let page = pdf.page(at: 0),
              let text = page.string, text.contains("Hardcover Book"),
              text.contains("Cover Template"), text.contains("Spine Fold") else { return nil }
        func numbers(_ pattern: String) -> [Double]? {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            return (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: text).flatMap { Double(text[$0]) }
            }
        }
        guard text.contains("Left to Right"),
              let trim = numbers(#"([0-9.]+)"\s*x\s*([0-9.]+)"\s*Book"#), trim.count == 2,
              let size = numbers(#"([0-9.]+)"\s*x\s*([0-9.]+)"\s*Overall Dimensions"#), size.count == 2,
              let spine = numbers(#"Spine Width\s*([0-9.]+)""#)?.first,
              let pages = numbers(#"([0-9]+)\s*Pages"#)?.first,
              pages.isFinite, (76...550).contains(pages) else {
            throw WriterError.message("This hardcover template could not be measured. Use a KDP left-to-right PDF with readable trim, spine, and overall dimensions.")
        }
        let layout = KDPHardcoverLayout(canvasWidth: size[0], canvasHeight: size[1],
            trimWidth: trim[0], trimHeight: trim[1], spineWidth: spine, pageCount: Int(pages))
        var check = CoverProject(type: .printFullWrap, width: size[0], height: size[1])
        check.trimWidth=trim[0]; check.backWidth=trim[0]; check.trimHeight=trim[1]
        check.spineWidth=spine; check.productionBinding = .hardcover
        let bounds = page.bounds(for: .mediaBox)
        guard layout.matches(check), page.rotation % 180 == 0,
              abs(bounds.width/72-size[0]) < 0.01, abs(bounds.height/72-size[1]) < 0.01 else {
            throw WriterError.message("The hardcover PDF page size does not agree with its printed measurements. Download an unscaled KDP template.")
        }
        return layout
    }

    static func layer(from url: URL, template: Bool, project: CoverProject) throws -> CoverLayer {
        let scoped=url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try layer(data:Data(contentsOf:url),filename:url.lastPathComponent,template:template,project:project)
    }

    static func smartObjectLayer(
        from url: URL,
        project: CoverProject
    ) throws -> CoverLayer {
        let scoped =
            url.startAccessingSecurityScopedResource()

        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try CoverEditorEngine
            .smartObjectLayerFromEmbeddedSource(
                data:
                    Data(
                        contentsOf:
                            url
                    ),
                filename:
                    url.lastPathComponent,
                project:
                    project
            )
    }

    static func replacingSmartObjectContents(
        in layer: CoverLayer,
        from url: URL
    ) throws -> CoverLayer? {
        let scoped =
            url.startAccessingSecurityScopedResource()

        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try CoverEditorEngine
            .replacingSmartObjectContents(
                in:
                    layer,
                data:
                    Data(
                        contentsOf:
                            url
                    ),
                filename:
                    url.lastPathComponent
            )
    }


    static func layer(data: Data, filename: String, template: Bool, project: CoverProject) throws -> CoverLayer {
        if PSDImporter.recognizes(data), !template {
            throw WriterError.message("Use Import Image or Open Image as Cover to preserve editable PSD layers.")
        }
        var layer: CoverLayer
        let width: Double, height: Double
        if template {
            layer=try CoverArtwork.importedTemplate(data:data,filename:filename)
            width=layer.frame.width; height=layer.frame.height
        } else if filename.lowercased().hasSuffix(".pdf") || data.starts(with: Data("%PDF".utf8)) {
            layer=try CoverArtwork.importedTemplate(data:data,filename:filename)
            width=layer.frame.width; height=layer.frame.height
            layer.kind = .image; layer.locked=false; layer.opacity=1
        } else {
            layer=try CoverArtwork.imageLayer(data:data,filename:filename)
            let raster=try CoverArtwork.decodedRaster(layer.imageData!)
            width=Double(raster.width)/project.dpi; height=Double(raster.height)/project.dpi
        }
        // A wrap-shaped image imported into a measured template is a complete
        // back/spine/front design. Keep its center on the physical spine instead
        // of inserting a small, DPI-sized image in the middle of the canvas.
        if !template, project.activeKDPHardcoverLayout != nil,
           abs((width / height) / (project.canvasWidth / project.canvasHeight) - 1) < 0.1 {
            layer.frame = CoverRect()
            layer.cropMode = .fit
            return layer
        }
        let scale=min(1,project.canvasWidth/width,project.canvasHeight/height)
        let w=width*scale/project.canvasWidth, h=height*scale/project.canvasHeight
        layer.frame=CoverRect(x:(1-w)/2,y:(1-h)/2,width:w,height:h)
        return layer
    }

    /// Commit only after decoding and validation succeed, using the editor's snapshot history.
    static func apply(_ layer: CoverLayer, project: inout CoverProject, undo: inout [CoverProject],
                      redo: inout [CoverProject], selectedID: inout UUID?, selectedIDs: inout Set<UUID>) throws {
        var next=project
        if !layer.isReferenceLayer, let reference = next.layers.firstIndex(where: { $0.isReferenceLayer }) {
            next.layers.insert(layer, at: reference)
            // Native trim/spine/hinge guides remain visible over artwork. The
            // editable printer instructions can be shown again with the group eye.
            for index in next.layers.indices where next.layers[index].kind == .group && next.layers[index].referenceOnly == true {
                next.layers[index].visible = false
            }
        } else { next.layers.append(layer) }
        try CoverProject.validate([next])
        undo.append(project)
        if undo.count>50 { undo.removeFirst() }
        redo=[]
        project=next
        selectedID=layer.id; selectedIDs=[layer.id]
    }


    static func linkedSmartObjectLayer(
        from url: URL,
        project: CoverProject
    ) throws -> CoverLayer {
        try CoverEditorEngine
            .smartObjectLayerFromLinkedSource(
                url:
                    url,
                project:
                    project
            )
    }

    static func updatingLinkedSmartObjectContents(
        in layer: CoverLayer
    ) throws -> CoverLayer? {
        try CoverEditorEngine
            .updatingLinkedSmartObjectContents(
                in:
                    layer
            )
    }

    static func relinkingSmartObjectContents(
        in layer: CoverLayer,
        from url: URL
    ) throws -> CoverLayer? {
        try CoverEditorEngine
            .relinkingSmartObject(
                in:
                    layer,
                to:
                    url
            )
    }

}

/// Shared snapshot operations used by the editor and import regression tests.
enum CoverProjectHistory {
    /// Returns the complete value-semantic project state stored in undo history.
    /// Keep this as an identity copy unless a history representation is changed
    /// together with explicit, lossless restore and matching behavior.
    static func snapshot(_ project: CoverProject) -> CoverProject {
        project
    }

    /// Compares an undo snapshot with the current document state. The editor
    /// uses this to avoid adding duplicate entries while a gesture is active.
    static func matches(_ snapshot: CoverProject, project: CoverProject) -> Bool {
        snapshot == project
    }

    static func undo(project: inout CoverProject, undo: inout [CoverProject], redo: inout [CoverProject]) {
        guard let prior=undo.popLast() else { return }
        redo.append(project); project=prior
    }
    static func redo(project: inout CoverProject, undo: inout [CoverProject], redo: inout [CoverProject]) {
        guard let next=redo.popLast() else { return }
        undo.append(project); project=next
    }
    static func placeImage(project:inout CoverProject,layerID:UUID,region:CoverRect,fill:Bool,undo:inout [CoverProject],redo:inout [CoverProject]) {
        guard let index=project.layers.firstIndex(where:{$0.id == layerID}),!project.layers[index].locked,project.layers[index].imageData != nil else{return}
        undo.append(project);redo=[]
        project.layers[index]=CoverCalculator.placement(project.layers[index],in:project,region:region,fill:fill)
    }
}
