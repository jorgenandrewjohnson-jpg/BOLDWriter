import AppKit

/// Cover transactions shared by menus, canvas helpers and file/AI automation.
/// Coordinates are normalized except guide/canvas measurements (inches).
enum CoverProjectOperations {
    static let maximumProjectCount = 8

    static func canAppendProject(existingCount: Int, hasOpenedProject: Bool) -> Bool {
        !hasOpenedProject || existingCount < maximumProjectCount
    }

    static let operations = ["psd-import", "move", "scale", "rotate", "crop", "align", "fit-panel", "group", "ungroup", "guide-add", "guide-clear",
                             "canvas-resize", "mask-add", "mask-invert", "mask-remove", "mask-apply",
                             "smart-embed", "smart-rasterize", "duplicate", "delete", "reorder"]

    static func replace(_ layer: CoverLayer, in project: inout CoverProject) throws {
        guard let i = project.layers.firstIndex(where: { $0.id == layer.id }) else {
            throw WriterError.message("The cover layer no longer exists.")
        }
        var next = project; next.layers[i] = layer
        try CoverProject.validate([next]); project = next
    }

    @discardableResult
    static func apply(_ operation: String, to project: inout CoverProject, arguments: [String:String]) throws -> [UUID] {
        guard operations.contains(operation) else { throw WriterError.message("Unknown cover operation.") }
        let fields: [String:Set<String>] = [
            "psd-import":["path"], "move":["dx","dy"], "scale":["scaleX","scaleY","pivotX","pivotY"],
            "rotate":["degrees","pivotX","pivotY"], "crop":["x","y","width","height"],
            "align":["edge","reference"], "fit-panel":["panel","includeBleed"],
            "group":["name"], "guide-add":["axis","position"],
            "canvas-resize":["width","height","anchorX","anchorY"],
            "mask-add":["coverage"], "reorder":["index"]
        ]
        let allowed = (fields[operation] ?? []).union(["layerID","layerIDs","operation"])
        guard arguments["operation"] == nil || arguments["operation"] == operation else { throw WriterError.message("Conflicting cover operation.") }
        guard Set(arguments.keys).isSubset(of:allowed),
              !(arguments["layerID"] != nil && arguments["layerIDs"] != nil) else {
            throw WriterError.message("Unknown or conflicting cover operation arguments.")
        }
        var next = project
        func number(_ key: String, default fallback: Double? = nil) throws -> Double {
            if let raw = arguments[key], let value = Double(raw), value.isFinite { return value }
            if arguments[key] == nil, let fallback { return fallback }
            throw WriterError.message("\(key) must be a finite number.")
        }
        let projectOperations = Set(["psd-import","canvas-resize","guide-add","guide-clear"])
        var ids = Set<UUID>()
        if !projectOperations.contains(operation) {
            let raw = arguments["layerIDs"] ?? arguments["layerID"] ?? ""
            let parts = raw.split(separator:",",omittingEmptySubsequences:false)
            let parsed = parts.compactMap { UUID(uuidString:String($0)) }
            guard !parsed.isEmpty, parsed.count == parts.count, Set(parsed).count == parsed.count,
                  parsed.allSatisfy({ id in next.layers.contains { $0.id == id } }) else {
                throw WriterError.message("Use existing comma-separated layerIDs from cover inspect.")
            }
            ids = Set(parsed)
            let targets = next.layers.filter { ids.contains($0.id) }
            guard !targets.contains(where: { $0.locked || ($0.isReferenceLayer && next.templateLocked) }) else {
                throw WriterError.message("Unlock the selected layers/template before editing.")
            }
            if ["move","scale","rotate","crop","align","fit-panel"].contains(operation), targets.contains(where: { $0.positionLocked == true }) {
                throw WriterError.message("A selected layer's position is locked.")
            }
        }
        if ["move","scale","rotate"].contains(operation) {
            ids = CoverEditorEngine.transformableLayerIDs(next.layers,ids:ids)
            guard !ids.isEmpty else { throw WriterError.message("No transformable artwork is selected.") }
            guard !next.layers.contains(where: { ids.contains($0.id) && $0.isReferenceLayer && next.templateLocked }) else {
                throw WriterError.message("The selected group contains a locked template.")
            }
        }
        var result = next.layers.filter { ids.contains($0.id) }.map(\.id)
        func single() throws -> Int {
            guard ids.count == 1, let i = next.layers.firstIndex(where: { ids.contains($0.id) }) else {
                throw WriterError.message("This operation requires one layerID.")
            }
            return i
        }
        switch operation {
        case "psd-import":
            guard let path = arguments["path"], path.hasPrefix("/"), !path.contains("\n"), !path.contains("\r") else { throw WriterError.message("PSD import requires an absolute local path.") }
            let url = URL(fileURLWithPath:path)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try CoverImport.replacePSD(data:Data(contentsOf:url),filename:url.lastPathComponent,in:&next)
            result = next.layers.map(\.id)
        case "move":
            CoverEditorEngine.moveLayers(&next.layers,ids:ids,dx:try number("dx"),dy:try number("dy"))
        case "scale", "rotate":
            let selected = next.layers.filter { ids.contains($0.id) }
            let minX = selected.map { $0.frame.x }.min()!, minY = selected.map { $0.frame.y }.min()!
            let maxX = selected.map { $0.frame.x+$0.frame.width }.max()!, maxY = selected.map { $0.frame.y+$0.frame.height }.max()!
            let pivot = CGPoint(x:try number("pivotX",default:(minX+maxX)/2),y:try number("pivotY",default:(minY+maxY)/2))
            if operation == "rotate" {
                CoverEditorEngine.rotateLayers(&next.layers,ids:ids,around:pivot,degrees:try number("degrees"),canvasSize:CGSize(width:next.canvasWidth,height:next.canvasHeight))
            } else {
                let x = try number("scaleX"), y = try number("scaleY",default:x)
                guard x > 0, y > 0, x <= 100, y <= 100 else { throw WriterError.message("Scale must be greater than zero and at most 100.") }
                CoverEditorEngine.scaleLayers(&next.layers,ids:ids,around:pivot,scaleX:x,scaleY:y)
            }
        case "align":
            let targets = next.layers.filter { ids.contains($0.id) }
            guard !targets.contains(where: { $0.kind == .group }) else {
                throw WriterError.message("Select ordinary artwork layers to align.")
            }
            let edges: [String:CoverAlignEdge] = ["left":.left,"centerX":.centerX,"right":.right,"top":.top,"centerY":.centerY,"bottom":.bottom]
            guard let edge = edges[arguments["edge"] ?? ""] else { throw WriterError.message("Choose left, centerX, right, top, centerY, or bottom.") }
            let geometry = CoverWrapGeometry(project: next)
            let references: [String:CoverRect] = ["canvas":CoverRect(x:0,y:0,width:1,height:1),"front":geometry.frontTrim,"back":geometry.backTrim,"spine":geometry.spineTrim]
            let name = arguments["reference"] ?? "selection"
            guard name == "selection" || references[name] != nil else { throw WriterError.message("Unknown alignment reference.") }
            guard name != "selection" || ids.count >= 2 else { throw WriterError.message("Select two layers, or align one layer to Canvas or a cover panel.") }
            let reference = references[name].map { CGRect(x:$0.x,y:$0.y,width:$0.width,height:$0.height) }
            CoverEditorEngine.align(&next.layers, ids:ids, edge:edge, reference:reference,
                                    canvasSize:CGSize(width:next.canvasWidth,height:next.canvasHeight))
        case "fit-panel":
            let i = try single(), geometry = CoverWrapGeometry(project: next)
            guard next.type == .printFullWrap, next.layers[i].imageData != nil || next.layers[i].kind == .shape else {
                throw WriterError.message("Auto Fit requires an image or shape in a full-wrap cover.")
            }
            let bleed = arguments["includeBleed"] ?? "true"
            guard ["true","false"].contains(bleed) else { throw WriterError.message("includeBleed must be true or false.") }
            let panel: CoverRect
            switch arguments["panel"] {
            case "front": panel = bleed == "true" ? geometry.front : geometry.frontTrim
            case "back": panel = bleed == "true" ? geometry.back : geometry.backTrim
            case "spine": panel = geometry.spineTrim
            default: throw WriterError.message("Choose front, spine, or back.")
            }
            guard panel.width > 0, panel.height > 0 else { throw WriterError.message("The chosen panel has no printable area.") }
            next.layers[i].frame = panel
            next.layers[i].rotation = 0; next.layers[i].skewX = nil; next.layers[i].skewY = nil
            next.layers[i].perspectiveCorners = nil; next.layers[i].warpPreset = nil; next.layers[i].warpAmount = nil
            next.layers[i].sourceCrop = nil
            next.layers[i].cropMode = .fill; next.layers[i].cropOffsetX = 0; next.layers[i].cropOffsetY = 0
        case "crop":
            let i = try single()
            guard next.layers[i].imageData != nil else { throw WriterError.message("Crop requires raster artwork.") }
            let rect = CoverRect(x:try number("x"),y:try number("y"),width:try number("width"),height:try number("height"))
            guard rect.x >= 0, rect.y >= 0, rect.width > 0, rect.height > 0,
                  rect.x+rect.width <= 1.000001, rect.y+rect.height <= 1.000001 else { throw WriterError.message("Crop must lie inside the source image (0...1).") }
            next.layers[i].sourceCrop = CoverEditorEngine.composeCrop(existing:next.layers[i].sourceCrop,selection:rect)
        case "group":
            guard ids.count >= 2, !next.layers.contains(where: { ids.contains($0.id) && $0.kind == .group }) else {
                throw WriterError.message("Select at least two ordinary layers to group.")
            }
            let group = CoverLayer(kind:.group,name:arguments["name"] ?? "Group",frame:CoverRect(x:0,y:0,width:1,height:1))
            next.layers.append(group)
            for i in next.layers.indices where ids.contains(next.layers[i].id) { next.layers[i].groupID = group.id }
            result = [group.id]
        case "ungroup":
            let i = try single(), group = next.layers[i]
            guard group.kind == .group else { throw WriterError.message("Ungroup requires a group layer.") }
            result = next.layers.filter { $0.groupID == group.id }.map(\.id)
            for i in next.layers.indices where next.layers[i].groupID == group.id { next.layers[i].groupID = group.groupID }
            next.layers.removeAll { $0.id == group.id }
        case "guide-add":
            guard next.guidesLocked != true else { throw WriterError.message("Guides are locked.") }
            let axis = arguments["axis"] ?? "", position = try number("position")
            guard axis == "x" || axis == "y", position >= 0,
                  position <= (axis == "x" ? next.canvasWidth:next.canvasHeight) else { throw WriterError.message("Guide position must lie inside the canvas, in inches.") }
            if axis == "x" { next.userGuidesX = (next.userGuidesX ?? [])+[position] }
            else { next.userGuidesY = (next.userGuidesY ?? [])+[position] }
        case "guide-clear":
            guard next.guidesLocked != true else { throw WriterError.message("Guides are locked.") }
            next.userGuidesX = []; next.userGuidesY = []
        case "canvas-resize":
            guard next.activeKDPHardcoverLayout == nil else { throw WriterError.message("Measured KDP canvas dimensions cannot be resized. Import a matching template instead.") }
            let width = try number("width"), height = try number("height")
            guard width > 0, height > 0, width <= 100, height <= 100 else { throw WriterError.message("Canvas dimensions must be 0...100 inches, excluding zero.") }
            let ax = try number("anchorX",default:0.5), ay = try number("anchorY",default:0.5)
            guard (0...1).contains(ax),(0...1).contains(ay) else { throw WriterError.message("Canvas anchors must be 0...1.") }
            for i in next.layers.indices {
                let frame = next.layers[i].frame
                next.layers[i].frame = CoverRect(x:(frame.x*next.canvasWidth+(width-next.canvasWidth)*ax)/width,
                    y:(frame.y*next.canvasHeight+(height-next.canvasHeight)*ay)/height,
                    width:frame.width*next.canvasWidth/width,height:frame.height*next.canvasHeight/height)
            }
            let offsetX = (width-next.canvasWidth)*ax, offsetY = (height-next.canvasHeight)*ay
            next.userGuidesX = next.userGuidesX?.map { $0+offsetX }.filter { (0...width).contains($0) }
            next.userGuidesY = next.userGuidesY?.map { $0+offsetY }.filter { (0...height).contains($0) }
            next.canvasWidth = width; next.canvasHeight = height
            if next.type == .ebookFront { next.trimWidth = width; next.trimHeight = height; next.backWidth = width }
        case "mask-add", "mask-invert", "mask-remove", "mask-apply":
            let i = try single()
            guard let data = next.layers[i].imageData, let rep = NSBitmapImageRep(data:data),
                  rep.pixelsWide <= 20_000, rep.pixelsHigh <= 20_000,
                  rep.pixelsWide <= 100_000_000/max(1,rep.pixelsHigh) else { throw WriterError.message("Masks require bounded raster artwork.") }
            let width = rep.pixelsWide, height = rep.pixelsHigh
            if operation == "mask-remove" { next.layers[i].maskData = nil; next.layers[i].maskEnabled = nil }
            else if operation == "mask-add" {
                guard next.layers[i].maskData == nil else { throw WriterError.message("The layer already has a mask.") }
                let fill = try number("coverage",default:1)
                guard (0...1).contains(fill) else { throw WriterError.message("Mask coverage must be 0...1.") }
                next.layers[i].maskData = CoverEditorEngine.encodedMask(Data(repeating:UInt8((fill*255).rounded()),count:width*height),width:width,height:height)
                next.layers[i].maskEnabled = true
            } else {
                guard let data = next.layers[i].maskData, let mask = CoverEditorEngine.decodedMask(data,width:width,height:height) else { throw WriterError.message("The layer has no valid mask.") }
                if operation == "mask-invert" {
                    next.layers[i].maskData = CoverEditorEngine.encodedMask(CoverEditorEngine.inverted(mask),width:width,height:height)
                } else {
                    guard next.layers[i].kind != .smartObject else { throw WriterError.message("Rasterize the Smart Object before baking its mask.") }
                    if next.layers[i].maskEnabled != false {
                        next.layers[i].imageData = try CoverEditorEngine.applyRasterMask(next.layers[i].imageData!,
                            maskImageData:data,density:next.layers[i].maskDensity ?? 1,
                            offsetX:next.layers[i].maskOffsetX ?? 0,offsetY:next.layers[i].maskOffsetY ?? 0)
                    }
                    next.layers[i].maskData = nil; next.layers[i].maskEnabled = nil
                }
            }
        case "smart-embed", "smart-rasterize":
            let i = try single()
            let converted = operation == "smart-embed" ? CoverEditorEngine.embeddingLinkedSmartObject(in:next.layers[i]) : CoverEditorEngine.rasterizingSmartObject(next.layers[i])
            guard let converted else { throw WriterError.message("This Smart Object operation is unavailable for the layer.") }
            next.layers[i] = converted
        case "duplicate":
            let selected = next.layers.filter { ids.contains($0.id) }
            guard !selected.contains(where: { $0.kind == .group }) else { throw WriterError.message("Duplicate group members explicitly.") }
            let copies = CoverEditorEngine.duplicateLinkedLayers(&next.layers,ids:ids)
            result = next.layers.filter { copies.contains($0.id) }.map(\.id)
        case "delete":
            guard !next.layers.contains(where: { ids.contains($0.id) && $0.kind == .group }) else { throw WriterError.message("Ungroup before deleting a group.") }
            next.layers.removeAll { ids.contains($0.id) }
            for i in next.layers.indices {
                if next.layers[i].clippedToLayerID.map({ ids.contains($0) }) == true { next.layers[i].clippedToLayerID = nil }
                if next.layers[i].linkSourceID.map({ ids.contains($0) }) == true { next.layers[i].linkSourceID = nil }
            }
        case "reorder":
            let i = try single(), value = try number("index")
            guard value.rounded() == value, value >= 0, value < Double(next.layers.count) else { throw WriterError.message("Use a valid integer stack index.") }
            let layer = next.layers.remove(at:i); next.layers.insert(layer,at:Int(value))
        default: break
        }
        try CoverProject.validate([next]); project = next; return result
    }
}
