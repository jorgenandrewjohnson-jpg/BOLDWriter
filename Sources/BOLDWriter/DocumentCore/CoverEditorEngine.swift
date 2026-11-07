import AppKit
import CoreImage
import Foundation
import Vision
import CoreVideo

import SwiftUI
enum CoverChannelPreviewKind: String, CaseIterable, Identifiable {
    case composite = "Composite"
    case red = "Red"
    case green = "Green"
    case blue = "Blue"
    case alpha = "Alpha"

    var id: String {
        rawValue
    }
}

/// Pixel and layer operations shared by the cover canvas and its tests. Coordinates are image pixels,
/// with (0,0) at the top left. The source image bytes are retained; transforms stay in layer metadata.
struct CoverVectorAnchorIndex: Hashable {
    let contourIndex: Int
    let pointIndex: Int
}

struct CoverVectorSelectionBounds:
    Equatable
{
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    var width: Double {
        maxX - minX
    }

    var height: Double {
        maxY - minY
    }

    var centerX: Double {
        (
            minX
            + maxX
        )
        / 2
    }

    var centerY: Double {
        (
            minY
            + maxY
        )
        / 2
    }
}


struct CoverVectorSegmentHit: Equatable {
    let contourIndex: Int
    let startPointIndex: Int
    let t: Double
    let distance: Double
}

struct CoverVectorStrokeGeometry: Equatable {
    let lineWidth: Double
    let cap: CoverStrokeCap
    let join: CoverStrokeJoin
    let miterLimit: Double
    let dashPattern: [Double]
    let dashPhase: Double
}


struct CoverVectorSegmentInsertion {
    let layer: CoverLayer
    let anchor: CoverVectorAnchorIndex
}

struct CoverVectorJoinResult {
    let layer: CoverLayer
    let selectedAnchors: Set<CoverVectorAnchorIndex>
    let activeAnchor: CoverVectorAnchorIndex
}

struct CoverVectorSplitResult {
    let layer: CoverLayer
    let selectedAnchors: Set<CoverVectorAnchorIndex>
    let activeAnchor: CoverVectorAnchorIndex
}

struct CoverVectorContourMutationResult {
    let layer: CoverLayer
    let contourIndex: Int
    let selectedAnchors: Set<CoverVectorAnchorIndex>
    let activeAnchor: CoverVectorAnchorIndex?
}

enum CoverVectorContourOrderMove {
    case forward
    case backward
    case front
    case back
}

struct CoverVectorContourOrderResult {
    let layer: CoverLayer
    let contourIndex: Int
    let selectedAnchors: Set<CoverVectorAnchorIndex>
    let activeAnchor: CoverVectorAnchorIndex?
}






enum CoverVectorBooleanOperation:
    String,
    CaseIterable,
    Identifiable
{
    case union
    case subtract
    case intersect
    case exclude

    var id:String {
        rawValue
    }

    var title:String {
        switch self {
        case .union:
            "Union"
        case .subtract:
            "Subtract"
        case .intersect:
            "Intersect"
        case .exclude:
            "Exclude"
        }
    }
}

enum CoverEditorEngine {

    static func vectorFillRule(
        for layer: CoverLayer
    ) -> CoverFillRule {
        layer.fillRule
        ?? .evenOdd
    }

    static func configureVectorFillRule(
        _ path: NSBezierPath,
        layer: CoverLayer
    ) {
        switch vectorFillRule(
            for:
                layer
        ) {
        case .evenOdd:
            path.windingRule =
                .evenOdd

        case .nonZero:
            path.windingRule =
                .nonZero
        }
    }


    static func vectorStrokeGeometry(
        for layer: CoverLayer
    ) -> CoverVectorStrokeGeometry {
        let lineWidth =
            (
                layer.strokeWidth.isFinite
                && layer.strokeWidth >= 0
            )
            ? layer.strokeWidth
            : 0

        let rawMiterLimit =
            layer.strokeMiterLimit
            ?? CoverStrokeValidation.defaultMiterLimit

        let miterLimit =
            (
                rawMiterLimit.isFinite
                && rawMiterLimit >= 1
                && rawMiterLimit
                    <= CoverStrokeValidation.maximumMiterLimit
            )
            ? rawMiterLimit
            : CoverStrokeValidation.defaultMiterLimit

        let rawPattern =
            layer.strokeDashPattern
            ?? []

        let dashPattern: [Double]

        if rawPattern.count
                <= CoverStrokeValidation.maximumDashCount
            && rawPattern.allSatisfy({
                $0.isFinite
                && $0 > 0
                && $0
                    <= CoverStrokeValidation.maximumDashValue
            })
        {
            dashPattern =
                rawPattern
        } else {
            dashPattern =
                []
        }

        let rawPhase =
            layer.strokeDashPhase
            ?? 0

        let dashPhase =
            (
                rawPhase.isFinite
                && abs(rawPhase)
                    <= CoverStrokeValidation.maximumDashValue
            )
            ? rawPhase
            : 0

        return CoverVectorStrokeGeometry(
            lineWidth:
                lineWidth,
            cap:
                layer.strokeCap
                ?? .butt,
            join:
                layer.strokeJoin
                ?? .miter,
            miterLimit:
                miterLimit,
            dashPattern:
                dashPattern,
            dashPhase:
                dashPhase
        )
    }

    static func configureVectorStroke(
        _ path: NSBezierPath,
        layer: CoverLayer
    ) {
        let geometry =
            vectorStrokeGeometry(
                for:
                    layer
            )

        path.lineWidth =
            CGFloat(
                geometry.lineWidth
            )

        switch geometry.cap {
        case .butt:
            path.lineCapStyle =
                .butt

        case .round:
            path.lineCapStyle =
                .round

        case .square:
            path.lineCapStyle =
                .square
        }

        switch geometry.join {
        case .miter:
            path.lineJoinStyle =
                .miter

        case .round:
            path.lineJoinStyle =
                .round

        case .bevel:
            path.lineJoinStyle =
                .bevel
        }

        path.miterLimit =
            CGFloat(
                geometry.miterLimit
            )

        let dashPattern: [CGFloat] =
            geometry
                .dashPattern
                .map {
                    value in

                    CGFloat(
                        value
                    )
                }

        path.setLineDash(
            dashPattern,
            count:
                dashPattern.count,
            phase:
                CGFloat(
                    geometry.dashPhase
                )
        )
    }

    static func configureVectorStroke(
        _ context: CGContext,
        layer: CoverLayer
    ) {
        let geometry =
            vectorStrokeGeometry(
                for:
                    layer
            )

        context.setLineWidth(
            CGFloat(
                geometry.lineWidth
            )
        )

        switch geometry.cap {
        case .butt:
            context.setLineCap(
                .butt
            )

        case .round:
            context.setLineCap(
                .round
            )

        case .square:
            context.setLineCap(
                .square
            )
        }

        switch geometry.join {
        case .miter:
            context.setLineJoin(
                .miter
            )

        case .round:
            context.setLineJoin(
                .round
            )

        case .bevel:
            context.setLineJoin(
                .bevel
            )
        }

        context.setMiterLimit(
            CGFloat(
                geometry.miterLimit
            )
        )

        let dashLengths: [CGFloat] =
            geometry
                .dashPattern
                .map {
                    value in

                    CGFloat(
                        value
                    )
                }

        context.setLineDash(
            phase:
                CGFloat(
                    geometry.dashPhase
                ),
            lengths:
                dashLengths
        )
    }

    static func move(_ layer: inout CoverLayer, dx: Double, dy: Double) { guard !layer.locked, layer.positionLocked != true else{return};layer.frame.x += dx;layer.frame.y += dy }
    static func resize(_ layer: inout CoverLayer, width: Double, height: Double, proportional: Bool = false) { guard !layer.locked,layer.positionLocked != true,width.isFinite,height.isFinite,width>0,height>0 else{return};if proportional{let ratio=layer.frame.width/max(0.0001,layer.frame.height);layer.frame.width=width;layer.frame.height=width/ratio}else{layer.frame.width=width;layer.frame.height=height} }
    static func rotate(_ layer: inout CoverLayer, degrees: Double) { guard !layer.locked,degrees.isFinite else{return};layer.rotation=(layer.rotation+degrees).truncatingRemainder(dividingBy:360) }
    static func flip(_ layer: inout CoverLayer, horizontal: Bool) { guard !layer.locked else{return};if horizontal{layer.flipHorizontal.toggle()}else{layer.flipVertical.toggle()} }
    /// Replace only source pixels. Placement, crop, mask, effects and identity
    /// remain editable, and a failed decode leaves the original layer intact.
    static func replacingImageContents(in layer: CoverLayer, data: Data) throws -> CoverLayer {
        guard layer.kind == .image, !layer.locked, layer.pixelsLocked != true else {
            throw WriterError.message("Select an unlocked image layer before replacing its artwork.")
        }
        let decoded = try CoverArtwork.decodedRaster(data)
        var replacement = layer
        replacement.imageData = decoded.data
        replacement.psdRasterPixelBasis = nil
        return replacement
    }
    static func configureAdjustment(_ layer: inout CoverLayer, kind: CoverAdjustmentKind, values: [String:Double] = [:]) { layer.adjustment=kind;layer.adjustmentValues=values }
    static func newPaintLayer(name:String,project:CoverProject,frame:CoverRect = CoverRect())->CoverLayer { var layer=CoverLayer(kind:.paint,name:name,frame:frame);layer.imageData=try? transparentImage(width:max(1,Int(project.canvasWidth*project.dpi)),height:max(1,Int(project.canvasHeight*project.dpi)));return layer }

    static func smartObjectLayerFromEmbeddedSource(
        data: Data,
        filename: String,
        project: CoverProject
    ) throws -> CoverLayer {
        guard !data.isEmpty,
              data.count
                <= CoverSmartObjectValidation
                    .maxSourceBytes,
              project.canvasWidth.isFinite,
              project.canvasHeight.isFinite,
              project.canvasWidth > 0,
              project.canvasHeight > 0,
              project.dpi.isFinite,
              project.dpi > 0
        else {
            throw WriterError.message(
                "The embedded Smart Object source is invalid or exceeds the supported size."
            )
        }

        let preview =
            try CoverArtwork
                .smartObjectPreview(
                    data:
                        data,
                    filename:
                        filename
                )

        let payload =
            CoverSmartObject(
                sourceKind:
                    preview.sourceKind,
                sourceData:
                    data,
                sourceFilename:
                    filename,
                intrinsicWidth:
                    preview.width,
                intrinsicHeight:
                    preview.height
            )

        guard CoverSmartObjectValidation
            .isValid(
                payload
            )
        else {
            throw WriterError.message(
                "The embedded Smart Object source metadata is invalid."
            )
        }

        let widthInches =
            Double(
                preview.width
            )
            / project.dpi

        let heightInches =
            Double(
                preview.height
            )
            / project.dpi

        guard widthInches.isFinite,
              heightInches.isFinite,
              widthInches > 0,
              heightInches > 0
        else {
            throw WriterError.message(
                "The embedded Smart Object has invalid dimensions."
            )
        }

        let canvasFit =
            min(
                project.canvasWidth
                    / widthInches,
                project.canvasHeight
                    / heightInches
            )

        let scale =
            min(
                1,
                canvasFit
            )

        let width =
            widthInches
            * scale
            / project.canvasWidth

        let height =
            heightInches
            * scale
            / project.canvasHeight

        var layer =
            CoverLayer(
                kind:
                    .smartObject,
                name:
                    filename,
                frame:
                    CoverRect(
                        x:
                            (
                                1
                                - width
                            )
                            / 2,
                        y:
                            (
                                1
                                - height
                            )
                            / 2,
                        width:
                            width,
                        height:
                            height
                    )
            )

        layer.imageData =
            preview.data

        layer.smartObject =
            payload

        layer.cropMode =
            .fit

        return layer
    }


    static func smartObjectLayerFromLinkedSource(
        url: URL,
        project: CoverProject
    ) throws -> CoverLayer {
        let snapshot =
            try CoverLinkedSmartObjectResource
                .snapshot(
                    from:
                        url
                )

        var layer =
            try smartObjectLayerFromEmbeddedSource(
                data:
                    snapshot.data,
                filename:
                    snapshot.url
                        .lastPathComponent,
                project:
                    project
            )

        guard var smartObject =
                layer.smartObject
        else {
            throw WriterError.message(
                "The linked Smart Object could not be created."
            )
        }

        smartObject.storageMode =
            .linked

        smartObject.linkedBookmarkData =
            snapshot.bookmarkData

        smartObject.linkedLastKnownModificationDate =
            snapshot.modificationDate

        smartObject.linkedLastKnownFileSize =
            snapshot.fileSize

        guard CoverSmartObjectValidation
            .isValid(
                smartObject
            )
        else {
            throw WriterError.message(
                "The linked Smart Object metadata is invalid."
            )
        }

        layer.smartObject =
            smartObject

        return layer
    }

    static func linkedSmartObjectStatus(
        in layer: CoverLayer
    ) -> CoverLinkedSmartObjectStatus? {
        guard layer.kind
                == .smartObject,
              let smartObject =
                layer.smartObject
        else {
            return nil
        }

        return CoverLinkedSmartObjectResource
            .status(
                of:
                    smartObject
            )
    }

    static func updatingLinkedSmartObjectContents(
        in layer: CoverLayer
    ) throws -> CoverLayer? {
        guard layer.kind
                == .smartObject,
              let smartObject =
                layer.smartObject,
              smartObject.storageMode
                == .linked
        else {
            return nil
        }

        let snapshot =
            try CoverLinkedSmartObjectResource
                .resolve(
                    smartObject
                )

        let filename =
            snapshot.url
                .lastPathComponent

        let preview =
            try CoverArtwork
                .smartObjectPreview(
                    data:
                        snapshot.data,
                    filename:
                        filename
                )

        var payload =
            smartObject

        payload.sourceKind =
            preview.sourceKind

        payload.sourceData =
            snapshot.data

        payload.sourceFilename =
            filename

        payload.intrinsicWidth =
            preview.width

        payload.intrinsicHeight =
            preview.height

        payload.storageMode =
            .linked

        payload.linkedBookmarkData =
            snapshot.bookmarkData

        payload.linkedLastKnownModificationDate =
            snapshot.modificationDate

        payload.linkedLastKnownFileSize =
            snapshot.fileSize

        guard CoverSmartObjectValidation
            .isValid(
                payload
            )
        else {
            throw WriterError.message(
                "The updated linked Smart Object metadata is invalid."
            )
        }

        var output =
            layer

        output.smartObject =
            payload

        output.imageData =
            preview.data

        return output
    }

    static func relinkingSmartObject(
        in layer: CoverLayer,
        to url: URL
    ) throws -> CoverLayer? {
        guard layer.kind
                == .smartObject,
              layer.smartObject?
                .storageMode
                == .linked
        else {
            return nil
        }

        let snapshot =
            try CoverLinkedSmartObjectResource
                .snapshot(
                    from:
                        url
                )

        let filename =
            snapshot.url
                .lastPathComponent

        let preview =
            try CoverArtwork
                .smartObjectPreview(
                    data:
                        snapshot.data,
                    filename:
                        filename
                )

        let payload =
            CoverSmartObject(
                sourceKind:
                    preview.sourceKind,
                sourceData:
                    snapshot.data,
                sourceFilename:
                    filename,
                intrinsicWidth:
                    preview.width,
                intrinsicHeight:
                    preview.height,
                storageMode:
                    .linked,
                linkedBookmarkData:
                    snapshot.bookmarkData,
                linkedLastKnownModificationDate:
                    snapshot.modificationDate,
                linkedLastKnownFileSize:
                    snapshot.fileSize
            )

        guard CoverSmartObjectValidation
            .isValid(
                payload
            )
        else {
            throw WriterError.message(
                "The replacement linked Smart Object metadata is invalid."
            )
        }

        var output =
            layer

        output.smartObject =
            payload

        output.imageData =
            preview.data

        return output
    }

    static func embeddingLinkedSmartObject(
        in layer: CoverLayer
    ) -> CoverLayer? {
        guard layer.kind
                == .smartObject,
              var smartObject =
                layer.smartObject,
              smartObject.storageMode
                == .linked,
              !smartObject.sourceData
                .isEmpty
        else {
            return nil
        }

        smartObject.storageMode =
            .embedded

        smartObject.linkedBookmarkData =
            nil

        smartObject.linkedLastKnownModificationDate =
            nil

        smartObject.linkedLastKnownFileSize =
            nil

        guard CoverSmartObjectValidation
            .isValid(
                smartObject
            )
        else {
            return nil
        }

        var output =
            layer

        output.smartObject =
            smartObject

        return output
    }

    static func replacingSmartObjectContents(
        in layer: CoverLayer,
        data: Data,
        filename: String
    ) throws -> CoverLayer? {
        guard layer.kind == .smartObject,
              layer.smartObject?.storageMode == .embedded,
              !data.isEmpty,
              data.count
                <= CoverSmartObjectValidation
                    .maxSourceBytes
        else {
            return nil
        }

        let preview =
            try CoverArtwork
                .smartObjectPreview(
                    data:
                        data,
                    filename:
                        filename
                )

        let payload =
            CoverSmartObject(
                sourceKind:
                    preview.sourceKind,
                sourceData:
                    data,
                sourceFilename:
                    filename,
                intrinsicWidth:
                    preview.width,
                intrinsicHeight:
                    preview.height
            )

        guard CoverSmartObjectValidation
            .isValid(
                payload
            )
        else {
            return nil
        }

        var output =
            layer

        output.smartObject =
            payload

        output.imageData =
            preview.data

        return output
    }

    static func regeneratingSmartObjectRenderCache(
        in layer: CoverLayer
    ) throws -> CoverLayer? {
        guard layer.kind == .smartObject,
              let smartObject =
                layer.smartObject,
              CoverSmartObjectValidation
                .isValid(
                    smartObject
                )
        else {
            return nil
        }

        let preview =
            try CoverArtwork
                .smartObjectPreview(
                    data:
                        smartObject
                            .sourceData,
                    filename:
                        smartObject
                            .sourceFilename
                        ?? (
                            smartObject.storageMode
                                == .linked
                            ? "Linked Object"
                            : "Embedded Object"
                        )
                )

        var output =
            layer

        var payload =
            smartObject

        payload.sourceKind =
            preview.sourceKind

        payload.intrinsicWidth =
            preview.width

        payload.intrinsicHeight =
            preview.height

        output.imageData =
            preview.data

        output.smartObject =
            payload

        return output
    }

    static func rasterizingSmartObject(
        _ layer: CoverLayer
    ) -> CoverLayer? {
        guard layer.kind == .smartObject,
              layer.smartObject != nil,
              layer.imageData != nil
        else {
            return nil
        }

        var output =
            layer

        output.kind =
            .image

        output.smartObject =
            nil

        return output
    }

    static func saveSelection(_ mask:Data,width:Int,height:Int,name:String,into project:inout CoverProject)->UUID? { guard mask.count==width*height,width>0,height>0 else{return nil};let item=CoverSavedSelection(id:UUID(),name:name,width:width,height:height,mask:mask);project.savedSelections=(project.savedSelections ?? [])+[item];return item.id }
    static func loadSelection(_ id:UUID,from project:CoverProject)->CoverSavedSelection? { project.savedSelections?.first{$0.id==id} }
    static func rectangleSelection(width: Int, height: Int, rect: CGRect) -> Data {
        makeMask(width: width, height: height) { x, y in rect.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) }
    }

    static func ellipseSelection(width:Int,height:Int,rect:CGRect,antialias:Bool=true)->Data{
        guard width>0,height>0,width<=20_000,height<=20_000 else{return Data()};let samples=antialias ? 4:1;var values=[UInt8](repeating:0,count:width*height)
        for y in 0..<height{for x in 0..<width{var hits=0;for sy in 0..<samples{for sx in 0..<samples{let p=CGPoint(x:Double(x)+(Double(sx)+0.5)/Double(samples),y:Double(y)+(Double(sy)+0.5)/Double(samples));if rect.width>0,rect.height>0, pow((p.x-rect.midX)/(rect.width/2),2)+pow((p.y-rect.midY)/(rect.height/2),2)<=1{hits += 1}}};values[y*width+x]=UInt8(hits*255/(samples*samples))}}
        return Data(values)
    }

    static func lassoSelection(width: Int, height: Int, points: [CGPoint],antialias:Bool=true) -> Data {
        guard points.count >= 3 else { return Data(repeating: 0, count: max(0, width * height)) }
        let path = CGMutablePath(); path.addLines(between: points); path.closeSubpath()
        guard antialias else{return makeMask(width:width,height:height){x,y in path.contains(CGPoint(x:Double(x)+0.5,y:Double(y)+0.5))}}
        guard width>0,height>0,width<=20_000,height<=20_000 else{return Data()};let samples=4;var values=[UInt8](repeating:0,count:width*height);for y in 0..<height{for x in 0..<width{var hits=0;for sy in 0..<samples{for sx in 0..<samples where path.contains(CGPoint(x:Double(x)+(Double(sx)+0.5)/Double(samples),y:Double(y)+(Double(sy)+0.5)/Double(samples))){hits += 1}};values[y*width+x]=UInt8(hits*255/(samples*samples))}};return Data(values)
    }

    static func combine(_ old: Data, _ new: Data, mode: CoverSelectionMode) -> Data {
        guard old.count == new.count else { return new }
        return Data(zip(old, new).map { a, b in
            switch mode { case .replace: b; case .add: max(a,b); case .subtract: a > b ? a-b : 0; case .intersect: min(a,b) }
        })
    }

    /// Combines a new selection with the active selection only when both target
    /// the same raster layer. Selection bytes are expressed in that layer's
    /// pixel coordinate space, so reusing bytes from another layer can distort
    /// selection geometry when the images have different sizes or frames.
    static func applyingSelection(
        _ proposed: Data,
        toLayer layerID: UUID,
        existing: Data?,
        existingLayerID: UUID?,
        mode: CoverSelectionMode
    ) -> Data {
        guard let existing,
              existingLayerID == layerID,
              existing.count == proposed.count
        else { return proposed }
        return combine(existing, proposed, mode: mode)
    }

    /// RGB Euclidean distance (0...441.7) across all three color channels; alpha is ignored.
    /// This makes wand tolerance deterministic and monotonic as its threshold increases.
    static func colorDistance(_ lhs:(UInt8,UInt8,UInt8),_ rhs:(UInt8,UInt8,UInt8))->Double {
        hypot(hypot(Double(lhs.0)-Double(rhs.0),Double(lhs.1)-Double(rhs.1)),Double(lhs.2)-Double(rhs.2))
    }

    static func transformSelection(_ mask:Data,width:Int,height:Int,translation:CGPoint = .zero,scale:CGSize = CGSize(width:1,height:1),rotation:Double = 0)->Data {
        guard width>0,height>0,width<=20_000,height<=20_000,mask.count==width*height,scale.width.isFinite,scale.height.isFinite,scale.width>0,scale.height>0,rotation.isFinite else{return mask}
        let radians = -rotation * .pi / 180, c=cos(radians), s=sin(radians), cx=Double(width)/2, cy=Double(height)/2
        let src=[UInt8](mask); var out=[UInt8](repeating:0,count:src.count)
        for y in 0..<height { for x in 0..<width {
            let px=Double(x)+0.5-translation.x-cx, py=Double(y)+0.5-translation.y-cy
            let rx=px*c-py*s, ry=px*s+py*c
            let sx=rx/scale.width+cx-0.5, sy=ry/scale.height+cy-0.5
            let x0=Int(floor(sx)), y0=Int(floor(sy)), fx=sx-Double(x0), fy=sy-Double(y0)
            func sample(_ xx:Int,_ yy:Int)->Double { xx>=0 && yy>=0 && xx<width && yy<height ? Double(src[yy*width+xx]) : 0 }
            let top=sample(x0,y0)*(1-fx)+sample(x0+1,y0)*fx, bottom=sample(x0,y0+1)*(1-fx)+sample(x0+1,y0+1)*fx
            out[y*width+x]=UInt8(max(0,min(255,(top*(1-fy)+bottom*fy).rounded())))
        }}
        return Data(out)
    }

    /// Spatially local edge snapping for magnetic lasso. Search is bounded by radius around
    /// the predicted point and favors a strong gradient aligned with the incoming direction.
    static func magneticLassoPath(imageData:Data,points:[CGPoint],radius:Int,contrast:Double,frequency:Int)->[CGPoint] {
        guard points.count>1,let pixels=try? PixelBuffer(data:imageData) else{return points}
        let r=max(1,min(64,radius)), sensitivity=max(0,min(1,contrast)), spacing=max(1,frequency)
        func lum(_ x:Int,_ y:Int)->Double { let p=pixels.color(x:max(0,min(pixels.width-1,x)),y:max(0,min(pixels.height-1,y)));return 0.2126*Double(p.r)+0.7152*Double(p.g)+0.0722*Double(p.b) }
        var anchors=[points[0]],last=points[0],travelled=0.0
        for target in points.dropFirst() {
            let dx=target.x-last.x,dy=target.y-last.y,d=hypot(dx,dy);if d<0.01{continue}
            let steps=max(1,Int(ceil(d/Double(max(1,r/2)))))
            for step in 1...steps {
                let predicted=CGPoint(x:last.x+dx*Double(step)/Double(steps),y:last.y+dy*Double(step)/Double(steps)), px=Int(predicted.x.rounded()),py=Int(predicted.y.rounded())
                var best=predicted,bestScore = -Double.infinity
                let minY=max(1,py-r),maxY=min(pixels.height-2,py+r),minX=max(1,px-r),maxX=min(pixels.width-2,px+r)
                if minY>maxY || minX>maxX {last=predicted;continue}
                for yy in minY...maxY { for xx in minX...maxX {
                    let gx=lum(xx+1,yy)-lum(xx-1,yy),gy=lum(xx,yy+1)-lum(xx,yy-1),strength=hypot(gx,gy),align=abs((gx*dx+gy*dy)/(max(0.001,strength*d))),distance=hypot(Double(xx)-predicted.x,Double(yy)-predicted.y)
                    let score=strength*(0.55+0.45*align)-distance*(8+24*(1-sensitivity))
                    if score>bestScore {bestScore=score;best=CGPoint(x:Double(xx),y:Double(yy))}
                }}
                last=best;travelled += d/Double(steps)
                if travelled>=Double(spacing){anchors.append(best);travelled=0}
            }
        }
        if anchors.last != last {anchors.append(last)}
        return anchors
    }

    static func encodedMask(_ mask:Data,width:Int,height:Int)->Data?{guard width>0,height>0,mask.count==width*height,var pixels=try? PixelBuffer(width:width,height:height) else{return nil};for i in 0..<mask.count{let v=mask[i];pixels.bytes[i*4]=v;pixels.bytes[i*4+1]=v;pixels.bytes[i*4+2]=v;pixels.bytes[i*4+3]=255};return pixels.pngData()}
    static func decodedMask(_ data:Data,width:Int,height:Int)->Data?{guard let pixels=try? PixelBuffer(data:data),pixels.width==width,pixels.height==height else{return nil};return Data((0..<width*height).map{index in let i=index*4;return UInt8((UInt16(pixels.bytes[i])+UInt16(pixels.bytes[i+1])+UInt16(pixels.bytes[i+2]))/3)})}
    static func channelPreview(
        imageData: Data,
        channel: CoverChannelPreviewKind
    ) throws -> Data {
        var pixels =
            try PixelBuffer(
                data:imageData
            )

        guard channel != .composite else {
            return pixels.pngData()
        }

        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let source =
                    pixels.color(
                        x:x,
                        y:y
                    )

                let value: UInt8

                switch channel {
                case .composite:
                    value = 0
                case .red:
                    value = source.r
                case .green:
                    value = source.g
                case .blue:
                    value = source.b
                case .alpha:
                    value = source.a
                }

                pixels.set(
                    x:x,
                    y:y,
                    rgba:(
                        value,
                        value,
                        value,
                        255
                    )
                )
            }
        }

        return pixels.pngData()
    }

    static func selectionPreview(_ mask:Data,width:Int,height:Int)->Data?{guard width>0,height>0,mask.count==width*height,var pixels=try? PixelBuffer(width:width,height:height) else{return nil};for i in 0..<mask.count{let alpha=UInt8(Double(mask[i])*0.38);pixels.bytes[i*4]=alpha;pixels.bytes[i*4+1]=0;pixels.bytes[i*4+2]=0;pixels.bytes[i*4+3]=alpha};return pixels.pngData()}

    static func selectSubject(imageData:Data)throws->(width:Int,height:Int,mask:Data){
        guard let rep=NSBitmapImageRep(data:imageData),let cg=rep.cgImage else{throw WriterError.message("Select Subject needs a readable raster image layer.")}
        // Transparent artwork already describes its foreground precisely.
        // Preserve its antialiased alpha edge instead of asking Vision to
        // classify empty transparent pixels as a foreground instance.
        let sourcePixels = try PixelBuffer(data: imageData)
        var hasTransparentPixels = false
        var alpha = [UInt8](repeating: 0, count: sourcePixels.width * sourcePixels.height)
        for index in alpha.indices {
            let value = sourcePixels.bytes[index * 4 + 3]
            alpha[index] = value
            if value < 255 { hasTransparentPixels = true }
        }
        if hasTransparentPixels {
            return (sourcePixels.width, sourcePixels.height, Data(alpha))
        }
        let request=VNGenerateForegroundInstanceMaskRequest();let handler=VNImageRequestHandler(cgImage:cg,options:[:]);try handler.perform([request])
        guard let result=request.results?.first else{throw WriterError.message("Vision could not identify a foreground subject in this image.")}
        let pixelBuffer=try result.generateScaledMaskForImage(forInstances:result.allInstances,from:handler)
        CVPixelBufferLockBaseAddress(pixelBuffer,.readOnly);defer{CVPixelBufferUnlockBaseAddress(pixelBuffer,.readOnly)}
        let width=CVPixelBufferGetWidth(pixelBuffer),height=CVPixelBufferGetHeight(pixelBuffer),stride=CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let address=CVPixelBufferGetBaseAddress(pixelBuffer) else{throw WriterError.message("Vision returned an empty subject mask.")}
        let bytes=address.assumingMemoryBound(to:UInt8.self);var mask=[UInt8](repeating:0,count:width*height)
        for y in 0..<height{for x in 0..<width{mask[y*width+x]=bytes[y*stride+x]}}
        return(width,height,Data(mask))
    }

    static func inverted(_ mask: Data) -> Data { Data(mask.map { 255 - $0 }) }
    static func offsetMask(_ mask:Data,width:Int,height:Int,dx:Int,dy:Int)->Data{guard width>0,height>0,mask.count==width*height else{return mask};var out=[UInt8](repeating:0,count:mask.count);for y in 0..<height{for x in 0..<width{let sx=x-dx,sy=y-dy;if sx>=0,sy>=0,sx<width,sy<height{out[y*width+x]=mask[sy*width+sx]}}};return Data(out)}
    static func refineMask(_ mask:Data,width:Int,height:Int,featherRadius:Int=0,morphology:Int=0,density:Double=1)->Data{var result=mask;if morphology>0{result=expandSelection(result,width:width,height:height,radius:morphology)}else if morphology<0{result=contractSelection(result,width:width,height:height,radius:-morphology)};if featherRadius>0{result=feather(result,width:width,height:height,radius:featherRadius)};let d=max(0,min(1,density));return Data(result.map{UInt8((Double($0)*d).rounded())})}

    static func colorSelection(imageData: Data, sample: CGPoint, tolerance: Double, contiguous: Bool = true,antialias:Bool=false) throws -> (width: Int, height: Int, mask: Data) {
        let pixels = try PixelBuffer(data: imageData)
        let sx = min(pixels.width-1, max(0, Int(sample.x))), sy = min(pixels.height-1, max(0, Int(sample.y)))
        let target = pixels.color(x: sx, y: sy)
        let limit = max(0, min(1, tolerance)) * sqrt(3*255.0*255.0)
        func distance(_ x:Int,_ y:Int)->Double { let c=pixels.color(x:x,y:y);return colorDistance((c.r,c.g,c.b),(target.r,target.g,target.b)) }
        func matches(_ x: Int, _ y: Int) -> Bool { distance(x,y) <= limit }
        func coverage(_ x:Int,_ y:Int)->UInt8{let delta=distance(x,y);guard delta<=limit else{return 0};guard antialias,limit>0 else{return 255};return UInt8(max(1,min(255,(255*(1-delta/limit)).rounded())))}
        var result = [UInt8](repeating: 0, count: pixels.width * pixels.height)
        if contiguous {
            var queue = [sy * pixels.width + sx], cursor = 0
            while cursor < queue.count {
                let index = queue[cursor]; cursor += 1
                if result[index] != 0 { continue }
                let x=index % pixels.width, y=index / pixels.width
                guard matches(x,y) else { continue }
                result[index] = coverage(x,y)
                if x > 0 { queue.append(index-1) }; if x+1 < pixels.width { queue.append(index+1) }
                if y > 0 { queue.append(index-pixels.width) }; if y+1 < pixels.height { queue.append(index+pixels.width) }
            }
        } else {
            for y in 0..<pixels.height { for x in 0..<pixels.width where matches(x,y) { result[y*pixels.width+x]=coverage(x,y) } }
        }
        return (pixels.width,pixels.height,Data(result))
    }

    /// Separable running sums preserve the original clipped box average exactly,
    /// including fractional coverage and a single integer rounding at the end.
    static func feather(_ mask: Data, width: Int, height: Int, radius: Int) -> Data {
        guard validSelection(mask, width: width, height: height), radius > 0 else { return mask }
        let r = min(radius, max(width, height)), src = [UInt8](mask)
        var horizontal = [Int](repeating: 0, count: src.count)
        for y in 0..<height {
            let base = y * width
            var sum = 0
            for x in 0..<min(width, r + 1) { sum += Int(src[base + x]) }
            for x in 0..<width {
                horizontal[base + x] = sum
                if x >= r { sum -= Int(src[base + x - r]) }
                if x + r + 1 < width { sum += Int(src[base + x + r + 1]) }
            }
        }
        var output = [UInt8](repeating: 0, count: src.count)
        for x in 0..<width {
            let columns = min(width - 1, x + r) - max(0, x - r) + 1
            var sum = 0
            for y in 0..<min(height, r + 1) { sum += horizontal[y * width + x] }
            for y in 0..<height {
                let rows = min(height - 1, y + r) - max(0, y - r) + 1
                output[y * width + x] = UInt8(sum / (columns * rows))
                if y >= r { sum -= horizontal[(y - r) * width + x] }
                if y + r + 1 < height { sum += horizontal[(y + r + 1) * width + x] }
            }
        }
        return Data(output)
    }

    private static func validSelection(_ mask: Data, width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && width <= 20_000 && height <= 20_000
            && mask.count == width * height
    }

    static func expandSelection(_ mask:Data,width:Int,height:Int,radius:Int)->Data{morph(mask,width:width,height:height,radius:radius,dilate:true)}
    static func contractSelection(_ mask:Data,width:Int,height:Int,radius:Int)->Data{morph(mask,width:width,height:height,radius:radius,dilate:false)}
    static func smoothSelection(_ mask:Data,width:Int,height:Int,radius:Int)->Data{guard radius>0,width>0,height>0,mask.count==width*height else{return mask};let softened=feather(mask,width:width,height:height,radius:radius);return Data(zip(mask,softened).map{a,b in UInt8((Double(a)*0.5+Double(b)*0.5).rounded())})}
    static func borderSelection(_ mask:Data,width:Int,height:Int,radius:Int)->Data{guard radius>0,mask.count==width*height else{return mask};let inner=contractSelection(mask,width:width,height:height,radius:radius);return Data(zip(mask,inner).map{a,b in a>b ? a-b:0})}
    /// A monotonic deque computes square dilation/erosion in two linear passes.
    /// The window clips at the canvas edge, matching existing selection behavior.
    private static func morph(_ mask: Data, width: Int, height: Int, radius: Int, dilate: Bool) -> Data {
        guard validSelection(mask, width: width, height: height), radius > 0 else { return mask }
        let r = min(radius, max(width, height)), src = [UInt8](mask)
        var horizontal = src, output = src
        var queue = [Int](repeating: 0, count: max(width, height))
        func pass(_ source: [UInt8], into destination: inout [UInt8], length: Int,
                  lines: Int, stride: Int, lineStride: Int) {
            for line in 0..<lines {
                let base = line * lineStride
                var head = 0, tail = 0, next = 0
                for position in 0..<length {
                    let lower = max(0, position - r), upper = min(length - 1, position + r)
                    while head < tail && queue[head] < lower { head += 1 }
                    while next <= upper {
                        let value = source[base + next * stride]
                        while head < tail {
                            let previous = source[base + queue[tail - 1] * stride]
                            if dilate ? previous > value : previous < value { break }
                            tail -= 1
                        }
                        queue[tail] = next; tail += 1; next += 1
                    }
                    destination[base + position * stride] = source[base + queue[head] * stride]
                }
            }
        }
        pass(src, into: &horizontal, length: width, lines: height, stride: 1, lineStride: width)
        pass(horizontal, into: &output, length: height, lines: width, stride: width, lineStride: 1)
        return Data(output)
    }


    static func filledImage(width: Int, height: Int, color: NSColor, selection: Data? = nil) throws -> Data {
        var pixels = try PixelBuffer(width:width,height:height)
        let rgba=color.usingColorSpace(.deviceRGB) ?? .black
        for y in 0..<height { for x in 0..<width {
            let alpha=selection.map { $0[y*width+x] } ?? 255
            let a=Double(alpha)/255
            pixels.set(x:x,y:y,rgba:(UInt8((rgba.redComponent*255*a).rounded()),UInt8((rgba.greenComponent*255*a).rounded()),UInt8((rgba.blueComponent*255*a).rounded()),alpha))
        } }
        return pixels.pngData()
    }

    static func transparentImage(width:Int,height:Int)throws->Data{try PixelBuffer(width:width,height:height).pngData()}

    static func canPencilPaint(
        _ layer:CoverLayer,
        quickMask:Bool=false,
        maskSelected:Bool=false
    )->Bool {
        guard !layer.locked else {
            return false
        }

        if quickMask || maskSelected {
            return true
        }

        guard layer.pixelsLocked != true else {
            return false
        }

        return layer.kind == .image
            || layer.kind == .paint
    }

    private static func interpolatedStrokePoints(
        _ points:[CGPoint],
        diameter:Double
    )->[CGPoint] {
        guard !points.isEmpty,
              diameter.isFinite,
              diameter > 0
        else {
            return points
        }

        let finitePoints =
            points.filter {
                $0.x.isFinite
                    && $0.y.isFinite
            }

        guard let first =
                finitePoints.first
        else {
            return []
        }

        let spacing =
            max(
                0.5,
                diameter * 0.25
            )

        let maximumSamples =
            250_000

        var output:[CGPoint] = [
            first
        ]

        for destination in finitePoints.dropFirst() {
            guard output.count
                    < maximumSamples
            else {
                break
            }

            guard let source =
                    output.last
            else {
                output.append(
                    destination
                )
                continue
            }

            let dx =
                destination.x
                - source.x

            let dy =
                destination.y
                - source.y

            let distance =
                hypot(
                    dx,
                    dy
                )

            guard distance.isFinite,
                  distance > 0,
                  distance <= 100_000
            else {
                if distance == 0 {
                    continue
                }

                output.append(
                    destination
                )
                continue
            }

            let rawSteps =
                ceil(
                    distance
                    / spacing
                )

            let steps =
                max(
                    1,
                    min(
                        100_000,
                        Int(rawSteps)
                    )
                )

            for step in 1...steps {
                guard output.count
                        < maximumSamples
                else {
                    break
                }

                let t =
                    Double(step)
                    / Double(steps)

                output.append(
                    CGPoint(
                        x:
                            source.x
                            + dx * t,
                        y:
                            source.y
                            + dy * t
                    )
                )
            }
        }

        return output
    }

    static func pencil(
        imageData:Data,
        points:[CGPoint],
        color:NSColor,
        diameter:Double,
        opacity:Double=1,
        selection:Data?=nil,
        flow:Double=1
    )throws->Data {
        try paint(
            imageData:imageData,
            points:points,
            color:color,
            diameter:diameter,
            opacity:opacity,
            erase:false,
            selection:selection,
            hardness:1,
            flow:flow
        )
    }

    static func pencilMask(
        _ mask:Data,
        width:Int,
        height:Int,
        points:[CGPoint],
        diameter:Double,
        value:UInt8,
        opacity:Double=1,
        flow:Double=1,
        selection:Data?=nil
    )throws->Data {
        try paintMask(
            mask,
            width:width,
            height:height,
            points:points,
            diameter:diameter,
            value:value,
            hardness:1,
            opacity:opacity,
            flow:flow,
            selection:selection
        )
    }

    static func maskValue(for color: NSColor) -> UInt8 {
        let rgb = color.usingColorSpace(.deviceRGB) ?? .black
        let luminance = 0.2126 * rgb.redComponent
            + 0.7152 * rgb.greenComponent
            + 0.0722 * rgb.blueComponent
        return UInt8(max(0, min(255, (luminance * 255).rounded())))
    }

    /// Applies a black/white linear or radial gradient to a grayscale raster mask.
    /// Opacity controls how strongly the gradient replaces the existing mask;
    /// an active selection limits the affected pixels using its antialiased coverage.
    static func gradientMask(
        _ mask: Data,
        width: Int,
        height: Int,
        start: CGPoint,
        end: CGPoint,
        radial: Bool = false,
        reversed: Bool = false,
        opacity: Double = 1,
        selection: Data? = nil
    ) -> Data {
        guard validSelection(mask, width: width, height: height),
              start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite,
              opacity.isFinite, selection == nil || selection?.count == mask.count
        else { return mask }

        let amount = max(0, min(1, opacity))
        guard amount > 0 else { return mask }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        let radius = sqrt(lengthSquared)
        guard lengthSquared > 0, !radial || radius > 0 else { return mask }

        var result = [UInt8](mask)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let coverage = Double(selection?[index] ?? 255) / 255
                let influence = amount * coverage
                guard influence > 0 else { continue }
                let px = Double(x) - start.x
                let py = Double(y) - start.y
                let position: Double
                if radial {
                    position = sqrt(px * px + py * py) / radius
                } else if lengthSquared > 0 {
                    position = (px * dx + py * dy) / lengthSquared
                } else {
                    position = 0
                }
                let t = max(0, min(1, reversed ? 1 - position : position))
                let target = t * 255
                result[index] = UInt8((Double(mask[index]) * (1 - influence) + target * influence).rounded())
            }
        }
        return Data(result)
    }

    static func maskInspectionPreview(_ mask: Data, width: Int, height: Int, overlay: Bool) -> Data? {
        guard width > 0, height > 0, mask.count == width * height,
              var pixels = try? PixelBuffer(width: width, height: height)
        else { return nil }
        for index in mask.indices {
            let value = mask[index]
            if overlay {
                // Show concealed areas as a translucent red rubylith.
                let alpha = UInt8((Double(255 - value) * 0.58).rounded())
                pixels.bytes[index * 4] = 255
                pixels.bytes[index * 4 + 1] = 24
                pixels.bytes[index * 4 + 2] = 32
                pixels.bytes[index * 4 + 3] = alpha
            } else {
                pixels.bytes[index * 4] = value
                pixels.bytes[index * 4 + 1] = value
                pixels.bytes[index * 4 + 2] = value
                pixels.bytes[index * 4 + 3] = 255
            }
        }
        return pixels.pngData()
    }

    /// Whether the red active-selection fill should be composited over the canvas.
    /// Mask inspection already communicates mask coverage; an additional selection
    /// tint obscures grayscale values and makes the view appear chromatic.
    static func maskInspectionSelectionTintEnabled(maskSelected: Bool, inspectionModeActive: Bool) -> Bool {
        !(maskSelected && inspectionModeActive)
    }

    static func paint(imageData: Data, points: [CGPoint], color: NSColor, diameter: Double, opacity: Double = 1, erase: Bool = false, selection: Data? = nil, hardness:Double=1, flow:Double=1) throws -> Data {
        var pixels=try PixelBuffer(data:imageData); guard !points.isEmpty, diameter.isFinite, diameter > 0, diameter <= Double(max(pixels.width,pixels.height))*2, selection == nil || selection?.count == pixels.width*pixels.height else { return imageData }
        let radius=max(0.5,diameter/2), rgb=color.usingColorSpace(.deviceRGB) ?? .black,hardEdge=radius*max(0,min(1,hardness)),flowAmount=max(0,min(1,flow))
        for point in interpolatedStrokePoints(points, diameter: diameter) {
            guard point.x.isFinite,point.y.isFinite,abs(point.x)<Double(Int.max/4),abs(point.y)<Double(Int.max/4) else{continue}
            let minX=max(0,Int(point.x-radius)),maxX=min(pixels.width-1,Int(point.x+radius)); let minY=max(0,Int(point.y-radius)),maxY=min(pixels.height-1,Int(point.y+radius))
            guard minX <= maxX, minY <= maxY else { continue }
            for y in minY...maxY { for x in minX...maxX where hypot(Double(x)-point.x,Double(y)-point.y) <= radius {
                let distance=hypot(Double(x)-point.x,Double(y)-point.y);let edgeCoverage=distance<=hardEdge ? 1:max(0,(radius-distance)/max(0.0001,radius-hardEdge))
                let idx=y*pixels.width+x, coverage=Double(selection?[idx] ?? 255)/255 * max(0,min(1,opacity))*flowAmount*edgeCoverage
                let old=pixels.color(x:x,y:y)
                if erase { pixels.set(x:x,y:y,rgba:(old.r,old.g,old.b,UInt8(Double(old.a)*(1-coverage)))) }
                else {
                    let a=coverage, oa=Double(old.a)/255, outA=a+oa*(1-a)
                    guard outA > 0 else { continue }
                    func channel(_ src:Double,_ dst:UInt8)->UInt8 { UInt8(max(0,min(255,((src*a+Double(dst)/255*oa*(1-a))/outA*255).rounded()))) }
                    pixels.set(x:x,y:y,rgba:(channel(rgb.redComponent,old.r),channel(rgb.greenComponent,old.g),channel(rgb.blueComponent,old.b),UInt8(outA*255)))
                }
            } }
        }
        return pixels.pngData()
    }

    static func paintMask(
        _ mask: Data,
        width: Int,
        height: Int,
        points: [CGPoint],
        diameter: Double,
        value: UInt8,
        hardness: Double = 1,
        opacity: Double = 1,
        flow: Double = 1,
        selection: Data? = nil
    ) throws -> Data {
        guard width > 0,
              height > 0,
              mask.count == width * height,
              selection == nil || selection?.count == width * height,
              diameter.isFinite,
              diameter > 0
        else { return mask }

        let radius = diameter / 2
        let hardEdge = radius * max(0, min(1, hardness))
        let strength = max(0, min(1, opacity)) * max(0, min(1, flow))
        var values = [UInt8](mask)

        for point in interpolatedStrokePoints(points, diameter: diameter)
        where point.x.isFinite && point.y.isFinite {
            guard abs(point.x) < Double(Int.max / 4),
                  abs(point.y) < Double(Int.max / 4)
            else { continue }

            let minX = max(0, Int(point.x - radius))
            let maxX = min(width - 1, Int(point.x + radius))
            let minY = max(0, Int(point.y - radius))
            let maxY = min(height - 1, Int(point.y + radius))
            guard minX <= maxX, minY <= maxY else { continue }

            for y in minY...maxY {
                for x in minX...maxX {
                    let distance = hypot(Double(x) - point.x, Double(y) - point.y)
                    guard distance <= radius else { continue }

                    let edge = distance <= hardEdge
                        ? 1
                        : max(0, (radius - distance) / max(0.0001, radius - hardEdge))
                    let index = y * width + x
                    let selectionCoverage = Double(selection?[index] ?? 255) / 255
                    let amount = strength * edge * selectionCoverage
                    guard amount > 0 else { continue }

                    values[index] = UInt8(max(0, min(255,
                        (Double(values[index]) * (1 - amount) + Double(value) * amount).rounded()
                    )))
                }
            }
        }

        return Data(values)
    }

    static func clone(
        imageData: Data,
        source: CGPoint,
        destinationPoints: [CGPoint],
        diameter: Double,
        opacity: Double = 1,
        destinationOrigin: CGPoint? = nil,
        hardness: Double = 1,
        flow: Double = 1,
        selection: Data? = nil
    ) throws -> Data {
        var pixels = try PixelBuffer(data:imageData)
        guard diameter.isFinite,
              diameter > 0,
              diameter <= Double(max(pixels.width,pixels.height))*2,
              selection == nil || selection?.count == pixels.width*pixels.height
        else { return imageData }

        let original = pixels.bytes
        let radius = max(0.5,diameter/2)
        let hardnessEdge = radius * max(0,min(1,hardness))
        let strength = max(0,min(1,opacity)) * max(0,min(1,flow))
        let sourceOffset = destinationOrigin.map {
            CGPoint(x:source.x - $0.x,y:source.y - $0.y)
        }

        for point in destinationPoints where point.x.isFinite && point.y.isFinite {
            let centerX = Int(point.x)
            let centerY = Int(point.y)
            let minX = max(0,centerX-Int(radius))
            let maxX = min(pixels.width-1,centerX+Int(radius))
            let minY = max(0,centerY-Int(radius))
            let maxY = min(pixels.height-1,centerY+Int(radius))
            guard minX <= maxX, minY <= maxY else { continue }

            for y in minY...maxY {
                for x in minX...maxX {
                    let distance = hypot(Double(x-centerX),Double(y-centerY))
                    guard distance <= radius else { continue }
                    let edgeCoverage = distance <= hardnessEdge
                        ? 1
                        : max(0,(radius-distance)/max(0.0001,radius-hardnessEdge))
                    let maskIndex = y*pixels.width+x
                    let maskCoverage = Double(selection?[maskIndex] ?? 255)/255
                    let amount = strength * edgeCoverage * maskCoverage
                    guard amount > 0 else { continue }

                    let sampleX: Int
                    let sampleY: Int
                    if let sourceOffset {
                        sampleX = x + Int((sourceOffset.x).rounded())
                        sampleY = y + Int((sourceOffset.y).rounded())
                    } else {
                        sampleX = x-centerX+Int(source.x)
                        sampleY = y-centerY+Int(source.y)
                    }
                    guard sampleX >= 0, sampleY >= 0,
                          sampleX < pixels.width, sampleY < pixels.height
                    else { continue }

                    let sourceIndex = (sampleY*pixels.width+sampleX)*4
                    let destinationIndex = maskIndex*4
                    for channel in 0..<4 {
                        let old = Double(pixels.bytes[destinationIndex+channel])
                        let sampled = Double(original[sourceIndex+channel])
                        pixels.bytes[destinationIndex+channel] = UInt8(
                            (old*(1-amount)+sampled*amount).rounded()
                        )
                    }
                }
            }
        }
        return pixels.pngData()
    }

    static func heal(imageData: Data, center: CGPoint, diameter: Double) throws -> Data {
        var pixels=try PixelBuffer(data:imageData);guard diameter.isFinite,diameter>0,diameter<=Double(max(pixels.width,pixels.height))*2 else{return imageData};let radius=max(1,Int(diameter/2)), cx=Int(center.x), cy=Int(center.y)
        guard cx>=radius,cy>=radius,cx+radius<pixels.width,cy+radius<pixels.height else{return imageData}
        let src=pixels.bytes
        for y in max(0,cy-radius)...min(pixels.height-1,cy+radius) { for x in max(0,cx-radius)...min(pixels.width-1,cx+radius) where hypot(Double(x-cx),Double(y-cy)) <= Double(radius) {
            let sx=(x-cx)+cx-radius-2, sy=(y-cy)+cy-radius-2
            if sx>=0,sy>=0,sx<pixels.width,sy<pixels.height { let si=(sy*pixels.width+sx)*4,di=(y*pixels.width+x)*4; for c in 0..<4 { pixels.bytes[di+c]=src[si+c] } }
        } }
        return pixels.pngData()
    }

    static func applyMask(_ imageData: Data, mask: Data, width: Int, height: Int) throws -> Data {
        var pixels=try PixelBuffer(data:imageData); guard pixels.width==width,pixels.height==height,mask.count==width*height else{throw WriterError.message("The mask dimensions do not match the image layer.")}
        for i in 0..<mask.count { let factor=Double(mask[i])/255;for c in 0..<4{pixels.bytes[i*4+c]=UInt8((Double(pixels.bytes[i*4+c])*factor).rounded())} }
        return pixels.pngData()
    }
    static func applyRasterMask(_ imageData:Data,maskImageData:Data,density:Double=1,offsetX:Double=0,offsetY:Double=0)throws->Data{var pixels=try PixelBuffer(data:imageData);let mask=try PixelBuffer(data:maskImageData);let amount=max(0,min(1,density));guard mask.width>0,mask.height>0 else{return imageData};for y in 0..<pixels.height{for x in 0..<pixels.width{let sx=Int((Double(x)/Double(pixels.width)-offsetX)*Double(mask.width)),sy=Int((Double(y)/Double(pixels.height)-offsetY)*Double(mask.height));let sample=sx>=0 && sy>=0 && sx<mask.width && sy<mask.height ? mask.color(x:sx,y:sy):(r:0,g:0,b:0,a:0);let coverage=(Double(sample.r)+Double(sample.g)+Double(sample.b))/765*Double(sample.a)/255*amount;let i=(y*pixels.width+x)*4;for c in 0..<4{pixels.bytes[i+c]=UInt8((Double(pixels.bytes[i+c])*coverage).rounded())}}};return pixels.pngData()}

    /// Sample the visible composite, including placement, masks, text, and shapes.
    /// Normalized coordinates use the canvas's top-left origin.
    static func sampledCanvasColor(project: CoverProject, point: CGPoint) throws -> NSColor {
        guard point.x.isFinite, point.y.isFinite, (0...1).contains(point.x), (0...1).contains(point.y) else {
            throw WriterError.message("Choose a point inside the cover canvas.")
        }
        let scale = min(project.dpi, 2048 / max(project.canvasWidth, project.canvasHeight))
        let image = try CoverArtwork.render(project, includeTemplate: true, scale: scale)
        guard let raster = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw WriterError.message("The cover could not be sampled.")
        }
        let bitmap = NSBitmapImageRep(cgImage: raster)
        let x = min(bitmap.pixelsWide-1, Int(point.x*Double(bitmap.pixelsWide)))
        let y = min(bitmap.pixelsHigh-1, Int(point.y*Double(bitmap.pixelsHigh)))
        guard let color = bitmap.colorAt(x: x, y: y) else {
            throw WriterError.message("The cover color could not be read.")
        }
        // The canvas raster is explicitly sRGB. AppKit colorAt returns a
        // device-RGB color for these bytes; converting that again shifts hues.
        return NSColor(srgbRed: color.redComponent, green: color.greenComponent,
                       blue: color.blueComponent, alpha: color.alphaComponent)
    }

    static func sampledColor(imageData:Data,at point:CGPoint)throws->NSColor{let pixels=try PixelBuffer(data:imageData);let x=max(0,min(pixels.width-1,Int(point.x))),y=max(0,min(pixels.height-1,Int(point.y))),c=pixels.color(x:x,y:y);return NSColor(srgbRed:CGFloat(c.r)/255,green:CGFloat(c.g)/255,blue:CGFloat(c.b)/255,alpha:CGFloat(c.a)/255)}


    static func blurSharpen(
        imageData: Data,
        at points: [CGPoint],
        diameter: Double,
        strength: Double,
        sharpen: Bool,
        selection: Data? = nil,
        hardness: Double = 1,
        flow: Double = 1
    ) throws -> Data {
        var pixels =
            try PixelBuffer(
                data:imageData
            )

        guard !points.isEmpty,
              diameter.isFinite,
              diameter > 0,
              diameter <= Double(
                max(
                    pixels.width,
                    pixels.height
                )
              ),
              strength.isFinite,
              hardness.isFinite,
              flow.isFinite,
              selection == nil
                || selection?.count
                    == pixels.width
                    * pixels.height
        else {
            return imageData
        }

        let amount =
            max(
                0,
                min(
                    1,
                    strength
                )
            )

        guard amount > 0 else {
            return imageData
        }

        let radius =
            max(
                0.5,
                diameter
                / 2
            )

        let hardEdge =
            radius
            * max(
                0,
                min(
                    1,
                    hardness
                )
            )

        let flowAmount =
            max(
                0,
                min(
                    1,
                    flow
                )
            )

        guard flowAmount > 0 else {
            return imageData
        }

        let sampleRadius =
            max(
                1,
                min(
                    8,
                    Int(
                        (
                            radius
                            * 0.18
                        )
                        .rounded()
                    )
                )
            )

        for point in points {
            guard point.x.isFinite,
                  point.y.isFinite,
                  abs(point.x) < Double(Int.max / 4),
                  abs(point.y) < Double(Int.max / 4)
            else {
                continue
            }

            let minX =
                max(
                    0,
                    Int(
                        point.x
                        - radius
                    )
                )

            let maxX =
                min(
                    pixels.width
                    - 1,
                    Int(
                        point.x
                        + radius
                    )
                )

            let minY =
                max(
                    0,
                    Int(
                        point.y
                        - radius
                    )
                )

            let maxY =
                min(
                    pixels.height
                    - 1,
                    Int(
                        point.y
                        + radius
                    )
                )

            guard minX <= maxX,
                  minY <= maxY
            else {
                continue
            }

            let source =
                pixels.bytes

            for y in minY...maxY {
                for x in minX...maxX {
                    let distance =
                        hypot(
                            Double(x)
                            - point.x,
                            Double(y)
                            - point.y
                        )

                    guard distance <= radius else {
                        continue
                    }

                    let edgeCoverage: Double

                    if distance <= hardEdge {
                        edgeCoverage = 1
                    } else {
                        edgeCoverage =
                            max(
                                0,
                                (
                                    radius
                                    - distance
                                )
                                / max(
                                    0.0001,
                                    radius
                                    - hardEdge
                                )
                            )
                    }

                    let pixelIndex =
                        y
                        * pixels.width
                        + x

                    let selectionCoverage =
                        Double(
                            selection?[
                                pixelIndex
                            ]
                            ?? 255
                        )
                        / 255

                    let influence =
                        amount
                        * flowAmount
                        * edgeCoverage
                        * selectionCoverage

                    guard influence > 0 else {
                        continue
                    }

                    let sampleMinX =
                        max(
                            0,
                            x
                            - sampleRadius
                        )

                    let sampleMaxX =
                        min(
                            pixels.width
                            - 1,
                            x
                            + sampleRadius
                        )

                    let sampleMinY =
                        max(
                            0,
                            y
                            - sampleRadius
                        )

                    let sampleMaxY =
                        min(
                            pixels.height
                            - 1,
                            y
                            + sampleRadius
                        )

                    var redTotal =
                        0.0

                    var greenTotal =
                        0.0

                    var blueTotal =
                        0.0

                    var sampleCount =
                        0.0

                    for sampleY in sampleMinY...sampleMaxY {
                        for sampleX in sampleMinX...sampleMaxX {
                            let sampleIndex =
                                (
                                    sampleY
                                    * pixels.width
                                    + sampleX
                                )
                                * 4

                            redTotal +=
                                Double(
                                    source[
                                        sampleIndex
                                    ]
                                )

                            greenTotal +=
                                Double(
                                    source[
                                        sampleIndex
                                        + 1
                                    ]
                                )

                            blueTotal +=
                                Double(
                                    source[
                                        sampleIndex
                                        + 2
                                    ]
                                )

                            sampleCount +=
                                1
                        }
                    }

                    guard sampleCount > 0 else {
                        continue
                    }

                    let destinationIndex =
                        pixelIndex
                        * 4

                    let averages =
                        [
                            redTotal / sampleCount,
                            greenTotal / sampleCount,
                            blueTotal / sampleCount,
                        ]

                    for component in 0..<3 {
                        let original =
                            Double(
                                source[
                                    destinationIndex
                                    + component
                                ]
                            )

                        let target: Double

                        if sharpen {
                            target =
                                original
                                + (
                                    original
                                    - averages[
                                        component
                                    ]
                                )
                                * 2
                        } else {
                            target =
                                averages[
                                    component
                                ]
                        }

                        let current =
                            Double(
                                pixels.bytes[
                                    destinationIndex
                                    + component
                                ]
                            )

                        let blended =
                            current
                            + (
                                target
                                - current
                            )
                            * influence

                        pixels.bytes[
                            destinationIndex
                            + component
                        ] =
                            UInt8(
                                max(
                                    0,
                                    min(
                                        255,
                                        blended
                                            .rounded()
                                    )
                                )
                            )
                    }
                }
            }
        }

        return pixels.pngData()
    }

    static func dodgeBurn(imageData:Data,at points:[CGPoint],diameter:Double,strength:Double,lighten:Bool)throws->Data{var pixels=try PixelBuffer(data:imageData);guard diameter.isFinite,diameter>0,diameter<=Double(max(pixels.width,pixels.height))*2 else{return imageData};let r=max(1,diameter/2),amount=max(0,min(1,strength));for p in points{for y in max(0,Int(p.y-r))...min(pixels.height-1,Int(p.y+r)){for x in max(0,Int(p.x-r))...min(pixels.width-1,Int(p.x+r)) where hypot(Double(x)-p.x,Double(y)-p.y)<=r{let i=(y*pixels.width+x)*4;for c in 0..<3{let old=Double(pixels.bytes[i+c]);pixels.bytes[i+c]=UInt8(max(0,min(255,lighten ? old+(255-old)*amount:old*(1-amount))))}}}};return pixels.pngData()}

    static func effectiveDPI(
        _ layer: CoverLayer,
        project: CoverProject
    ) -> Double? {
        guard
            let data = layer.imageData,
            let rep = NSBitmapImageRep(
                data: data
            ),
            rep.pixelsWide > 0,
            rep.pixelsHigh > 0,
            layer.frame.width > 0,
            layer.frame.height > 0,
            project.canvasWidth > 0,
            project.canvasHeight > 0
        else {
            return nil
        }

        let displayedWidth =
            layer.frame.width
            * project.canvasWidth

        let displayedHeight =
            layer.frame.height
            * project.canvasHeight

        guard
            displayedWidth > 0,
            displayedHeight > 0
        else {
            return nil
        }

        var usedWidth =
            Double(
                rep.pixelsWide
            )

        var usedHeight =
            Double(
                rep.pixelsHigh
            )

        if let crop = layer.sourceCrop {
            let fractionWidth =
                max(
                    0.000001,
                    min(
                        1,
                        crop.width
                    )
                )

            let fractionHeight =
                max(
                    0.000001,
                    min(
                        1,
                        crop.height
                    )
                )

            usedWidth *=
                fractionWidth

            usedHeight *=
                fractionHeight
        } else {
            switch layer.cropMode {
            case .fit:
                break

            case .fill:
                let sourceAspect =
                    usedWidth
                    / usedHeight

                let targetAspect =
                    displayedWidth
                    / displayedHeight

                if sourceAspect
                    > targetAspect {

                    usedWidth =
                        usedHeight
                        * targetAspect
                } else {
                    usedHeight =
                        usedWidth
                        / targetAspect
                }

            case .free:
                usedWidth *=
                    1
                    - min(
                        0.9,
                        abs(
                            layer.cropOffsetX
                        )
                    )

                usedHeight *=
                    1
                    - min(
                        0.9,
                        abs(
                            layer.cropOffsetY
                        )
                    )
            }
        }

        return min(
            usedWidth
                / displayedWidth,
            usedHeight
                / displayedHeight
        )
    }

    static func snappedOrigin(_ origin: CGPoint, size: CGSize, canvas: CGSize, threshold: Double = 0.015) -> CGPoint {
        func snap(_ value: Double, candidates: [Double]) -> Double { candidates.min(by:{abs($0-value)<abs($1-value)}).map{abs($0-value)<=threshold ? $0:value} ?? value }
        return CGPoint(x:snap(origin.x,candidates:[0,(canvas.width-size.width)/2,canvas.width-size.width]),y:snap(origin.y,candidates:[0,(canvas.height-size.height)/2,canvas.height-size.height]))
    }

    static func vectorContours(
        for layer:CoverLayer
    )->[[CoverPathPoint]] {
        if var contours=layer.pathContours,
           !contours.isEmpty
        {
            if let primary=layer.pathPoints,
               !primary.isEmpty
            {
                contours[0]=primary
            }

            return contours.filter {
                !$0.isEmpty
            }
        }

        if let points=layer.pathPoints,
           !points.isEmpty
        {
            return [points]
        }

        return []
    }

    static func vectorContourClosures(
        for layer: CoverLayer,
        contourCount: Int
    ) -> [Bool] {
        guard contourCount > 0 else {
            return []
        }

        let contours =
            vectorContours(
                for: layer
            )

        let legacy =
            layer.pathClosed
            ?? (
                (contours.first?.count ?? 0)
                > 2
            )

        var result =
            Array(
                repeating:
                    legacy,
                count:
                    contourCount
            )

        if let explicit =
            layer.pathContourClosed
        {
            for index in 0..<min(
                explicit.count,
                contourCount
            ) {
                result[index] =
                    explicit[index]
            }
        }

        return result
    }

    static func settingVectorContourClosures(
        in layer: CoverLayer,
        closures: [Bool]
    ) -> CoverLayer {
        var output = layer

        let contourCount =
            vectorContours(
                for: output
            )
            .count

        guard closures.count
                == contourCount
        else {
            return output
        }

        output.pathContourClosed =
            closures

        output.pathClosed =
            closures.first
            ?? false

        return output
    }

    static func settingVectorContourClosed(
        in layer: CoverLayer,
        contourIndex: Int,
        closed: Bool
    ) -> CoverLayer? {
        guard layer.kind == .path else {
            return nil
        }

        let contours =
            vectorContours(
                for: layer
            )

        guard contours.indices.contains(
                contourIndex
              ),
              !closed
                || contours[contourIndex].count >= 2
        else {
            return nil
        }

        var closures =
            vectorContourClosures(
                for: layer,
                contourCount:
                    contours.count
            )

        closures[
            contourIndex
        ] = closed

        return settingVectorContourClosures(
            in: layer,
            closures:
                closures
        )
    }


    static let ellipseBezierKappa =
        0.5522847498307936

    static func convertedShapeToPath(
        _ layer: CoverLayer
    ) -> CoverLayer? {
        guard layer.kind == .shape else {
            return nil
        }

        var output = layer

        let points: [CoverPathPoint]
        let closed: Bool

        switch layer.shape {
        case .rectangle:
            points = [
                CoverPathPoint(
                    x: 0,
                    y: 0
                ),
                CoverPathPoint(
                    x: 1,
                    y: 0
                ),
                CoverPathPoint(
                    x: 1,
                    y: 1
                ),
                CoverPathPoint(
                    x: 0,
                    y: 1
                )
            ]

            closed = true

        case .ellipse:
            let handle =
                ellipseBezierKappa
                * 0.5

            points = [
                CoverPathPoint(
                    x: 0.5,
                    y: 0,
                    controlInX:
                        0.5 - handle,
                    controlInY: 0,
                    controlOutX:
                        0.5 + handle,
                    controlOutY: 0
                ),
                CoverPathPoint(
                    x: 1,
                    y: 0.5,
                    controlInX: 1,
                    controlInY:
                        0.5 - handle,
                    controlOutX: 1,
                    controlOutY:
                        0.5 + handle
                ),
                CoverPathPoint(
                    x: 0.5,
                    y: 1,
                    controlInX:
                        0.5 + handle,
                    controlInY: 1,
                    controlOutX:
                        0.5 - handle,
                    controlOutY: 1
                ),
                CoverPathPoint(
                    x: 0,
                    y: 0.5,
                    controlInX: 0,
                    controlInY:
                        0.5 + handle,
                    controlOutX: 0,
                    controlOutY:
                        0.5 - handle
                )
            ]

            closed = true

        case .line:
            points = [
                CoverPathPoint(
                    x: 0,
                    y: 0.5
                ),
                CoverPathPoint(
                    x: 1,
                    y: 0.5
                )
            ]

            closed = false
        }

        output.kind = .path
        output.pathPoints = points
        output.pathContours = [
            points
        ]
        output.pathClosed = closed

        return output
    }

    static func vectorAnchorCount(
        for layer: CoverLayer
    ) -> Int {
        vectorContours(
            for: layer
        )
        .reduce(0) {
            $0 + $1.count
        }
    }

    static func translatingVectorAnchors(
        in layer: CoverLayer,
        selections: Set<CoverVectorAnchorIndex>,
        deltaX: Double,
        deltaY: Double
    ) -> CoverLayer {
        guard layer.kind == .path,
              !selections.isEmpty,
              deltaX.isFinite,
              deltaY.isFinite
        else {
            return layer
        }

        var output = layer
        var contours = vectorContours(
            for: output
        )

        guard !contours.isEmpty else {
            return output
        }

        let hadExplicitContours =
            output.pathContours != nil

        func clampAnchor(
            _ value: Double
        ) -> Double {
            max(
                -4,
                min(
                    5,
                    value
                )
            )
        }

        for selection in selections {
            guard contours.indices.contains(
                selection.contourIndex
            ),
            contours[
                selection.contourIndex
            ]
            .indices
            .contains(
                selection.pointIndex
            )
            else {
                continue
            }

            var point =
                contours[
                    selection.contourIndex
                ][
                    selection.pointIndex
                ]

            let nextX =
                clampAnchor(
                    point.x
                    + deltaX
                )

            let nextY =
                clampAnchor(
                    point.y
                    + deltaY
                )

            let appliedX =
                nextX
                - point.x

            let appliedY =
                nextY
                - point.y

            point.x = nextX
            point.y = nextY

            if let value =
                point.controlInX
            {
                point.controlInX =
                    value
                    + appliedX
            }

            if let value =
                point.controlInY
            {
                point.controlInY =
                    value
                    + appliedY
            }

            if let value =
                point.controlOutX
            {
                point.controlOutX =
                    value
                    + appliedX
            }

            if let value =
                point.controlOutY
            {
                point.controlOutY =
                    value
                    + appliedY
            }

            contours[
                selection.contourIndex
            ][
                selection.pointIndex
            ] = point
        }

        if hadExplicitContours {
            output.pathContours =
                contours
        } else {
            output.pathContours =
                nil
        }

        output.pathPoints =
            contours.first

        return output
    }

    private static let vectorSelectionTransformCoordinateLimit =
        1_000_000.0

    private static func validVectorSelectionTransformCoordinate(
        _ value: Double
    ) -> Bool {
        value.isFinite
        && abs(value)
            <= vectorSelectionTransformCoordinateLimit
    }

    static func vectorContourAnchorSelection(
        in layer: CoverLayer,
        contourIndex: Int
    ) -> Set<CoverVectorAnchorIndex> {
        guard layer.kind == .path else {
            return []
        }

        let contours =
            vectorContours(
                for:
                    layer
            )

        guard contours.indices.contains(
            contourIndex
        )
        else {
            return []
        }

        return Set(
            contours[
                contourIndex
            ]
            .indices
            .map {
                CoverVectorAnchorIndex(
                    contourIndex:
                        contourIndex,
                    pointIndex:
                        $0
                )
            }
        )
    }

    static func selectedVectorGeometryBounds(
        in layer: CoverLayer,
        selections: Set<CoverVectorAnchorIndex>
    ) -> CoverVectorSelectionBounds? {
        guard layer.kind == .path,
              !selections.isEmpty
        else {
            return nil
        }

        let contours =
            vectorContours(
                for:
                    layer
            )

        var selectedPoints:
            [CoverPathPoint] = []

        selectedPoints.reserveCapacity(
            selections.count
        )

        for selection in selections {
            guard contours.indices.contains(
                selection.contourIndex
            ),
            contours[
                selection.contourIndex
            ]
            .indices
            .contains(
                selection.pointIndex
            )
            else {
                return nil
            }

            selectedPoints.append(
                contours[
                    selection.contourIndex
                ][
                    selection.pointIndex
                ]
            )
        }

        guard let first =
            selectedPoints.first,
              first.x.isFinite,
              first.y.isFinite
        else {
            return nil
        }

        var minX =
            first.x

        var minY =
            first.y

        var maxX =
            first.x

        var maxY =
            first.y

        for point in selectedPoints.dropFirst() {
            guard point.x.isFinite,
                  point.y.isFinite
            else {
                return nil
            }

            minX =
                min(
                    minX,
                    point.x
                )

            minY =
                min(
                    minY,
                    point.y
                )

            maxX =
                max(
                    maxX,
                    point.x
                )

            maxY =
                max(
                    maxY,
                    point.y
                )
        }

        return CoverVectorSelectionBounds(
            minX:
                minX,
            minY:
                minY,
            maxX:
                maxX,
            maxY:
                maxY
        )
    }

    private static func transformingVectorAnchors(
        in layer: CoverLayer,
        selections: Set<CoverVectorAnchorIndex>,
        transform: (
            Double,
            Double
        ) -> (
            x: Double,
            y: Double
        )?
    ) -> CoverLayer? {
        guard layer.kind == .path,
              !selections.isEmpty
        else {
            return nil
        }

        var output =
            layer

        var contours =
            vectorContours(
                for:
                    output
            )

        guard !contours.isEmpty else {
            return nil
        }

        let hadExplicitContours =
            output.pathContours
            != nil

        for selection in selections {
            guard contours.indices.contains(
                selection.contourIndex
            ),
            contours[
                selection.contourIndex
            ]
            .indices
            .contains(
                selection.pointIndex
            )
            else {
                return nil
            }
        }

        for selection in selections {
            let original =
                contours[
                    selection.contourIndex
                ][
                    selection.pointIndex
                ]

            guard let anchor =
                transform(
                    original.x,
                    original.y
                ),
                  validVectorSelectionTransformCoordinate(
                    anchor.x
                  ),
                  validVectorSelectionTransformCoordinate(
                    anchor.y
                  )
            else {
                return nil
            }

            var point =
                original

            point.x =
                anchor.x

            point.y =
                anchor.y

            if original.controlInX != nil
                || original.controlInY != nil
            {
                let sourceX =
                    original.controlInX
                    ?? original.x

                let sourceY =
                    original.controlInY
                    ?? original.y

                guard let transformed =
                    transform(
                        sourceX,
                        sourceY
                    ),
                      validVectorSelectionTransformCoordinate(
                        transformed.x
                      ),
                      validVectorSelectionTransformCoordinate(
                        transformed.y
                      )
                else {
                    return nil
                }

                if original.controlInX != nil {
                    point.controlInX =
                        transformed.x
                }

                if original.controlInY != nil {
                    point.controlInY =
                        transformed.y
                }
            }

            if original.controlOutX != nil
                || original.controlOutY != nil
            {
                let sourceX =
                    original.controlOutX
                    ?? original.x

                let sourceY =
                    original.controlOutY
                    ?? original.y

                guard let transformed =
                    transform(
                        sourceX,
                        sourceY
                    ),
                      validVectorSelectionTransformCoordinate(
                        transformed.x
                      ),
                      validVectorSelectionTransformCoordinate(
                        transformed.y
                      )
                else {
                    return nil
                }

                if original.controlOutX != nil {
                    point.controlOutX =
                        transformed.x
                }

                if original.controlOutY != nil {
                    point.controlOutY =
                        transformed.y
                }
            }

            contours[
                selection.contourIndex
            ][
                selection.pointIndex
            ] =
                point
        }

        if hadExplicitContours {
            output.pathContours =
                contours
        } else {
            output.pathContours =
                nil
        }

        output.pathPoints =
            contours.first

        return output
    }

    static func scalingVectorAnchors(
        in layer: CoverLayer,
        selections: Set<CoverVectorAnchorIndex>,
        scaleX: Double,
        scaleY: Double,
        pivotX: Double,
        pivotY: Double
    ) -> CoverLayer? {
        guard scaleX.isFinite,
              scaleY.isFinite,
              pivotX.isFinite,
              pivotY.isFinite,
              abs(scaleX)
                <= vectorSelectionTransformCoordinateLimit,
              abs(scaleY)
                <= vectorSelectionTransformCoordinateLimit,
              validVectorSelectionTransformCoordinate(
                pivotX
              ),
              validVectorSelectionTransformCoordinate(
                pivotY
              )
        else {
            return nil
        }

        return transformingVectorAnchors(
            in:
                layer,
            selections:
                selections
        ) {
            x,
            y in

            let nextX =
                pivotX
                + (
                    x
                    - pivotX
                )
                * scaleX

            let nextY =
                pivotY
                + (
                    y
                    - pivotY
                )
                * scaleY

            guard nextX.isFinite,
                  nextY.isFinite
            else {
                return nil
            }

            return (
                nextX,
                nextY
            )
        }
    }

    static func rotatingVectorAnchors(
        in layer: CoverLayer,
        selections: Set<CoverVectorAnchorIndex>,
        degrees: Double,
        pivotX: Double,
        pivotY: Double
    ) -> CoverLayer? {
        guard degrees.isFinite,
              pivotX.isFinite,
              pivotY.isFinite,
              validVectorSelectionTransformCoordinate(
                pivotX
              ),
              validVectorSelectionTransformCoordinate(
                pivotY
              )
        else {
            return nil
        }

        let normalizedDegrees =
            degrees.truncatingRemainder(
                dividingBy:
                    360
            )

        let radians =
            normalizedDegrees
            * Double.pi
            / 180

        let cosine =
            cos(
                radians
            )

        let sine =
            sin(
                radians
            )

        return transformingVectorAnchors(
            in:
                layer,
            selections:
                selections
        ) {
            x,
            y in

            let offsetX =
                x
                - pivotX

            let offsetY =
                y
                - pivotY

            let nextX =
                pivotX
                + offsetX
                * cosine
                - offsetY
                * sine

            let nextY =
                pivotY
                + offsetX
                * sine
                + offsetY
                * cosine

            guard nextX.isFinite,
                  nextY.isFinite
            else {
                return nil
            }

            return (
                nextX,
                nextY
            )
        }
    }

    static func flippingVectorAnchors(
        in layer: CoverLayer,
        selections: Set<CoverVectorAnchorIndex>,
        horizontal: Bool,
        pivotX: Double,
        pivotY: Double
    ) -> CoverLayer? {
        scalingVectorAnchors(
            in:
                layer,
            selections:
                selections,
            scaleX:
                horizontal
                ? -1
                : 1,
            scaleY:
                horizontal
                ? 1
                : -1,
            pivotX:
                pivotX,
            pivotY:
                pivotY
        )
    }


    static func settingVectorAnchorType(
        in layer: CoverLayer,
        selections: Set<CoverVectorAnchorIndex>,
        type: CoverPathAnchorType
    ) -> CoverLayer {
        guard layer.kind == .path,
              !selections.isEmpty
        else {
            return layer
        }

        var output = layer

        var contours =
            vectorContours(
                for: output
            )

        guard !contours.isEmpty else {
            return output
        }

        let hadExplicitContours =
            output.pathContours != nil

        let closures =
            vectorContourClosures(
                for: output,
                contourCount:
                    contours.count
            )

        for selection in selections {
            guard contours.indices.contains(
                selection.contourIndex
            ),
            contours[
                selection.contourIndex
            ]
            .indices
            .contains(
                selection.pointIndex
            )
            else {
                continue
            }

            contours[
                selection.contourIndex
            ] =
                settingPathAnchorType(
                    contours[
                        selection.contourIndex
                    ],
                    index:
                        selection.pointIndex,
                    type:
                        type,
                    closed:
                        closures[
                            selection.contourIndex
                        ]
                )
        }

        if hadExplicitContours
            || contours.count > 1
        {
            output.pathContours =
                contours
        } else {
            output.pathContours =
                nil
        }

        output.pathPoints =
            contours.first

        output =
            settingVectorContourClosures(
                in: output,
                closures:
                    closures
            )

        return output
    }

    static func settingPathAnchorType(
        _ points: [CoverPathPoint],
        index: Int,
        type: CoverPathAnchorType,
        closed: Bool
    ) -> [CoverPathPoint] {
        guard points.indices.contains(
            index
        ) else {
            return points
        }

        var result = points
        var point = result[index]

        point.anchorType = type

        guard type != .corner else {
            result[index] = point
            return result
        }

        let previousIndex: Int? = {
            if index > 0 {
                return index - 1
            }

            if closed,
               points.count > 1
            {
                return points.count - 1
            }

            return nil
        }()

        let nextIndex: Int? = {
            if index + 1 < points.count {
                return index + 1
            }

            if closed,
               points.count > 1
            {
                return 0
            }

            return nil
        }()

        func distance(
            fromX: Double,
            fromY: Double,
            toX: Double,
            toY: Double
        ) -> Double {
            hypot(
                toX - fromX,
                toY - fromY
            )
        }

        let existingInLength: Double = {
            guard point.controlInX != nil
                    || point.controlInY != nil
            else {
                return 0
            }

            return distance(
                fromX:
                    point.x,
                fromY:
                    point.y,
                toX:
                    point.controlInX
                    ?? point.x,
                toY:
                    point.controlInY
                    ?? point.y
            )
        }()

        let existingOutLength: Double = {
            guard point.controlOutX != nil
                    || point.controlOutY != nil
            else {
                return 0
            }

            return distance(
                fromX:
                    point.x,
                fromY:
                    point.y,
                toX:
                    point.controlOutX
                    ?? point.x,
                toY:
                    point.controlOutY
                    ?? point.y
            )
        }()

        let previousDistance: Double = {
            guard let previousIndex else {
                return 0
            }

            let previous =
                points[
                    previousIndex
                ]

            return distance(
                fromX:
                    point.x,
                fromY:
                    point.y,
                toX:
                    previous.x,
                toY:
                    previous.y
            )
        }()

        let nextDistance: Double = {
            guard let nextIndex else {
                return 0
            }

            let next =
                points[
                    nextIndex
                ]

            return distance(
                fromX:
                    point.x,
                fromY:
                    point.y,
                toX:
                    next.x,
                toY:
                    next.y
            )
        }()

        var directionX = 1.0
        var directionY = 0.0

        if let previousIndex,
           let nextIndex
        {
            let previous =
                points[
                    previousIndex
                ]

            let next =
                points[
                    nextIndex
                ]

            directionX =
                next.x
                - previous.x

            directionY =
                next.y
                - previous.y
        } else if let nextIndex {
            let next =
                points[
                    nextIndex
                ]

            directionX =
                next.x
                - point.x

            directionY =
                next.y
                - point.y
        } else if let previousIndex {
            let previous =
                points[
                    previousIndex
                ]

            directionX =
                point.x
                - previous.x

            directionY =
                point.y
                - previous.y
        }

        var directionLength =
            hypot(
                directionX,
                directionY
            )

        if directionLength
            <= 0.0000001
        {
            if existingOutLength
                > 0.0000001
            {
                directionX =
                    (
                        point.controlOutX
                        ?? point.x
                    )
                    - point.x

                directionY =
                    (
                        point.controlOutY
                        ?? point.y
                    )
                    - point.y

                directionLength =
                    hypot(
                        directionX,
                        directionY
                    )
            } else if existingInLength
                        > 0.0000001
            {
                directionX =
                    point.x
                    - (
                        point.controlInX
                        ?? point.x
                    )

                directionY =
                    point.y
                    - (
                        point.controlInY
                        ?? point.y
                    )

                directionLength =
                    hypot(
                        directionX,
                        directionY
                    )
            }
        }

        if directionLength
            <= 0.0000001
        {
            directionX = 1
            directionY = 0
            directionLength = 1
        }

        directionX /= directionLength
        directionY /= directionLength

        func defaultLength(
            preferred: Double,
            alternate: Double
        ) -> Double {
            if preferred
                > 0.0000001
            {
                return preferred
            }

            if alternate
                > 0.0000001
            {
                return alternate / 3
            }

            return 0.1
        }

        switch type {
        case .corner:
            break

        case .smooth:
            let inLength =
                defaultLength(
                    preferred:
                        existingInLength,
                    alternate:
                        previousDistance
                )

            let outLength =
                defaultLength(
                    preferred:
                        existingOutLength,
                    alternate:
                        nextDistance
                )

            point.controlInX =
                point.x
                - directionX
                * inLength

            point.controlInY =
                point.y
                - directionY
                * inLength

            point.controlOutX =
                point.x
                + directionX
                * outLength

            point.controlOutY =
                point.y
                + directionY
                * outLength

        case .symmetric:
            let handleLength: Double = {
                if existingInLength
                    > 0.0000001,
                   existingOutLength
                    > 0.0000001
                {
                    return (
                        existingInLength
                        + existingOutLength
                    )
                    / 2
                }

                if existingInLength
                    > 0.0000001
                {
                    return existingInLength
                }

                if existingOutLength
                    > 0.0000001
                {
                    return existingOutLength
                }

                let nearby =
                    [
                        previousDistance,
                        nextDistance
                    ]
                    .filter {
                        $0 > 0.0000001
                    }

                if let shortest =
                    nearby.min()
                {
                    return shortest / 3
                }

                return 0.1
            }()

            point.controlInX =
                point.x
                - directionX
                * handleLength

            point.controlInY =
                point.y
                - directionY
                * handleLength

            point.controlOutX =
                point.x
                + directionX
                * handleLength

            point.controlOutY =
                point.y
                + directionY
                * handleLength
        }

        result[index] = point
        return result
    }


    static func nearestVectorSegment(
        in layer: CoverLayer,
        to point: CGPoint,
        scaleX: Double,
        scaleY: Double
    ) -> CoverVectorSegmentHit? {
        guard layer.kind == .path,
              scaleX.isFinite,
              scaleY.isFinite,
              scaleX > 0,
              scaleY > 0
        else {
            return nil
        }

        let contours =
            vectorContours(
                for: layer
            )

        guard !contours.isEmpty else {
            return nil
        }

        let closures =
            vectorContourClosures(
                for: layer,
                contourCount:
                    contours.count
            )

        let queryX =
            Double(point.x)
            * scaleX

        let queryY =
            Double(point.y)
            * scaleY

        func distanceSquared(
            x: Double,
            y: Double
        ) -> Double {
            let dx =
                x - queryX

            let dy =
                y - queryY

            return
                dx * dx
                + dy * dy
        }

        func cubicValue(
            _ p0: Double,
            _ p1: Double,
            _ p2: Double,
            _ p3: Double,
            _ t: Double
        ) -> Double {
            let u =
                1 - t

            return
                u * u * u * p0
                + 3 * u * u * t * p1
                + 3 * u * t * t * p2
                + t * t * t * p3
        }

        func curvePoint(
            from: CoverPathPoint,
            to: CoverPathPoint,
            t: Double
        ) -> (
            x: Double,
            y: Double
        ) {
            let x =
                cubicValue(
                    from.x,
                    from.controlOutX
                        ?? from.x,
                    to.controlInX
                        ?? to.x,
                    to.x,
                    t
                )

            let y =
                cubicValue(
                    from.y,
                    from.controlOutY
                        ?? from.y,
                    to.controlInY
                        ?? to.y,
                    to.y,
                    t
                )

            return (
                x * scaleX,
                y * scaleY
            )
        }

        var best:
            CoverVectorSegmentHit?

        for contourIndex in contours.indices {
            let contour =
                contours[
                    contourIndex
                ]

            guard contour.count >= 2 else {
                continue
            }

            let segmentCount =
                closures[
                    contourIndex
                ]
                ? contour.count
                : contour.count - 1

            guard segmentCount > 0 else {
                continue
            }

            for startIndex in 0..<segmentCount {
                let endIndex =
                    (
                        startIndex
                        + 1
                    )
                    % contour.count

                let from =
                    contour[
                        startIndex
                    ]

                let to =
                    contour[
                        endIndex
                    ]

                let hitT: Double
                let hitDistance: Double

                if vectorSegmentIsCurved(
                    from,
                    to
                ) {
                    let sampleCount = 48

                    var sampleT = 0.0

                    var sampleDistance =
                        Double
                            .greatestFiniteMagnitude

                    for sample in 0...sampleCount {
                        let t =
                            Double(sample)
                            / Double(
                                sampleCount
                            )

                        let position =
                            curvePoint(
                                from: from,
                                to: to,
                                t: t
                            )

                        let distance =
                            distanceSquared(
                                x: position.x,
                                y: position.y
                            )

                        if distance
                            < sampleDistance
                        {
                            sampleDistance =
                                distance

                            sampleT = t
                        }
                    }

                    let sampleWidth =
                        1
                        / Double(
                            sampleCount
                        )

                    var low =
                        max(
                            0,
                            sampleT
                            - sampleWidth
                        )

                    var high =
                        min(
                            1,
                            sampleT
                            + sampleWidth
                        )

                    for _ in 0..<30 {
                        let third =
                            (
                                high
                                - low
                            )
                            / 3

                        let first =
                            low
                            + third

                        let second =
                            high
                            - third

                        let firstPoint =
                            curvePoint(
                                from: from,
                                to: to,
                                t: first
                            )

                        let secondPoint =
                            curvePoint(
                                from: from,
                                to: to,
                                t: second
                            )

                        let firstDistance =
                            distanceSquared(
                                x: firstPoint.x,
                                y: firstPoint.y
                            )

                        let secondDistance =
                            distanceSquared(
                                x: secondPoint.x,
                                y: secondPoint.y
                            )

                        if firstDistance
                            <= secondDistance
                        {
                            high = second
                        } else {
                            low = first
                        }
                    }

                    hitT =
                        (
                            low
                            + high
                        )
                        / 2

                    let finalPoint =
                        curvePoint(
                            from: from,
                            to: to,
                            t: hitT
                        )

                    hitDistance =
                        sqrt(
                            distanceSquared(
                                x: finalPoint.x,
                                y: finalPoint.y
                            )
                        )
                } else {
                    let startX =
                        from.x
                        * scaleX

                    let startY =
                        from.y
                        * scaleY

                    let endX =
                        to.x
                        * scaleX

                    let endY =
                        to.y
                        * scaleY

                    let dx =
                        endX
                        - startX

                    let dy =
                        endY
                        - startY

                    let denominator =
                        dx * dx
                        + dy * dy

                    if denominator
                        <= 0.000000000001
                    {
                        hitT = 0

                        hitDistance =
                            sqrt(
                                distanceSquared(
                                    x: startX,
                                    y: startY
                                )
                            )
                    } else {
                        let projected =
                            (
                                (
                                    queryX
                                    - startX
                                )
                                * dx
                                + (
                                    queryY
                                    - startY
                                )
                                * dy
                            )
                            / denominator

                        hitT =
                            max(
                                0,
                                min(
                                    1,
                                    projected
                                )
                            )

                        let x =
                            startX
                            + dx
                            * hitT

                        let y =
                            startY
                            + dy
                            * hitT

                        hitDistance =
                            sqrt(
                                distanceSquared(
                                    x: x,
                                    y: y
                                )
                            )
                    }
                }

                if best == nil
                    || hitDistance
                        < best!.distance
                {
                    best =
                        CoverVectorSegmentHit(
                            contourIndex:
                                contourIndex,
                            startPointIndex:
                                startIndex,
                            t:
                                hitT,
                            distance:
                                hitDistance
                        )
                }
            }
        }

        return best
    }

    static func insertingVectorPoint(
        in layer: CoverLayer,
        contourIndex: Int,
        startPointIndex: Int,
        t: Double
    ) -> CoverVectorSegmentInsertion? {
        guard layer.kind == .path,
              t.isFinite
        else {
            return nil
        }

        var output = layer

        var contours =
            vectorContours(
                for: output
            )

        guard contours.indices.contains(
            contourIndex
        ) else {
            return nil
        }

        var contour =
            contours[
                contourIndex
            ]

        guard contour.count >= 2,
              contour.indices.contains(
                startPointIndex
              )
        else {
            return nil
        }

        let closures =
            vectorContourClosures(
                for: output,
                contourCount:
                    contours.count
            )

        let closed =
            closures[
                contourIndex
            ]

        let endPointIndex: Int
        let insertionIndex: Int

        if startPointIndex
            < contour.count - 1
        {
            endPointIndex =
                startPointIndex
                + 1

            insertionIndex =
                endPointIndex
        } else {
            guard closed else {
                return nil
            }

            endPointIndex = 0

            insertionIndex =
                contour.count
        }

        let fraction =
            max(
                0.001,
                min(
                    0.999,
                    t
                )
            )

        func lerp(
            _ start: Double,
            _ end: Double
        ) -> Double {
            start
            + (
                end
                - start
            )
            * fraction
        }

        var from =
            contour[
                startPointIndex
            ]

        var to =
            contour[
                endPointIndex
            ]

        let inserted:
            CoverPathPoint

        if vectorSegmentIsCurved(
            from,
            to
        ) {
            let p0x = from.x
            let p0y = from.y

            let p1x =
                from.controlOutX
                ?? from.x

            let p1y =
                from.controlOutY
                ?? from.y

            let p2x =
                to.controlInX
                ?? to.x

            let p2y =
                to.controlInY
                ?? to.y

            let p3x = to.x
            let p3y = to.y

            let ax =
                lerp(
                    p0x,
                    p1x
                )

            let ay =
                lerp(
                    p0y,
                    p1y
                )

            let bx =
                lerp(
                    p1x,
                    p2x
                )

            let by =
                lerp(
                    p1y,
                    p2y
                )

            let cx =
                lerp(
                    p2x,
                    p3x
                )

            let cy =
                lerp(
                    p2y,
                    p3y
                )

            let dx =
                lerp(
                    ax,
                    bx
                )

            let dy =
                lerp(
                    ay,
                    by
                )

            let ex =
                lerp(
                    bx,
                    cx
                )

            let ey =
                lerp(
                    by,
                    cy
                )

            let fx =
                lerp(
                    dx,
                    ex
                )

            let fy =
                lerp(
                    dy,
                    ey
                )

            from.controlOutX = ax
            from.controlOutY = ay

            to.controlInX = cx
            to.controlInY = cy

            inserted =
                CoverPathPoint(
                    x: fx,
                    y: fy,
                    controlInX: dx,
                    controlInY: dy,
                    controlOutX: ex,
                    controlOutY: ey
                )
        } else {
            inserted =
                CoverPathPoint(
                    x:
                        lerp(
                            from.x,
                            to.x
                        ),
                    y:
                        lerp(
                            from.y,
                            to.y
                        )
                )
        }

        contour[
            startPointIndex
        ] = from

        contour[
            endPointIndex
        ] = to

        contour.insert(
            inserted,
            at: insertionIndex
        )

        contours[
            contourIndex
        ] = contour

        if output.pathContours != nil
            || contours.count > 1
        {
            output.pathContours =
                contours
        } else {
            output.pathContours =
                nil
        }

        output.pathPoints =
            contours.first

        return CoverVectorSegmentInsertion(
            layer:
                output,
            anchor:
                CoverVectorAnchorIndex(
                    contourIndex:
                        contourIndex,
                    pointIndex:
                        insertionIndex
                )
        )
    }

    static func reversedVectorContour(
        _ points: [CoverPathPoint]
    ) -> [CoverPathPoint] {
        points
            .reversed()
            .map {
                point in

                var reversed = point

                reversed.controlInX =
                    point.controlOutX

                reversed.controlInY =
                    point.controlOutY

                reversed.controlOutX =
                    point.controlInX

                reversed.controlOutY =
                    point.controlInY

                return reversed
            }
    }

    static func duplicatingVectorContour(
        in layer: CoverLayer,
        contourIndex: Int
    ) -> CoverVectorContourMutationResult? {
        guard layer.kind == .path else {
            return nil
        }

        var output = layer

        var contours =
            vectorContours(
                for: output
            )

        guard contours.indices.contains(
                contourIndex
              ),
              !contours[
                contourIndex
              ]
              .isEmpty
        else {
            return nil
        }

        var closures =
            vectorContourClosures(
                for: output,
                contourCount:
                    contours.count
            )

        let duplicateIndex =
            contourIndex + 1

        let duplicate =
            contours[
                contourIndex
            ]

        let duplicateClosed =
            closures[
                contourIndex
            ]

        contours.insert(
            duplicate,
            at:
                duplicateIndex
        )

        closures.insert(
            duplicateClosed,
            at:
                duplicateIndex
        )

        output.pathContours =
            contours

        output.pathPoints =
            contours.first

        output =
            settingVectorContourClosures(
                in: output,
                closures:
                    closures
            )

        let selected =
            Set(
                duplicate.indices.map {
                    pointIndex in

                    CoverVectorAnchorIndex(
                        contourIndex:
                            duplicateIndex,
                        pointIndex:
                            pointIndex
                    )
                }
            )

        let active =
            duplicate.isEmpty
            ? nil
            : CoverVectorAnchorIndex(
                contourIndex:
                    duplicateIndex,
                pointIndex:
                    0
            )

        return CoverVectorContourMutationResult(
            layer:
                output,
            contourIndex:
                duplicateIndex,
            selectedAnchors:
                selected,
            activeAnchor:
                active
        )
    }

    static func reversingVectorContour(
        in layer: CoverLayer,
        contourIndex: Int
    ) -> CoverVectorContourMutationResult? {
        guard layer.kind == .path else {
            return nil
        }

        var output = layer

        var contours =
            vectorContours(
                for: output
            )

        guard contours.indices.contains(
                contourIndex
              ),
              !contours[
                contourIndex
              ]
              .isEmpty
        else {
            return nil
        }

        let closures =
            vectorContourClosures(
                for: output,
                contourCount:
                    contours.count
            )

        contours[
            contourIndex
        ] =
            reversedVectorContour(
                contours[
                    contourIndex
                ]
            )

        if output.pathContours != nil
            || contours.count > 1
        {
            output.pathContours =
                contours
        } else {
            output.pathContours =
                nil
        }

        output.pathPoints =
            contours.first

        output =
            settingVectorContourClosures(
                in: output,
                closures:
                    closures
            )

        let reversed =
            contours[
                contourIndex
            ]

        let selected =
            Set(
                reversed.indices.map {
                    pointIndex in

                    CoverVectorAnchorIndex(
                        contourIndex:
                            contourIndex,
                        pointIndex:
                            pointIndex
                    )
                }
            )

        let active =
            reversed.isEmpty
            ? nil
            : CoverVectorAnchorIndex(
                contourIndex:
                    contourIndex,
                pointIndex:
                    0
            )

        return CoverVectorContourMutationResult(
            layer:
                output,
            contourIndex:
                contourIndex,
            selectedAnchors:
                selected,
            activeAnchor:
                active
        )
    }

    static func remappedVectorContourIndex(
        _ index: Int,
        moving sourceIndex: Int,
        to destinationIndex: Int
    ) -> Int {
        if index == sourceIndex {
            return destinationIndex
        }

        if sourceIndex < destinationIndex {
            if index > sourceIndex
                && index <= destinationIndex
            {
                return index - 1
            }

            return index
        }

        if sourceIndex > destinationIndex {
            if index >= destinationIndex
                && index < sourceIndex
            {
                return index + 1
            }

            return index
        }

        return index
    }

    static func orderingVectorContour(
        in layer: CoverLayer,
        contourIndex: Int,
        move: CoverVectorContourOrderMove,
        selectedAnchors: Set<CoverVectorAnchorIndex> = []
    ) -> CoverVectorContourOrderResult? {
        guard layer.kind == .path else {
            return nil
        }

        var output = layer

        var contours =
            vectorContours(
                for: output
            )

        guard contours.count >= 2,
              contours.indices.contains(
                contourIndex
              )
        else {
            return nil
        }

        var closures =
            vectorContourClosures(
                for: output,
                contourCount:
                    contours.count
            )

        let destinationIndex: Int

        switch move {
        case .forward:
            guard contourIndex
                    < contours.count - 1
            else {
                return nil
            }

            destinationIndex =
                contourIndex + 1

        case .backward:
            guard contourIndex > 0 else {
                return nil
            }

            destinationIndex =
                contourIndex - 1

        case .front:
            guard contourIndex
                    < contours.count - 1
            else {
                return nil
            }

            destinationIndex =
                contours.count - 1

        case .back:
            guard contourIndex > 0 else {
                return nil
            }

            destinationIndex =
                0
        }

        guard destinationIndex
                != contourIndex
        else {
            return nil
        }

        let validSelections =
            selectedAnchors.filter {
                selection in

                guard contours.indices.contains(
                    selection.contourIndex
                ) else {
                    return false
                }

                return contours[
                    selection.contourIndex
                ]
                .indices
                .contains(
                    selection.pointIndex
                )
            }

        let movedContour =
            contours.remove(
                at:
                    contourIndex
            )

        let movedClosure =
            closures.remove(
                at:
                    contourIndex
            )

        contours.insert(
            movedContour,
            at:
                destinationIndex
        )

        closures.insert(
            movedClosure,
            at:
                destinationIndex
        )

        let remappedSelections =
            Set(
                validSelections.map {
                    selection in

                    CoverVectorAnchorIndex(
                        contourIndex:
                            remappedVectorContourIndex(
                                selection.contourIndex,
                                moving:
                                    contourIndex,
                                to:
                                    destinationIndex
                            ),
                        pointIndex:
                            selection.pointIndex
                    )
                }
            )

        output.pathContours =
            contours

        output.pathPoints =
            contours.first

        output =
            settingVectorContourClosures(
                in: output,
                closures:
                    closures
            )

        let activeAnchor =
            remappedSelections
                .filter {
                    $0.contourIndex
                        == destinationIndex
                }
                .sorted {
                    lhs,
                    rhs in

                    lhs.pointIndex
                        < rhs.pointIndex
                }
                .first

        return CoverVectorContourOrderResult(
            layer:
                output,
            contourIndex:
                destinationIndex,
            selectedAnchors:
                remappedSelections,
            activeAnchor:
                activeAnchor
        )
    }



    static func joiningVectorEndpoints(
        in layer: CoverLayer,
        first: CoverVectorAnchorIndex,
        second: CoverVectorAnchorIndex
    ) -> CoverVectorJoinResult? {
        guard layer.kind == .path,
              first != second
        else {
            return nil
        }

        var output = layer

        var contours =
            vectorContours(
                for: output
            )

        guard !contours.isEmpty,
              contours.indices.contains(
                first.contourIndex
              ),
              contours.indices.contains(
                second.contourIndex
              )
        else {
            return nil
        }

        var closures =
            vectorContourClosures(
                for: output,
                contourCount:
                    contours.count
            )

        let firstContour =
            contours[first.contourIndex]

        let secondContour =
            contours[second.contourIndex]

        guard firstContour.indices.contains(
                first.pointIndex
              ),
              secondContour.indices.contains(
                second.pointIndex
              )
        else {
            return nil
        }

        func isEndpoint(
            contour: [CoverPathPoint],
            pointIndex: Int
        ) -> Bool {
            guard !contour.isEmpty else {
                return false
            }

            return pointIndex == 0
                || pointIndex == contour.count - 1
        }

        guard isEndpoint(
                contour: firstContour,
                pointIndex: first.pointIndex
              ),
              isEndpoint(
                contour: secondContour,
                pointIndex: second.pointIndex
              )
        else {
            return nil
        }

        if first.contourIndex == second.contourIndex {
            let contourIndex =
                first.contourIndex

            guard closures[contourIndex] == false,
                  firstContour.count >= 2
            else {
                return nil
            }

            let endpointSet =
                Set([
                    first.pointIndex,
                    second.pointIndex
                ])

            guard endpointSet
                    == Set([
                        0,
                        firstContour.count - 1
                    ])
            else {
                return nil
            }

            closures[contourIndex] = true

            output =
                settingVectorContourClosures(
                    in: output,
                    closures: closures
                )

            let selections:
                Set<CoverVectorAnchorIndex> = [
                    CoverVectorAnchorIndex(
                        contourIndex: contourIndex,
                        pointIndex: 0
                    ),
                    CoverVectorAnchorIndex(
                        contourIndex: contourIndex,
                        pointIndex:
                            firstContour.count - 1
                    )
                ]

            return CoverVectorJoinResult(
                layer: output,
                selectedAnchors: selections,
                activeAnchor:
                    CoverVectorAnchorIndex(
                        contourIndex: contourIndex,
                        pointIndex:
                            min(
                                first.pointIndex,
                                second.pointIndex
                            )
                    )
            )
        }

        guard closures[first.contourIndex] == false,
              closures[second.contourIndex] == false
        else {
            return nil
        }

        var a =
            firstContour

        var b =
            secondContour

        if first.pointIndex == 0 {
            a =
                reversedVectorContour(
                    a
                )
        }

        if second.pointIndex
            == secondContour.count - 1
        {
            b =
                reversedVectorContour(
                    b
                )
        }

        guard !a.isEmpty,
              !b.isEmpty
        else {
            return nil
        }

        let merged =
            a + b

        let insertionIndex =
            min(
                first.contourIndex,
                second.contourIndex
            )

        for index in [
            first.contourIndex,
            second.contourIndex
        ]
        .sorted(by: >)
        {
            contours.remove(
                at: index
            )

            closures.remove(
                at: index
            )
        }

        contours.insert(
            merged,
            at: insertionIndex
        )

        closures.insert(
            false,
            at: insertionIndex
        )

        output.pathContours =
            contours

        output.pathPoints =
            contours.first

        output =
            settingVectorContourClosures(
                in: output,
                closures: closures
            )

        let seamA =
            a.count - 1

        let seamB =
            a.count

        let selections:
            Set<CoverVectorAnchorIndex> = [
                CoverVectorAnchorIndex(
                    contourIndex: insertionIndex,
                    pointIndex: seamA
                ),
                CoverVectorAnchorIndex(
                    contourIndex: insertionIndex,
                    pointIndex: seamB
                )
            ]

        return CoverVectorJoinResult(
            layer: output,
            selectedAnchors: selections,
            activeAnchor:
                CoverVectorAnchorIndex(
                    contourIndex: insertionIndex,
                    pointIndex: seamA
                )
        )
    }

    static func splitBoundaryIncomingCopy(
        _ point: CoverPathPoint
    ) -> CoverPathPoint {
        var copy = point

        copy.controlOutX = nil
        copy.controlOutY = nil
        copy.anchorType = .corner

        return copy
    }

    static func splitBoundaryOutgoingCopy(
        _ point: CoverPathPoint
    ) -> CoverPathPoint {
        var copy = point

        copy.controlInX = nil
        copy.controlInY = nil
        copy.anchorType = .corner

        return copy
    }

    static func splittingVectorPath(
        in layer: CoverLayer,
        at anchor: CoverVectorAnchorIndex
    ) -> CoverVectorSplitResult? {
        guard layer.kind == .path else {
            return nil
        }

        var output = layer

        var contours =
            vectorContours(
                for: output
            )

        guard contours.indices.contains(
                anchor.contourIndex
              )
        else {
            return nil
        }

        var closures =
            vectorContourClosures(
                for: output,
                contourCount:
                    contours.count
            )

        let sourceContourIndex =
            anchor.contourIndex

        let contour =
            contours[sourceContourIndex]

        guard contour.count >= 2,
              contour.indices.contains(
                anchor.pointIndex
              )
        else {
            return nil
        }

        let closed =
            closures[sourceContourIndex]

        let splitIndex =
            anchor.pointIndex

        let original =
            contour[splitIndex]

        if closed {
            var opened:
                [CoverPathPoint] = []

            opened.append(
                splitBoundaryOutgoingCopy(
                    original
                )
            )

            if splitIndex + 1 < contour.count {
                opened.append(
                    contentsOf:
                        contour[
                            (splitIndex + 1)
                            ..<
                            contour.count
                        ]
                )
            }

            if splitIndex > 0 {
                opened.append(
                    contentsOf:
                        contour[
                            0
                            ..<
                            splitIndex
                        ]
                )
            }

            opened.append(
                splitBoundaryIncomingCopy(
                    original
                )
            )

            guard opened.count >= 2 else {
                return nil
            }

            contours[sourceContourIndex] =
                opened

            closures[sourceContourIndex] =
                false

            output.pathContours =
                contours

            output.pathPoints =
                contours.first

            output =
                settingVectorContourClosures(
                    in: output,
                    closures: closures
                )

            let first =
                CoverVectorAnchorIndex(
                    contourIndex: sourceContourIndex,
                    pointIndex: 0
                )

            let last =
                CoverVectorAnchorIndex(
                    contourIndex: sourceContourIndex,
                    pointIndex:
                        opened.count - 1
                )

            return CoverVectorSplitResult(
                layer: output,
                selectedAnchors: [
                    first,
                    last
                ],
                activeAnchor: first
            )
        }

        guard splitIndex > 0,
              splitIndex < contour.count - 1
        else {
            return nil
        }

        var firstPiece =
            Array(
                contour[
                    0
                    ..<
                    splitIndex
                ]
            )

        firstPiece.append(
            splitBoundaryIncomingCopy(
                original
            )
        )

        var secondPiece:
            [CoverPathPoint] = [
                splitBoundaryOutgoingCopy(
                    original
                )
            ]

        if splitIndex + 1 < contour.count {
            secondPiece.append(
                contentsOf:
                    contour[
                        (splitIndex + 1)
                        ..<
                        contour.count
                    ]
            )
        }

        guard firstPiece.count >= 2,
              secondPiece.count >= 2
        else {
            return nil
        }

        contours.remove(
            at: sourceContourIndex
        )

        closures.remove(
            at: sourceContourIndex
        )

        contours.insert(
            secondPiece,
            at: sourceContourIndex
        )

        contours.insert(
            firstPiece,
            at: sourceContourIndex
        )

        closures.insert(
            false,
            at: sourceContourIndex
        )

        closures.insert(
            false,
            at: sourceContourIndex
        )

        output.pathContours =
            contours

        output.pathPoints =
            contours.first

        output =
            settingVectorContourClosures(
                in: output,
                closures: closures
            )

        let firstBoundary =
            CoverVectorAnchorIndex(
                contourIndex: sourceContourIndex,
                pointIndex:
                    firstPiece.count - 1
            )

        let secondBoundary =
            CoverVectorAnchorIndex(
                contourIndex:
                    sourceContourIndex + 1,
                pointIndex: 0
            )

        return CoverVectorSplitResult(
            layer: output,
            selectedAnchors: [
                firstBoundary,
                secondBoundary
            ],
            activeAnchor:
                firstBoundary
        )
    }

    static func cuttingVectorPath(
        in layer: CoverLayer,
        first: CoverVectorAnchorIndex,
        second: CoverVectorAnchorIndex
    ) -> CoverVectorSplitResult? {
        guard layer.kind == .path,
              first != second,
              first.contourIndex
                == second.contourIndex
        else {
            return nil
        }

        var output = layer

        var contours =
            vectorContours(
                for: output
            )

        guard contours.indices.contains(
                first.contourIndex
              )
        else {
            return nil
        }

        var closures =
            vectorContourClosures(
                for: output,
                contourCount:
                    contours.count
            )

        let sourceContourIndex =
            first.contourIndex

        let contour =
            contours[sourceContourIndex]

        guard contour.count >= 2,
              contour.indices.contains(
                first.pointIndex
              ),
              contour.indices.contains(
                second.pointIndex
              )
        else {
            return nil
        }

        let low =
            min(
                first.pointIndex,
                second.pointIndex
            )

        let high =
            max(
                first.pointIndex,
                second.pointIndex
            )

        guard low < high else {
            return nil
        }

        let closed =
            closures[sourceContourIndex]

        let lowPoint =
            contour[low]

        let highPoint =
            contour[high]

        var pieces:
            [[CoverPathPoint]] = []

        var localSelections:
            [(piece: Int, point: Int)] = []

        func appendPiece(
            _ piece: [CoverPathPoint],
            selectFirst: Bool,
            selectLast: Bool
        ) {
            guard piece.count >= 2 else {
                return
            }

            let pieceIndex =
                pieces.count

            pieces.append(
                piece
            )

            if selectFirst {
                localSelections.append(
                    (
                        piece: pieceIndex,
                        point: 0
                    )
                )
            }

            if selectLast {
                localSelections.append(
                    (
                        piece: pieceIndex,
                        point:
                            piece.count - 1
                    )
                )
            }
        }

        if closed {
            var firstPiece:
                [CoverPathPoint] = [
                    splitBoundaryOutgoingCopy(
                        lowPoint
                    )
                ]

            if low + 1 < high {
                firstPiece.append(
                    contentsOf:
                        contour[
                            (low + 1)
                            ..<
                            high
                        ]
                )
            }

            firstPiece.append(
                splitBoundaryIncomingCopy(
                    highPoint
                )
            )

            var secondPiece:
                [CoverPathPoint] = [
                    splitBoundaryOutgoingCopy(
                        highPoint
                    )
                ]

            if high + 1 < contour.count {
                secondPiece.append(
                    contentsOf:
                        contour[
                            (high + 1)
                            ..<
                            contour.count
                        ]
                )
            }

            if low > 0 {
                secondPiece.append(
                    contentsOf:
                        contour[
                            0
                            ..<
                            low
                        ]
                )
            }

            secondPiece.append(
                splitBoundaryIncomingCopy(
                    lowPoint
                )
            )

            appendPiece(
                firstPiece,
                selectFirst: true,
                selectLast: true
            )

            appendPiece(
                secondPiece,
                selectFirst: true,
                selectLast: true
            )
        } else {
            if low > 0 {
                var prefix =
                    Array(
                        contour[
                            0
                            ..<
                            low
                        ]
                    )

                prefix.append(
                    splitBoundaryIncomingCopy(
                        lowPoint
                    )
                )

                appendPiece(
                    prefix,
                    selectFirst: false,
                    selectLast: true
                )
            }

            var middle:
                [CoverPathPoint] = [
                    splitBoundaryOutgoingCopy(
                        lowPoint
                    )
                ]

            if low + 1 < high {
                middle.append(
                    contentsOf:
                        contour[
                            (low + 1)
                            ..<
                            high
                        ]
                )
            }

            middle.append(
                splitBoundaryIncomingCopy(
                    highPoint
                )
            )

            appendPiece(
                middle,
                selectFirst: true,
                selectLast: true
            )

            if high < contour.count - 1 {
                var suffix:
                    [CoverPathPoint] = [
                        splitBoundaryOutgoingCopy(
                            highPoint
                        )
                    ]

                suffix.append(
                    contentsOf:
                        contour[
                            (high + 1)
                            ..<
                            contour.count
                        ]
                )

                appendPiece(
                    suffix,
                    selectFirst: true,
                    selectLast: false
                )
            }

            guard pieces.count >= 2 else {
                return nil
            }
        }

        guard !pieces.isEmpty else {
            return nil
        }

        contours.remove(
            at: sourceContourIndex
        )

        closures.remove(
            at: sourceContourIndex
        )

        for (
            offset,
            piece
        ) in pieces.enumerated() {
            contours.insert(
                piece,
                at:
                    sourceContourIndex
                    + offset
            )

            closures.insert(
                false,
                at:
                    sourceContourIndex
                    + offset
            )
        }

        output.pathContours =
            contours

        output.pathPoints =
            contours.first

        output =
            settingVectorContourClosures(
                in: output,
                closures: closures
            )

        let selected =
            Set(
                localSelections.map {
                    value in

                    CoverVectorAnchorIndex(
                        contourIndex:
                            sourceContourIndex
                            + value.piece,
                        pointIndex:
                            value.point
                    )
                }
            )

        guard let active =
            selected.sorted(
                by: {
                    lhs,
                    rhs in

                    if lhs.contourIndex
                        == rhs.contourIndex
                    {
                        return lhs.pointIndex
                            < rhs.pointIndex
                    }

                    return lhs.contourIndex
                        < rhs.contourIndex
                }
            )
            .first
        else {
            return nil
        }

        return CoverVectorSplitResult(
            layer: output,
            selectedAnchors: selected,
            activeAnchor: active
        )
    }





    static func replacingVectorContour(
        in layer: CoverLayer,
        contourIndex: Int,
        points: [CoverPathPoint]
    ) -> CoverLayer {
        var output = layer

        var contours =
            vectorContours(
                for: output
            )

        guard contours.indices.contains(
            contourIndex
        ) else {
            return output
        }

        let closures =
            vectorContourClosures(
                for: output,
                contourCount:
                    contours.count
            )

        contours[
            contourIndex
        ] = points

        if output.pathContours != nil
            || contours.count > 1
        {
            output.pathContours =
                contours
        }

        output.pathPoints =
            contours.first
            ?? []

        output =
            settingVectorContourClosures(
                in: output,
                closures: closures
            )

        return output
    }

    static func deletingVectorPoint(
        in layer: CoverLayer,
        contourIndex: Int,
        pointIndex: Int
    ) -> CoverLayer {
        var output = layer

        var contours =
            vectorContours(
                for: output
            )

        guard contours.indices.contains(
            contourIndex
        ) else {
            return output
        }

        var closures =
            vectorContourClosures(
                for: output,
                contourCount:
                    contours.count
            )

        let remaining =
            removedPathPoint(
                contours[
                    contourIndex
                ],
                index:
                    pointIndex
            )

        if contours.count == 1 {
            contours[0] =
                remaining

            output.pathPoints =
                remaining

            if output.pathContours != nil {
                output.pathContours =
                    contours
            }

            if remaining.count < 3 {
                closures[0] =
                    false
            }

            output =
                settingVectorContourClosures(
                    in: output,
                    closures: closures
                )

            return output
        }

        if remaining.count < 3 {
            contours.remove(
                at: contourIndex
            )

            closures.remove(
                at: contourIndex
            )
        } else {
            contours[
                contourIndex
            ] = remaining
        }

        guard !contours.isEmpty else {
            output.pathPoints = []
            output.pathContours = []
            output.pathContourClosed = []
            output.pathClosed = false
            return output
        }

        output.pathContours =
            contours

        output.pathPoints =
            contours[0]

        output =
            settingVectorContourClosures(
                in: output,
                closures: closures
            )

        return output
    }



    static func vectorCompoundPath(
        contours:[[CoverPathPoint]],
        in rect:NSRect,
        closures:[Bool]
    )->NSBezierPath {
        let compound=NSBezierPath()
        compound.windingRule = .evenOdd

        for (
            index,
            contour
        ) in contours.enumerated()
        where !contour.isEmpty
        {
            let closed =
                closures.indices.contains(
                    index
                )
                ? closures[index]
                : false

            compound.append(
                vectorPath(
                    points:contour,
                    in:rect,
                    closed:closed
                )
            )
        }

        return compound
    }

    static func vectorCompoundPath(
        contours:[[CoverPathPoint]],
        in rect:NSRect,
        closed:Bool
    )->NSBezierPath {
        vectorCompoundPath(
            contours:contours,
            in:rect,
            closures:
                Array(
                    repeating:
                        closed,
                    count:
                        contours.count
                )
        )
    }

    private static func booleanCanvasPoint(
        _ point:CoverPathPoint,
        layer:CoverLayer,
        project:CoverProject,
        control:(x:Double,y:Double)? = nil
    )->CGPoint {
        var localX=control?.x ?? point.x
        var localY=control?.y ?? point.y

        if layer.flipHorizontal {
            localX=1-localX
        }

        if layer.flipVertical {
            localY=1-localY
        }

        let width=max(
            0.0000001,
            project.canvasWidth
        )

        let height=max(
            0.0000001,
            project.canvasHeight
        )

        var x =
            (
                layer.frame.x +
                localX*layer.frame.width
            ) * width

        var y =
            (
                layer.frame.y +
                localY*layer.frame.height
            ) * height

        if abs(layer.rotation)>0.0000001 {
            let centerX =
                (
                    layer.frame.x +
                    layer.frame.width/2
                ) * width

            let centerY =
                (
                    layer.frame.y +
                    layer.frame.height/2
                ) * height

            let radians =
                layer.rotation *
                .pi /
                180

            let dx=x-centerX
            let dy=y-centerY

            let rotatedX =
                dx*cos(radians) -
                dy*sin(radians)

            let rotatedY =
                dx*sin(radians) +
                dy*cos(radians)

            x=centerX+rotatedX
            y=centerY+rotatedY
        }

        return CGPoint(
            x:x,
            y:y
        )
    }

    static func vectorProjectPath(
        layer:CoverLayer,
        project:CoverProject
    )->Path? {
        let contours=vectorContours(
            for:layer
        )

        guard layer.kind == .path,
              (
                  layer.pathClosed ??
                  ((contours.first?.count ?? 0) > 2)
              ),
              !contours.isEmpty,
              abs(layer.skewX ?? 0)<0.0000001,
              abs(layer.skewY ?? 0)<0.0000001
        else {
            return nil
        }

        var result=Path()

        for contour in contours {
            guard let first=contour.first,
                  contour.count>=3
            else {
                continue
            }

            result.move(
                to:booleanCanvasPoint(
                    first,
                    layer:layer,
                    project:project
                )
            )

            func appendSegment(
                _ from:CoverPathPoint,
                _ to:CoverPathPoint
            ) {
                let destination =
                    booleanCanvasPoint(
                        to,
                        layer:layer,
                        project:project
                    )

                if vectorSegmentIsCurved(
                    from,
                    to
                ) {
                    let firstControl =
                        booleanCanvasPoint(
                            from,
                            layer:layer,
                            project:project,
                            control:(
                                from.controlOutX ?? from.x,
                                from.controlOutY ?? from.y
                            )
                        )

                    let secondControl =
                        booleanCanvasPoint(
                            to,
                            layer:layer,
                            project:project,
                            control:(
                                to.controlInX ?? to.x,
                                to.controlInY ?? to.y
                            )
                        )

                    result.addCurve(
                        to:destination,
                        control1:firstControl,
                        control2:secondControl
                    )
                } else {
                    result.addLine(
                        to:destination
                    )
                }
            }

            for index in 1..<contour.count {
                appendSegment(
                    contour[index-1],
                    contour[index]
                )
            }

            appendSegment(
                contour[contour.count-1],
                first
            )

            result.closeSubpath()
        }

        return result
    }

    private static func vectorBooleanContours(
        from path:Path,
        bounds:CGRect
    )->[[CoverPathPoint]] {
        guard bounds.width>0.0000001,
              bounds.height>0.0000001
        else {
            return []
        }

        func local(
            _ point:CGPoint
        )->CGPoint {
            CGPoint(
                x:
                    (
                        point.x -
                        bounds.minX
                    ) /
                    bounds.width,
                y:
                    (
                        point.y -
                        bounds.minY
                    ) /
                    bounds.height
            )
        }

        func absolute(
            _ point:CoverPathPoint
        )->CGPoint {
            CGPoint(
                x:
                    bounds.minX +
                    point.x*bounds.width,
                y:
                    bounds.minY +
                    point.y*bounds.height
            )
        }

        func newPoint(
            _ point:CGPoint
        )->CoverPathPoint {
            let value=local(point)

            return CoverPathPoint(
                x:Double(value.x),
                y:Double(value.y)
            )
        }

        var contours:[[CoverPathPoint]]=[]
        var current:[CoverPathPoint]=[]

        func finishContour() {
            guard current.count>=3 else {
                current=[]
                return
            }

            if current.count>3,
               let first=current.first,
               let last=current.last,
               hypot(
                   first.x-last.x,
                   first.y-last.y
               )<0.0000001
            {
                current.removeLast()
            }

            if current.count>=3 {
                contours.append(current)
            }

            current=[]
        }

        path.forEach {
            element in

            switch element {
            case .move(to:let destination):
                finishContour()
                current=[newPoint(destination)]

            case .line(to:let destination):
                if current.isEmpty {
                    current=[newPoint(destination)]
                } else {
                    current.append(
                        newPoint(destination)
                    )
                }

            case .quadCurve(
                to:let destination,
                control:let control
            ):
                guard let previous=current.last else {
                    current=[newPoint(destination)]
                    return
                }

                let start=absolute(previous)

                let firstControl=CGPoint(
                    x:
                        start.x +
                        (
                            control.x-start.x
                        ) * 2/3,
                    y:
                        start.y +
                        (
                            control.y-start.y
                        ) * 2/3
                )

                let secondControl=CGPoint(
                    x:
                        destination.x +
                        (
                            control.x-destination.x
                        ) * 2/3,
                    y:
                        destination.y +
                        (
                            control.y-destination.y
                        ) * 2/3
                )

                let firstLocal=local(
                    firstControl
                )

                current[current.count-1]
                    .controlOutX =
                        Double(firstLocal.x)

                current[current.count-1]
                    .controlOutY =
                        Double(firstLocal.y)

                var next=newPoint(
                    destination
                )

                let secondLocal=local(
                    secondControl
                )

                next.controlInX =
                    Double(secondLocal.x)

                next.controlInY =
                    Double(secondLocal.y)

                current.append(next)

            case .curve(
                to:let destination,
                control1:let control1,
                control2:let control2
            ):
                guard !current.isEmpty else {
                    current=[newPoint(destination)]
                    return
                }

                let firstLocal=local(
                    control1
                )

                current[current.count-1]
                    .controlOutX =
                        Double(firstLocal.x)

                current[current.count-1]
                    .controlOutY =
                        Double(firstLocal.y)

                var next=newPoint(
                    destination
                )

                let secondLocal=local(
                    control2
                )

                next.controlInX =
                    Double(secondLocal.x)

                next.controlInY =
                    Double(secondLocal.y)

                current.append(next)

            case .closeSubpath:
                finishContour()
            }
        }

        finishContour()

        return contours
    }

    static func booleanPathLayer(
        project:CoverProject,
        ids:Set<UUID>,
        primaryID:UUID,
        operation:CoverVectorBooleanOperation
    )->CoverLayer? {
        if #available(macOS 14.0,*) {
            guard ids.count>=2,
                  let primary =
                    project.layers.first(
                        where:{
                            $0.id==primaryID &&
                            ids.contains($0.id)
                        }
                    )
            else {
                return nil
            }

            let selected =
                project.layers.filter {
                    ids.contains($0.id)
                }

            guard selected.count>=2,
                  selected.allSatisfy({
                      let contours =
                          vectorContours(
                              for:$0
                          )

                      return
                          $0.kind == .path &&
                          (
                              $0.pathClosed ??
                              ((contours.first?.count ?? 0) > 2)
                          ) &&
                          !contours.isEmpty &&
                          abs($0.skewX ?? 0)<0.0000001 &&
                          abs($0.skewY ?? 0)<0.0000001
                  }),
                  var result =
                    vectorProjectPath(
                        layer:primary,
                        project:project
                    )
            else {
                return nil
            }

            let operands =
                selected.filter {
                    $0.id != primaryID
                }

            for layer in operands {
                guard let operand =
                    vectorProjectPath(
                        layer:layer,
                        project:project
                    )
                else {
                    return nil
                }

                switch operation {
                case .union:
                    result=result.union(
                        operand,
                        eoFill:true
                    )

                case .subtract:
                    result=result.subtracting(
                        operand,
                        eoFill:true
                    )

                case .intersect:
                    result=result.intersection(
                        operand,
                        eoFill:true
                    )

                case .exclude:
                    result=result.symmetricDifference(
                        operand,
                        eoFill:true
                    )
                }
            }

            let bounds=result.boundingRect

            guard !bounds.isNull,
                  !bounds.isEmpty,
                  bounds.width>0.0000001,
                  bounds.height>0.0000001,
                  project.canvasWidth>0,
                  project.canvasHeight>0
            else {
                return nil
            }

            let contours=vectorBooleanContours(
                from:result,
                bounds:bounds
            )

            guard !contours.isEmpty else {
                return nil
            }

            var output=primary

            output.id=UUID()
            output.name="\(operation.title) Path"
            output.kind = .path

            output.frame=CoverRect(
                x:
                    Double(bounds.minX) /
                    project.canvasWidth,
                y:
                    Double(bounds.minY) /
                    project.canvasHeight,
                width:
                    Double(bounds.width) /
                    project.canvasWidth,
                height:
                    Double(bounds.height) /
                    project.canvasHeight
            )

            output.rotation=0
            output.flipHorizontal=false
            output.flipVertical=false
            output.skewX=nil
            output.skewY=nil
            output.pathClosed=true
            output.pathContours=contours
            output.pathPoints=contours.first
            output.locked=false
            output.positionLocked=false

            return output
        } else {
            return nil
        }
    }

    static func separatedVectorPathLayers(
        from layer: CoverLayer
    ) -> [CoverLayer]? {
        guard layer.kind == .path else {
            return nil
        }

        let contours =
            vectorContours(
                for: layer
            )

        guard contours.count >= 2 else {
            return nil
        }

        let closures =
            vectorContourClosures(
                for: layer,
                contourCount:
                    contours.count
            )

        return contours.enumerated().map {
            index,
            contour in

            var output = layer

            output.id = UUID()

            output.name =
                "\(layer.name) \(index + 1)"

            output.pathPoints =
                contour

            output.pathContours = [
                contour
            ]

            output.pathClosed =
                closures[index]

            output.pathContourClosed = [
                closures[index]
            ]

            return output
        }
    }

    private static func combinedVectorLocalPoint(
        _ canvasPoint: CGPoint,
        destination: CoverLayer,
        project: CoverProject
    ) -> CGPoint? {
        guard project.canvasWidth > 0,
              project.canvasHeight > 0,
              destination.frame.width > 0.0000001,
              destination.frame.height > 0.0000001
        else {
            return nil
        }

        return CGPoint(
            x:
                (
                    Double(canvasPoint.x)
                    / project.canvasWidth
                    - destination.frame.x
                )
                / destination.frame.width,
            y:
                (
                    Double(canvasPoint.y)
                    / project.canvasHeight
                    - destination.frame.y
                )
                / destination.frame.height
        )
    }

    private static func combinedVectorPathPoint(
        _ point: CoverPathPoint,
        source: CoverLayer,
        destination: CoverLayer,
        project: CoverProject
    ) -> CoverPathPoint? {
        let anchorCanvas =
            booleanCanvasPoint(
                point,
                layer:
                    source,
                project:
                    project
            )

        guard let anchor =
            combinedVectorLocalPoint(
                anchorCanvas,
                destination:
                    destination,
                project:
                    project
            )
        else {
            return nil
        }

        var output = point

        output.x =
            Double(anchor.x)

        output.y =
            Double(anchor.y)

        if point.controlInX != nil
            || point.controlInY != nil
        {
            let controlCanvas =
                booleanCanvasPoint(
                    point,
                    layer:
                        source,
                    project:
                        project,
                    control:(
                        point.controlInX
                            ?? point.x,
                        point.controlInY
                            ?? point.y
                    )
                )

            guard let control =
                combinedVectorLocalPoint(
                    controlCanvas,
                    destination:
                        destination,
                    project:
                        project
                )
            else {
                return nil
            }

            output.controlInX =
                Double(control.x)

            output.controlInY =
                Double(control.y)
        } else {
            output.controlInX = nil
            output.controlInY = nil
        }

        if point.controlOutX != nil
            || point.controlOutY != nil
        {
            let controlCanvas =
                booleanCanvasPoint(
                    point,
                    layer:
                        source,
                    project:
                        project,
                    control:(
                        point.controlOutX
                            ?? point.x,
                        point.controlOutY
                            ?? point.y
                    )
                )

            guard let control =
                combinedVectorLocalPoint(
                    controlCanvas,
                    destination:
                        destination,
                    project:
                        project
                )
            else {
                return nil
            }

            output.controlOutX =
                Double(control.x)

            output.controlOutY =
                Double(control.y)
        } else {
            output.controlOutX = nil
            output.controlOutY = nil
        }

        return output
    }

    private static func selectionRasterPathPoint(
        _ point: CoverPathPoint
    ) -> CoverPathPoint {
        /*
         combinedVectorPathPoint returns target-local coordinates in
         BOLD Writer's top-down canvas convention.

         vectorPath stores Y in the opposite path convention and maps it
         with (1 - y), so convert once here.  This prevents a second
         inversion while still reusing vectorCompoundPath exactly.
        */
        var output = point

        output.y =
            1 - point.y

        if let value =
            point.controlInY
        {
            output.controlInY =
                1 - value
        }

        if let value =
            point.controlOutY
        {
            output.controlOutY =
                1 - value
        }

        return output
    }

    static func selectionFromVectorPath(
        layer: CoverLayer,
        project: CoverProject,
        targetLayer: CoverLayer,
        width: Int,
        height: Int,
        antialias: Bool = true
    ) -> Data? {
        guard layer.kind == .path,
              width > 0,
              height > 0,
              width <= 20_000,
              height <= 20_000,
              project.canvasWidth > 0,
              project.canvasHeight > 0,
              targetLayer.frame.width > 0.0000001,
              targetLayer.frame.height > 0.0000001,
              abs(layer.skewX ?? 0)
                < 0.0000001,
              abs(layer.skewY ?? 0)
                < 0.0000001,
              abs(targetLayer.rotation)
                < 0.0000001,
              targetLayer.flipHorizontal == false,
              targetLayer.flipVertical == false,
              abs(targetLayer.skewX ?? 0)
                < 0.0000001,
              abs(targetLayer.skewY ?? 0)
                < 0.0000001
        else {
            return nil
        }

        let contours =
            vectorContours(
                for:
                    layer
            )

        guard !contours.isEmpty else {
            return nil
        }

        let closures =
            vectorContourClosures(
                for:
                    layer,
                contourCount:
                    contours.count
            )

        var closedContours:
            [[CoverPathPoint]] = []

        for (
            contourIndex,
            contour
        ) in contours.enumerated()
        where closures[
            contourIndex
        ] && contour.count >= 3 {
            var mapped:
                [CoverPathPoint] = []

            mapped.reserveCapacity(
                contour.count
            )

            for point in contour {
                guard let converted =
                    combinedVectorPathPoint(
                        point,
                        source:
                            layer,
                        destination:
                            targetLayer,
                        project:
                            project
                    )
                else {
                    return nil
                }

                mapped.append(
                    selectionRasterPathPoint(
                        converted
                    )
                )
            }

            closedContours.append(
                mapped
            )
        }

        guard !closedContours.isEmpty else {
            return nil
        }

        let selectionPath =
            vectorCompoundPath(
                contours:
                    closedContours,
                in:
                    NSRect(
                        x: 0,
                        y: 0,
                        width:
                            width,
                        height:
                            height
                    ),
                closures:
                    Array(
                        repeating:
                            true,
                        count:
                            closedContours.count
                    )
            )


        configureVectorFillRule(
            selectionPath,
            layer:
                layer
        )

        let bounds =
            selectionPath.bounds

        var values =
            [UInt8](
                repeating:
                    0,
                count:
                    width * height
            )

        guard !bounds.isEmpty else {
            return Data(
                values
            )
        }

        let minX =
            max(
                0,
                Int(
                    floor(
                        bounds.minX
                    )
                ) - 1
            )

        let minY =
            max(
                0,
                Int(
                    floor(
                        bounds.minY
                    )
                ) - 1
            )

        let maxX =
            min(
                width - 1,
                Int(
                    ceil(
                        bounds.maxX
                    )
                ) + 1
            )

        let maxY =
            min(
                height - 1,
                Int(
                    ceil(
                        bounds.maxY
                    )
                ) + 1
            )

        guard minX <= maxX,
              minY <= maxY
        else {
            return Data(
                values
            )
        }

        let samples =
            antialias
            ? 4
            : 1

        let totalSamples =
            samples * samples

        for y in minY...maxY {
            for x in minX...maxX {
                var hits = 0

                for sampleY in 0..<samples {
                    for sampleX in 0..<samples {
                        let point =
                            NSPoint(
                                x:
                                    Double(x)
                                    + (
                                        Double(
                                            sampleX
                                        )
                                        + 0.5
                                    )
                                    / Double(
                                        samples
                                    ),
                                y:
                                    Double(y)
                                    + (
                                        Double(
                                            sampleY
                                        )
                                        + 0.5
                                    )
                                    / Double(
                                        samples
                                    )
                            )

                        if selectionPath.contains(
                            point
                        ) {
                            hits += 1
                        }
                    }
                }

                values[
                    y * width + x
                ] =
                    UInt8(
                        hits * 255
                        / totalSamples
                    )
            }
        }

        return Data(
            values
        )
    }

    private struct CoverSelectionBoundaryEdge:
        Hashable
    {
        let start: Int
        let end: Int
    }

    private static func selectionBoundaryDirection(
        _ edge: CoverSelectionBoundaryEdge,
        vertexWidth: Int
    ) -> Int {
        let startX =
            edge.start
            % vertexWidth

        let startY =
            edge.start
            / vertexWidth

        let endX =
            edge.end
            % vertexWidth

        let endY =
            edge.end
            / vertexWidth

        let dx =
            endX - startX

        let dy =
            endY - startY

        if dx == 1 {
            return 0
        }

        if dy == 1 {
            return 1
        }

        if dx == -1 {
            return 2
        }

        return 3
    }

    private static func selectionBoundaryTurnRank(
        incoming: Int,
        outgoing: Int
    ) -> Int {
        let delta =
            (
                outgoing
                - incoming
                + 4
            )
            % 4

        switch delta {
        case 1:
            return 0
        case 0:
            return 1
        case 3:
            return 2
        default:
            return 3
        }
    }

    private static func simplifiedSelectionBoundary(
        _ vertices: [Int],
        vertexWidth: Int
    ) -> [Int] {
        guard vertices.count >= 3 else {
            return vertices
        }

        var points:
            [Int] = []

        points.reserveCapacity(
            vertices.count
        )

        for vertex in vertices {
            if points.last != vertex {
                points.append(
                    vertex
                )
            }
        }

        if points.count > 1,
           points.first == points.last
        {
            points.removeLast()
        }

        guard points.count >= 3 else {
            return points
        }

        var changed = true

        while changed,
              points.count >= 3
        {
            changed = false

            var reduced:
                [Int] = []

            reduced.reserveCapacity(
                points.count
            )

            for index in points.indices {
                let previous =
                    points[
                        (
                            index
                            + points.count
                            - 1
                        )
                        % points.count
                    ]

                let current =
                    points[index]

                let next =
                    points[
                        (
                            index
                            + 1
                        )
                        % points.count
                    ]

                let previousX =
                    previous
                    % vertexWidth

                let previousY =
                    previous
                    / vertexWidth

                let currentX =
                    current
                    % vertexWidth

                let currentY =
                    current
                    / vertexWidth

                let nextX =
                    next
                    % vertexWidth

                let nextY =
                    next
                    / vertexWidth

                let horizontal =
                    previousY == currentY
                    && currentY == nextY

                let vertical =
                    previousX == currentX
                    && currentX == nextX

                if horizontal
                    || vertical
                {
                    changed = true
                    continue
                }

                reduced.append(
                    current
                )
            }

            guard reduced.count >= 3 else {
                break
            }

            points =
                reduced
        }

        return points
    }

    static func vectorContoursFromSelection(
        _ selection: Data,
        width: Int,
        height: Int,
        threshold: UInt8 = 128
    ) -> [[CoverPathPoint]]? {
        guard width > 0,
              height > 0,
              width <= 20_000,
              height <= 20_000,
              selection.count
                == width * height
        else {
            return nil
        }

        func isSelected(
            _ x: Int,
            _ y: Int
        ) -> Bool {
            guard x >= 0,
                  y >= 0,
                  x < width,
                  y < height
            else {
                return false
            }

            return selection[
                y * width + x
            ] >= threshold
        }

        guard selection.contains(
            where: {
                $0 >= threshold
            }
        ) else {
            return nil
        }

        let vertexWidth =
            width + 1

        func vertex(
            _ x: Int,
            _ y: Int
        ) -> Int {
            y * vertexWidth
            + x
        }

        var edges:
            [CoverSelectionBoundaryEdge] = []

        for y in 0..<height {
            for x in 0..<width
            where isSelected(
                x,
                y
            ) {
                if !isSelected(
                    x,
                    y - 1
                ) {
                    edges.append(
                        CoverSelectionBoundaryEdge(
                            start:
                                vertex(
                                    x,
                                    y
                                ),
                            end:
                                vertex(
                                    x + 1,
                                    y
                                )
                        )
                    )
                }

                if !isSelected(
                    x + 1,
                    y
                ) {
                    edges.append(
                        CoverSelectionBoundaryEdge(
                            start:
                                vertex(
                                    x + 1,
                                    y
                                ),
                            end:
                                vertex(
                                    x + 1,
                                    y + 1
                                )
                        )
                    )
                }

                if !isSelected(
                    x,
                    y + 1
                ) {
                    edges.append(
                        CoverSelectionBoundaryEdge(
                            start:
                                vertex(
                                    x + 1,
                                    y + 1
                                ),
                            end:
                                vertex(
                                    x,
                                    y + 1
                                )
                        )
                    )
                }

                if !isSelected(
                    x - 1,
                    y
                ) {
                    edges.append(
                        CoverSelectionBoundaryEdge(
                            start:
                                vertex(
                                    x,
                                    y + 1
                                ),
                            end:
                                vertex(
                                    x,
                                    y
                                )
                        )
                    )
                }
            }
        }

        guard !edges.isEmpty else {
            return nil
        }

        var outgoing:
            [Int: [Int]] = [:]

        outgoing.reserveCapacity(
            edges.count
        )

        for (
            index,
            edge
        ) in edges.enumerated() {
            outgoing[
                edge.start,
                default:
                    []
            ].append(
                index
            )
        }

        var used =
            [Bool](
                repeating:
                    false,
                count:
                    edges.count
            )

        var vertexLoops:
            [[Int]] = []

        vertexLoops.reserveCapacity(
            max(
                1,
                edges.count / 4
            )
        )

        for seedIndex in edges.indices
        where !used[
            seedIndex
        ] {
            let seed =
                edges[
                    seedIndex
                ]

            used[
                seedIndex
            ] = true

            var vertices = [
                seed.start,
                seed.end
            ]

            var current =
                seed.end

            var incomingDirection =
                selectionBoundaryDirection(
                    seed,
                    vertexWidth:
                        vertexWidth
                )

            var walked = 1

            while current
                    != seed.start
            {
                let candidates =
                    (
                        outgoing[
                            current
                        ]
                        ?? []
                    )
                    .filter {
                        !used[
                            $0
                        ]
                    }

                guard !candidates.isEmpty else {
                    return nil
                }

                let nextIndex =
                    candidates.min {
                        lhs,
                        rhs in

                        let lhsDirection =
                            selectionBoundaryDirection(
                                edges[
                                    lhs
                                ],
                                vertexWidth:
                                    vertexWidth
                            )

                        let rhsDirection =
                            selectionBoundaryDirection(
                                edges[
                                    rhs
                                ],
                                vertexWidth:
                                    vertexWidth
                            )

                        let lhsRank =
                            selectionBoundaryTurnRank(
                                incoming:
                                    incomingDirection,
                                outgoing:
                                    lhsDirection
                            )

                        let rhsRank =
                            selectionBoundaryTurnRank(
                                incoming:
                                    incomingDirection,
                                outgoing:
                                    rhsDirection
                            )

                        if lhsRank
                            != rhsRank
                        {
                            return lhsRank
                                < rhsRank
                        }

                        if edges[lhs].end
                            != edges[rhs].end
                        {
                            return edges[lhs].end
                                < edges[rhs].end
                        }

                        return lhs < rhs
                    }

                guard let nextIndex else {
                    return nil
                }

                let next =
                    edges[
                        nextIndex
                    ]

                used[
                    nextIndex
                ] = true

                vertices.append(
                    next.end
                )

                incomingDirection =
                    selectionBoundaryDirection(
                        next,
                        vertexWidth:
                            vertexWidth
                    )

                current =
                    next.end

                walked += 1

                guard walked
                        <= edges.count
                else {
                    return nil
                }
            }

            if vertices.last
                == vertices.first
            {
                vertices.removeLast()
            }

            let simplified =
                simplifiedSelectionBoundary(
                    vertices,
                    vertexWidth:
                        vertexWidth
                )

            guard simplified.count >= 3 else {
                return nil
            }

            vertexLoops.append(
                simplified
            )
        }

        guard used.allSatisfy({
            $0
        }),
              !vertexLoops.isEmpty
        else {
            return nil
        }

        var contours:
            [[CoverPathPoint]] = []

        contours.reserveCapacity(
            vertexLoops.count
        )

        for loop in vertexLoops {
            var contour:
                [CoverPathPoint] = []

            contour.reserveCapacity(
                loop.count
            )

            for vertexIndex in loop {
                let rasterX =
                    vertexIndex
                    % vertexWidth

                let rasterY =
                    vertexIndex
                    / vertexWidth

                /*
                 CoverPathPoint stores normalized path coordinates in the
                 editor's normal top-down convention.

                 vectorPath performs the AppKit drawing-space Y inversion
                 later, so Selection → Path must NOT pre-invert raster Y.
                */
                var point =
                    CoverPathPoint(
                        x:
                            Double(
                                rasterX
                            )
                            / Double(
                                width
                            ),
                        y:
                            Double(
                                rasterY
                            )
                            / Double(
                                height
                            )
                    )

                point.anchorType =
                    .corner

                contour.append(
                    point
                )
            }

            contours.append(
                contour
            )
        }

        return contours
    }

    static func vectorPathLayerFromSelection(
        _ selection: Data,
        width: Int,
        height: Int,
        frame: CoverRect,
        name: String = "Selection Path",
        threshold: UInt8 = 128
    ) -> CoverLayer? {
        guard let contours =
            vectorContoursFromSelection(
                selection,
                width:
                    width,
                height:
                    height,
                threshold:
                    threshold
            ),
              !contours.isEmpty
        else {
            return nil
        }

        var layer =
            CoverLayer(
                kind:
                    .path,
                name:
                    name,
                frame:
                    frame
            )

        layer.pathPoints =
            contours.first

        layer.pathContours =
            contours

        layer.pathClosed =
            true

        layer.pathContourClosed =
            Array(
                repeating:
                    true,
                count:
                    contours.count
            )

        layer.fillRule =
            .evenOdd

        layer.rotation = 0
        layer.flipHorizontal = false
        layer.flipVertical = false
        layer.skewX = nil
        layer.skewY = nil

        return layer
    }

    static func insertingSelectionPathLayer(
        in project: CoverProject,
        hostLayerID: UUID,
        selection: Data,
        width: Int,
        height: Int,
        name: String = "Selection Path",
        threshold: UInt8 = 128,
        fillHex: String? = nil,
        strokeHex: String? = nil,
        strokeWidth: Double? = nil
    ) -> (
        project: CoverProject,
        layer: CoverLayer
    )? {
        guard let hostIndex =
            project.layers.firstIndex(
                where: {
                    $0.id
                        == hostLayerID
                }
            ),
              let hostData =
                project.layers[
                    hostIndex
                ]
                .imageData,
              let representation =
                NSBitmapImageRep(
                    data:
                        hostData
                ),
              representation.pixelsWide
                == width,
              representation.pixelsHigh
                == height,
              var layer =
                vectorPathLayerFromSelection(
                    selection,
                    width:
                        width,
                    height:
                        height,
                    frame:
                        project.layers[
                            hostIndex
                        ]
                        .frame,
                    name:
                        name,
                    threshold:
                        threshold
                )
        else {
            return nil
        }

        if let fillHex {
            layer.fillHex =
                fillHex
        }

        if let strokeHex {
            layer.strokeHex =
                strokeHex
        }

        if let strokeWidth {
            layer.strokeWidth =
                strokeWidth
        }

        var output =
            project

        output.layers.insert(
            layer,
            at:
                min(
                    hostIndex + 1,
                    output.layers.count
                )
        )

        return (
            output,
            layer
        )
    }



    static func combinedVectorPathLayer(
        project: CoverProject,
        ids: Set<UUID>,
        primaryID: UUID
    ) -> CoverLayer? {
        guard ids.count >= 2,
              project.canvasWidth > 0,
              project.canvasHeight > 0,
              let primary =
                project.layers.first(
                    where: {
                        $0.id == primaryID
                        && ids.contains($0.id)
                    }
                ),
              primary.kind == .path,
              primary.frame.width > 0.0000001,
              primary.frame.height > 0.0000001
        else {
            return nil
        }

        let selected =
            project.layers.filter {
                ids.contains(
                    $0.id
                )
            }

        guard selected.count == ids.count,
              selected.count >= 2,
              selected.allSatisfy({
                  layer in

                  layer.kind == .path
                  && !vectorContours(
                      for: layer
                  ).isEmpty
                  && layer.frame.width > 0.0000001
                  && layer.frame.height > 0.0000001
                  && abs(layer.skewX ?? 0)
                      < 0.0000001
                  && abs(layer.skewY ?? 0)
                      < 0.0000001
              })
        else {
            return nil
        }

        var combinedContours:
            [[CoverPathPoint]] = []

        var combinedClosures:
            [Bool] = []

        for source in selected {
            let contours =
                vectorContours(
                    for: source
                )

            let closures =
                vectorContourClosures(
                    for: source,
                    contourCount:
                        contours.count
                )

            for (
                contourIndex,
                contour
            ) in contours.enumerated() {
                var transformed:
                    [CoverPathPoint] = []

                transformed.reserveCapacity(
                    contour.count
                )

                for point in contour {
                    guard let mapped =
                        combinedVectorPathPoint(
                            point,
                            source:
                                source,
                            destination:
                                primary,
                            project:
                                project
                        )
                    else {
                        return nil
                    }

                    transformed.append(
                        mapped
                    )
                }

                guard !transformed.isEmpty else {
                    return nil
                }

                combinedContours.append(
                    transformed
                )

                combinedClosures.append(
                    closures[
                        contourIndex
                    ]
                )
            }
        }

        guard !combinedContours.isEmpty,
              combinedContours.count
                == combinedClosures.count
        else {
            return nil
        }

        var output = primary

        output.rotation = 0
        output.flipHorizontal = false
        output.flipVertical = false
        output.skewX = nil
        output.skewY = nil

        output.pathContours =
            combinedContours

        output.pathPoints =
            combinedContours.first

        output =
            settingVectorContourClosures(
                in: output,
                closures:
                    combinedClosures
            )

        return output
    }

    static func combiningVectorPathLayers(
        in project: CoverProject,
        ids: Set<UUID>,
        primaryID: UUID
    ) -> (
        project: CoverProject,
        layer: CoverLayer
    )? {
        guard let combined =
            combinedVectorPathLayer(
                project:
                    project,
                ids:
                    ids,
                primaryID:
                    primaryID
            ),
              let originalIndex =
                project.layers.firstIndex(
                    where: {
                        $0.id == primaryID
                    }
                )
        else {
            return nil
        }

        var output = project

        let insertionIndex =
            output.layers
                .prefix(
                    originalIndex
                )
                .filter {
                    !ids.contains(
                        $0.id
                    )
                }
                .count

        output.layers.removeAll {
            ids.contains(
                $0.id
            )
        }

        output.layers.insert(
            combined,
            at:
                min(
                    insertionIndex,
                    output.layers.count
                )
        )

        return (
            output,
            combined
        )
    }

    static func separatingVectorPathLayer(
        in project: CoverProject,
        layerID: UUID
    ) -> (
        project: CoverProject,
        layers: [CoverLayer]
    )? {
        guard let index =
            project.layers.firstIndex(
                where: {
                    $0.id == layerID
                }
            ),
              let separated =
                separatedVectorPathLayers(
                    from:
                        project.layers[
                            index
                        ]
                )
        else {
            return nil
        }

        var output = project

        output.layers.remove(
            at:
                index
        )

        output.layers.insert(
            contentsOf:
                separated,
            at:
                index
        )

        return (
            output,
            separated
        )
    }


    static func vectorLayerContains(
        _ layer:CoverLayer,
        project:CoverProject,
        normalizedPoint:CGPoint
    )->Bool {
        if #available(macOS 14.0,*) {
            guard let path =
                vectorProjectPath(
                    layer:layer,
                    project:project
                )
            else {
                return false
            }

            return path.contains(
                CGPoint(
                    x:
                        normalizedPoint.x *
                        project.canvasWidth,
                    y:
                        normalizedPoint.y *
                        project.canvasHeight
                ),
                eoFill:
                    vectorFillRule(
                        for:
                            layer
                    ) == .evenOdd
            )
        } else {
            return false
        }
    }

    static func vectorSegmentIsCurved(
        _ from: CoverPathPoint,
        _ to: CoverPathPoint
    ) -> Bool {
        from.controlOutX != nil ||
        from.controlOutY != nil ||
        to.controlInX != nil ||
        to.controlInY != nil
    }

    static func vectorPath(
        points: [CoverPathPoint],
        in rect: NSRect,
        closed: Bool
    ) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }

        func mapped(_ value: CoverPathPoint) -> NSPoint {
            NSPoint(
                x: rect.minX + value.x * rect.width,
                y: rect.minY + (1 - value.y) * rect.height
            )
        }

        func mapped(_ x: Double, _ y: Double) -> NSPoint {
            NSPoint(
                x: rect.minX + x * rect.width,
                y: rect.minY + (1 - y) * rect.height
            )
        }

        func appendSegment(
            _ from: CoverPathPoint,
            _ to: CoverPathPoint
        ) {
            if vectorSegmentIsCurved(from, to) {
                path.curve(
                    to: mapped(to),
                    controlPoint1: mapped(
                        from.controlOutX ?? from.x,
                        from.controlOutY ?? from.y
                    ),
                    controlPoint2: mapped(
                        to.controlInX ?? to.x,
                        to.controlInY ?? to.y
                    )
                )
            } else {
                path.line(to: mapped(to))
            }
        }

        path.move(to: mapped(first))

        if points.count > 1 {
            for index in 1..<points.count {
                appendSegment(
                    points[index - 1],
                    points[index]
                )
            }
        }

        if closed, points.count > 1 {
            appendSegment(
                points[points.count - 1],
                first
            )
            path.close()
        }

        return path
    }

    static func appendedPathPoint(
        _ points: [CoverPathPoint],
        anchor: CGPoint,
        draggedTo: CGPoint? = nil
    ) -> [CoverPathPoint] {
        func clamp(_ value: Double) -> Double {
            max(-4, min(5, value))
        }

        let x = clamp(Double(anchor.x))
        let y = clamp(Double(anchor.y))
        var point = CoverPathPoint(x: x, y: y)

        if let draggedTo {
            let targetX = clamp(Double(draggedTo.x))
            let targetY = clamp(Double(draggedTo.y))
            let dx = targetX - x
            let dy = targetY - y

            if hypot(dx, dy) > 0.0001 {
                point.controlOutX = targetX
                point.controlOutY = targetY
                point.controlInX = clamp(x - dx)
                point.controlInY = clamp(y - dy)
            }
        }

        return points + [point]
    }

    static func movedPathPoint(
        _ points: [CoverPathPoint],
        index: Int,
        to destination: CGPoint
    ) -> [CoverPathPoint] {
        guard points.indices.contains(index) else { return points }

        var result = points
        let oldX = result[index].x
        let oldY = result[index].y
        let newX = max(-4, min(5, Double(destination.x)))
        let newY = max(-4, min(5, Double(destination.y)))
        let dx = newX - oldX
        let dy = newY - oldY

        result[index].x = newX
        result[index].y = newY

        if let value = result[index].controlInX {
            result[index].controlInX = value + dx
        }

        if let value = result[index].controlInY {
            result[index].controlInY = value + dy
        }

        if let value = result[index].controlOutX {
            result[index].controlOutX = value + dx
        }

        if let value = result[index].controlOutY {
            result[index].controlOutY = value + dy
        }

        return result
    }

    static func movedPathControl(
        _ points: [CoverPathPoint],
        index: Int,
        to destination: CGPoint,
        incoming: Bool,
        mirrorOpposite: Bool = false
    ) -> [CoverPathPoint] {
        guard points.indices.contains(
            index
        ) else {
            return points
        }

        var result = points

        let x =
            max(
                -4,
                min(
                    5,
                    Double(
                        destination.x
                    )
                )
            )

        let y =
            max(
                -4,
                min(
                    5,
                    Double(
                        destination.y
                    )
                )
            )

        let anchorX =
            result[index].x

        let anchorY =
            result[index].y

        let oppositeXBefore =
            incoming
            ? result[index].controlOutX
            : result[index].controlInX

        let oppositeYBefore =
            incoming
            ? result[index].controlOutY
            : result[index].controlInY

        let oppositeLengthBefore =
            hypot(
                (
                    oppositeXBefore
                    ?? anchorX
                )
                - anchorX,
                (
                    oppositeYBefore
                    ?? anchorY
                )
                - anchorY
            )

        if incoming {
            result[index].controlInX = x
            result[index].controlInY = y
        } else {
            result[index].controlOutX = x
            result[index].controlOutY = y
        }

        let dx =
            x - anchorX

        let dy =
            y - anchorY

        let draggedLength =
            hypot(
                dx,
                dy
            )

        switch result[index].anchorType {
        case .corner:
            break

        case .smooth:
            guard draggedLength
                    > 0.0000001
            else {
                break
            }

            let oppositeLength =
                oppositeLengthBefore
                    > 0.0000001
                ? oppositeLengthBefore
                : draggedLength

            let unitX =
                dx
                / draggedLength

            let unitY =
                dy
                / draggedLength

            let oppositeX =
                anchorX
                - unitX
                * oppositeLength

            let oppositeY =
                anchorY
                - unitY
                * oppositeLength

            if incoming {
                result[index].controlOutX =
                    oppositeX

                result[index].controlOutY =
                    oppositeY
            } else {
                result[index].controlInX =
                    oppositeX

                result[index].controlInY =
                    oppositeY
            }

        case .symmetric:
            let oppositeX =
                anchorX - dx

            let oppositeY =
                anchorY - dy

            if incoming {
                result[index].controlOutX =
                    oppositeX

                result[index].controlOutY =
                    oppositeY
            } else {
                result[index].controlInX =
                    oppositeX

                result[index].controlInY =
                    oppositeY
            }

        case nil:
            guard mirrorOpposite else {
                break
            }

            let oppositeX =
                anchorX - dx

            let oppositeY =
                anchorY - dy

            if incoming {
                result[index].controlOutX =
                    oppositeX

                result[index].controlOutY =
                    oppositeY
            } else {
                result[index].controlInX =
                    oppositeX

                result[index].controlInY =
                    oppositeY
            }
        }

        return result
    }

    static func removedPathPoint(
        _ points: [CoverPathPoint],
        index: Int
    ) -> [CoverPathPoint] {
        guard points.indices.contains(index) else { return points }

        var result = points
        result.remove(at: index)
        return result
    }


    static func linkableLayerIDs(
        _ layers: [CoverLayer],
        ids: Set<UUID>
    ) -> Set<UUID> {
        Set(
            layers
                .filter {
                    ids.contains($0.id)
                    && !$0.isReferenceLayer
                    && $0.kind != .group
                    && $0.kind != .adjustment
                }
                .map(\.id)
        )
    }

    static func linkedLayerIDs(
        _ layers: [CoverLayer],
        layerID: UUID
    ) -> Set<UUID> {
        guard let source = layers.first(where: { $0.id == layerID })
        else {
            return []
        }

        guard let linkSetID = source.linkSetID
        else {
            return [layerID]
        }

        return Set(
            layers
                .filter { $0.linkSetID == linkSetID }
                .map(\.id)
        )
    }

    static func effectiveLinkedLayerIDs(
        _ layers: [CoverLayer],
        ids: Set<UUID>
    ) -> Set<UUID> {
        guard !ids.isEmpty else {
            return []
        }

        var result = ids

        let touchedSets = Set(
            layers
                .filter { ids.contains($0.id) }
                .compactMap(\.linkSetID)
        )

        if !touchedSets.isEmpty {
            for layer in layers
            where layer.linkSetID.map(touchedSets.contains) == true
            {
                result.insert(layer.id)
            }
        }

        return result
    }

    static func normalizeLayerLinks(
        _ layers: inout [CoverLayer]
    ) {
        var counts: [UUID: Int] = [:]

        for layer in layers {
            if let linkSetID = layer.linkSetID {
                counts[linkSetID, default: 0] += 1
            }
        }

        for index in layers.indices {
            guard let linkSetID = layers[index].linkSetID
            else {
                continue
            }

            if counts[linkSetID, default: 0] < 2 {
                layers[index].linkSetID = nil
            }
        }
    }

    @discardableResult
    static func linkLayers(
        _ layers: inout [CoverLayer],
        ids: Set<UUID>,
        linkSetID requestedLinkSetID: UUID? = nil
    ) -> UUID? {
        let eligible = linkableLayerIDs(
            layers,
            ids: ids
        )

        guard eligible.count >= 2
        else {
            return nil
        }

        let touchedSets = Set(
            layers
                .filter { eligible.contains($0.id) }
                .compactMap(\.linkSetID)
        )

        var mergedIDs = eligible

        if !touchedSets.isEmpty {
            for layer in layers
            where layer.linkSetID.map(touchedSets.contains) == true
            {
                if !layer.isReferenceLayer,
                   layer.kind != .group,
                   layer.kind != .adjustment
                {
                    mergedIDs.insert(layer.id)
                }
            }
        }

        guard mergedIDs.count >= 2
        else {
            return nil
        }

        let newLinkSetID = requestedLinkSetID ?? UUID()

        for index in layers.indices
        where mergedIDs.contains(layers[index].id)
        {
            layers[index].linkSetID = newLinkSetID
        }

        normalizeLayerLinks(&layers)

        return newLinkSetID
    }

    static func unlinkLayers(
        _ layers: inout [CoverLayer],
        ids: Set<UUID>
    ) {
        guard !ids.isEmpty else {
            return
        }

        for index in layers.indices
        where ids.contains(layers[index].id)
        {
            layers[index].linkSetID = nil
        }

        normalizeLayerLinks(&layers)
    }

    @discardableResult
    static func duplicateLinkedLayers(
        _ layers: inout [CoverLayer],
        ids: Set<UUID>,
        offsetX: Double = 0.03,
        offsetY: Double = 0.03
    ) -> Set<UUID> {
        let sources = layers.filter {
            ids.contains($0.id)
        }

        guard !sources.isEmpty else {
            return []
        }

        var selectedCounts: [UUID: Int] = [:]

        for layer in sources {
            if let linkSetID = layer.linkSetID {
                selectedCounts[linkSetID, default: 0] += 1
            }
        }

        var freshSets: [UUID: UUID] = [:]

        for (oldSet, count) in selectedCounts
        where count >= 2
        {
            freshSets[oldSet] = UUID()
        }

        var copies: [CoverLayer] = []
        var copiedIDs: Set<UUID> = []

        for source in sources {
            var copy = source

            copy.id = UUID()
            copy.name += " Copy"

            copy.frame.x = min(
                1 - copy.frame.width,
                copy.frame.x + offsetX
            )

            copy.frame.y = min(
                1 - copy.frame.height,
                copy.frame.y + offsetY
            )

            if let oldSet = source.linkSetID,
               let newSet = freshSets[oldSet]
            {
                copy.linkSetID = newSet
            } else {
                copy.linkSetID = nil
            }

            copiedIDs.insert(copy.id)
            copies.append(copy)
        }

        layers.append(contentsOf: copies)
        normalizeLayerLinks(&layers)

        return copiedIDs
    }

    static func flipLayers(
        _ layers: inout [CoverLayer],
        ids: Set<UUID>,
        around center: Double,
        horizontal: Bool
    ) {
        guard center.isFinite else {
            return
        }

        for index in layers.indices
        where ids.contains(layers[index].id)
            && !layers[index].locked
            && layers[index].positionLocked != true
        {
            if horizontal {
                layers[index].frame.x =
                    2 * center
                    - layers[index].frame.x
                    - layers[index].frame.width

                layers[index].flipHorizontal.toggle()
            } else {
                layers[index].frame.y =
                    2 * center
                    - layers[index].frame.y
                    - layers[index].frame.height

                layers[index].flipVertical.toggle()
            }
        }
    }

    static func moveLayers(_ layers:inout [CoverLayer],ids:Set<UUID>,dx:Double,dy:Double){for i in layers.indices where ids.contains(layers[i].id){move(&layers[i],dx:dx,dy:dy)}}
    static func nudgeLayers(_ layers:inout [CoverLayer],ids:Set<UUID>,dx:Double,dy:Double){moveLayers(&layers,ids:ids,dx:dx,dy:dy)}
    static func transformableLayerIDs(
        _ layers: [CoverLayer],
        ids: Set<UUID>
    ) -> Set<UUID> {
        var expanded = ids
        var changed = true
        while changed {
            changed = false
            for layer in layers where layer.groupID.map({ expanded.contains($0) }) == true {
                if expanded.insert(layer.id).inserted { changed = true }
            }
        }
        return Set(layers.filter { expanded.contains($0.id) && $0.kind != .group
            && !$0.locked && $0.positionLocked != true }.map(\.id))
    }

    static func transformBounds(
        _ layers: [CoverLayer],
        ids: Set<UUID>,
        canvasSize: CGSize = CGSize(width: 1, height: 1)
    ) -> CGRect? {
        let editableIDs =
            transformableLayerIDs(
                layers,
                ids:ids
            )

        let frames =
            layers
                .filter {
                    editableIDs.contains(
                        $0.id
                    )
                }
                .map { transformedSnapBounds(of: $0, canvas: canvasSize) }

        guard let first =
            frames.first
        else {
            return nil
        }

        return frames
            .dropFirst()
            .reduce(first) {
                $0.union($1)
            }
    }

    static func scaleLayers(_ layers:inout [CoverLayer],ids:Set<UUID>,around anchor:CGPoint,scaleX:Double,scaleY:Double){guard scaleX.isFinite,scaleY.isFinite,scaleX>0,scaleY>0 else{return};for i in layers.indices where ids.contains(layers[i].id) && !layers[i].locked && layers[i].positionLocked != true{let old=layers[i].frame;layers[i].frame.x=anchor.x+(old.x-anchor.x)*scaleX;layers[i].frame.y=anchor.y+(old.y-anchor.y)*scaleY;layers[i].frame.width=old.width*scaleX;layers[i].frame.height=old.height*scaleY}}
    static func rotateLayers(_ layers:inout [CoverLayer],ids:Set<UUID>,around anchor:CGPoint,degrees:Double,canvasSize:CGSize=CGSize(width:1,height:1)){guard degrees.isFinite,canvasSize.width.isFinite,canvasSize.height.isFinite,canvasSize.width>0,canvasSize.height>0 else{return};let radians=degrees * .pi/180;for i in layers.indices where ids.contains(layers[i].id) && !layers[i].locked && layers[i].positionLocked != true{let frame=layers[i].frame,cx=(frame.x+frame.width/2-anchor.x)*canvasSize.width,cy=(frame.y+frame.height/2-anchor.y)*canvasSize.height,rx=cx*cos(radians)-cy*sin(radians),ry=cx*sin(radians)+cy*cos(radians);layers[i].frame.x=anchor.x+rx/canvasSize.width-frame.width/2;layers[i].frame.y=anchor.y+ry/canvasSize.height-frame.height/2;layers[i].rotation=(layers[i].rotation+degrees).truncatingRemainder(dividingBy:360)}}
    /// Align visible rotated bounds using the Fabric.js-derived corner geometry
    /// already shared with snapping. Translation leaves each layer's transform intact.
    static func align(_ layers: inout [CoverLayer], ids: Set<UUID>, edge: CoverAlignEdge,
                      reference: CGRect? = nil, canvasSize: CGSize = CGSize(width: 1, height: 1)) {
        let indices = layers.indices.filter { ids.contains(layers[$0].id) && !layers[$0].locked && layers[$0].positionLocked != true }
        guard !indices.isEmpty else { return }
        let boxes = indices.map { transformedSnapBounds(of: layers[$0], canvas: canvasSize) }
        let target = reference ?? boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
        for (index, box) in zip(indices, boxes) {
            switch edge {
            case .left: layers[index].frame.x += Double(target.minX - box.minX)
            case .centerX: layers[index].frame.x += Double(target.midX - box.midX)
            case .right: layers[index].frame.x += Double(target.maxX - box.maxX)
            case .top: layers[index].frame.y += Double(target.minY - box.minY)
            case .centerY: layers[index].frame.y += Double(target.midY - box.midY)
            case .bottom: layers[index].frame.y += Double(target.maxY - box.maxY)
            }
        }
    }

    static func distribute(_ layers: inout [CoverLayer], ids: Set<UUID>, axis: CoverDistributionAxis,
                           canvasSize: CGSize = CGSize(width: 1, height: 1)) {
        let boxes = layers.indices.compactMap { index -> (Int, CGRect)? in
            guard ids.contains(layers[index].id), !layers[index].locked, layers[index].positionLocked != true else { return nil }
            return (index, transformedSnapBounds(of: layers[index], canvas: canvasSize))
        }.sorted { axis == .horizontal ? $0.1.minX < $1.1.minX : $0.1.minY < $1.1.minY }
        guard boxes.count >= 3, let first = boxes.first?.1, let last = boxes.last?.1 else { return }
        let horizontal = axis == .horizontal
        let span = horizontal ? last.maxX - first.minX : last.maxY - first.minY
        let occupied = boxes.reduce(CGFloat.zero) { $0 + (horizontal ? $1.1.width : $1.1.height) }
        let gap = (span - occupied) / CGFloat(boxes.count - 1)
        var cursor = horizontal ? first.minX : first.minY
        for (index, box) in boxes {
            if horizontal {
                layers[index].frame.x += Double(cursor - box.minX)
                cursor += box.width + gap
            } else {
                layers[index].frame.y += Double(cursor - box.minY)
                cursor += box.height + gap
            }
        }
    }

    static func safeZoneRects(
        project: CoverProject
    ) -> [CoverRect] {
        guard
            project.canvasWidth > 0,
            project.canvasHeight > 0
        else {
            return []
        }

        if project.type == .printFullWrap {
            let geometry =
                CoverWrapGeometry(
                    project:
                        project
                )

            return [
                geometry.backSafeArea,
                geometry.spineSafeArea,
                geometry.frontSafeArea
            ]
            .filter {
                $0.width > 0
                    && $0.height > 0
            }
        }

        let trim =
            CoverRect(
                x:
                    project.bleed,
                y:
                    project.bleed,
                width:
                    project.trimWidth,
                height:
                    project.trimHeight
            )

        let safe =
            CoverCalculator
                .safeRect(
                    trim:
                        trim
                )

        return [
            CoverRect(
                x:
                    safe.x
                    / project.canvasWidth,
                y:
                    safe.y
                    / project.canvasHeight,
                width:
                    safe.width
                    / project.canvasWidth,
                height:
                    safe.height
                    / project.canvasHeight
            )
        ]
        .filter {
            $0.width > 0
                && $0.height > 0
        }
    }

    static func snap(_ frame:CoverRect,layerID:UUID?,project:CoverProject,displayedCanvas:CGSize,thresholdPoints:Double=8,otherLayers:[CoverLayer]=[],rotationDegrees:Double=0)->(frame:CoverRect,indicators:[CGPoint]){
        guard project.snapEnabled != false,displayedCanvas.width>0,displayedCanvas.height>0 else{return(frame,[])}
        var xTargets=[Double](),yTargets=[Double]()
        let w=project.canvasWidth,h=project.canvasHeight,b=project.bleed,legacy=project.snapBounds != false
        if project.snapCanvasEdges ?? legacy{xTargets += [0,1];yTargets += [0,1]}
        if project.snapCanvasCenter ?? legacy{xTargets.append(0.5);yTargets.append(0.5)}
        if project.snapBleed ?? legacy{xTargets += [0,1];yTargets += [0,1]}
        if project.snapTrim ?? legacy{xTargets += [b/w,(w-b)/w];yTargets += [b/h,(h-b)/h]}
        if project.type == .printFullWrap {
            let back=(b+project.backWidth)/w,front=(b+project.backWidth+project.spineWidth)/w
            if project.snapBackCover ?? legacy{xTargets += [b/w,back]};if project.snapBackCoverCenter ?? (project.snapBackCover ?? legacy){xTargets.append((b/w+back)/2)}
            if project.snapFrontCover ?? legacy{xTargets += [front,(w-b)/w]};if project.snapFrontCoverCenter ?? (project.snapFrontCover ?? legacy){xTargets.append((front+(w-b)/w)/2)}
            if project.snapSpine ?? legacy{xTargets += [back,front]};if project.snapSpineCenter ?? (project.snapSpine ?? legacy){xTargets.append((back+front)/2)}
        }
        if project.snapSafeZone ?? false {
            for safe in safeZoneRects(
                project:
                    project
            ) {
                xTargets += [
                    safe.x,
                    safe.x
                        + safe.width
                ]

                yTargets += [
                    safe.y,
                    safe.y
                        + safe.height
                ]
            }
        }
        if project.snapGuides != false{for value in project.userGuidesX ?? []{xTargets.append(value/w)};for value in project.userGuidesY ?? []{yTargets.append(value/h)}}
        if project.snapGrid != false,let spacing=project.gridSpacingInches,spacing>0{for i in 0...Int(w/spacing){xTargets.append(Double(i)*spacing/w)};for i in 0...Int(h/spacing){yTargets.append(Double(i)*spacing/h)}}
        if project.snapLayers != false{for layer in otherLayers where layer.visible && layer.id != layerID{
            let bounds = transformedSnapBounds(of: layer, canvas: CGSize(width: w, height: h))
            if project.snapLayerEdges ?? true{xTargets += [Double(bounds.minX),Double(bounds.maxX)];yTargets += [Double(bounds.minY),Double(bounds.maxY)]}
            if project.snapLayerCenters ?? true{xTargets.append(Double(bounds.midX));yTargets.append(Double(bounds.midY))}
        }}
        let probe = transformedSnapBounds(frame: frame, rotation: rotationDegrees, canvas: CGSize(width: w, height: h))
        var result=frame;var guides=[CGPoint]();let tx=thresholdPoints/displayedCanvas.width,ty=thresholdPoints/displayedCanvas.height
        func adjustment(_ edges:[Double],_ targets:[Double],_ threshold:Double)->(delta:Double,target:Double)?{
            let candidates=edges.flatMap{edge in targets.map{(delta:$0-edge,target:$0)}}.filter{abs($0.delta)<=threshold}
            return candidates.min(by:{abs($0.delta)<abs($1.delta)})
        }
        if let snap=adjustment([Double(probe.minX),Double(probe.midX),Double(probe.maxX)],xTargets,tx){result.x += snap.delta;guides.append(CGPoint(x:snap.target,y:-1))}
        if let snap=adjustment([Double(probe.minY),Double(probe.midY),Double(probe.maxY)],yTargets,ty){result.y += snap.delta;guides.append(CGPoint(x:-1,y:snap.target))}
        return(result,guides)
    }

    /// Adapted from Fabric.js ObjectGeometry.calcACoords (MIT), commit
    /// 5157cd00903e75da3240eb3c952adc4c71ba8ab2. Rotate physical canvas
    /// coordinates before reducing the corners to normalized snapping bounds.
    private static func transformedSnapBounds(of layer: CoverLayer, canvas: CGSize) -> CGRect {
        transformedSnapBounds(frame: layer.frame, rotation: layer.rotation, canvas: canvas)
    }

    private static func transformedSnapBounds(frame: CoverRect, rotation: Double, canvas: CGSize) -> CGRect {
        let fallback = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        guard rotation.isFinite, canvas.width.isFinite, canvas.height.isFinite,
              canvas.width > 0, canvas.height > 0, frame.x.isFinite, frame.y.isFinite,
              frame.width.isFinite, frame.height.isFinite, frame.width >= 0, frame.height >= 0 else {
            return fallback
        }
        if rotation.truncatingRemainder(dividingBy: 360) == 0 { return fallback }
        let canvasWidth = Double(canvas.width), canvasHeight = Double(canvas.height)
        let angle = rotation * .pi / 180
        let cosine = cos(angle), sine = sin(angle)
        let centerX = (frame.x + frame.width / 2) * canvasWidth
        let centerY = (frame.y + frame.height / 2) * canvasHeight
        let halfWidth = frame.width * canvasWidth / 2
        let halfHeight = frame.height * canvasHeight / 2
        let corners = [(-halfWidth, -halfHeight), (halfWidth, -halfHeight),
                       (-halfWidth, halfHeight), (halfWidth, halfHeight)]
        let xs = corners.map { (centerX + $0.0 * cosine - $0.1 * sine) / canvasWidth }
        let ys = corners.map { (centerY + $0.0 * sine + $0.1 * cosine) / canvasHeight }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return fallback
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func cropSourceRect(layer:CoverLayer,canvasDrag:CGRect,canvasSize:CGSize,imagePixels:CGSize)->CoverRect?{guard canvasSize.width>0,canvasSize.height>0,imagePixels.width>0,imagePixels.height>0,layer.frame.width>0,layer.frame.height>0 else{return nil};let x=max(0,min(1,(canvasDrag.minX/canvasSize.width-layer.frame.x)/layer.frame.width)),y=max(0,min(1,(canvasDrag.minY/canvasSize.height-layer.frame.y)/layer.frame.height)),w=max(0,min(1-x,(canvasDrag.width/canvasSize.width)/layer.frame.width)),h=max(0,min(1-y,(canvasDrag.height/canvasSize.height)/layer.frame.height));guard w>0.001,h>0.001 else{return nil};return CoverRect(x:x,y:y,width:w,height:h)}
    static func composeCrop(existing:CoverRect?,selection:CoverRect)->CoverRect{let base=existing ?? CoverRect();let x=max(0,min(1,selection.x)),y=max(0,min(1,selection.y)),w=max(0,min(1-x,selection.width)),h=max(0,min(1-y,selection.height));return CoverRect(x:base.x+x*base.width,y:base.y+y*base.height,width:w*base.width,height:h*base.height)}

    /// Warps source pixels into a new preview image. The source data stays unchanged in CoverLayer.
    /// Amount is normalized to -1...1 and the mapping is deterministic for a given source/preset.
    static func warpedImage(_ image: NSImage, preset: CoverWarpPreset, amount: Double) -> NSImage {
        guard abs(amount) > 0.0001,let tiff=image.tiffRepresentation,let original=try? PixelBuffer(data:tiff),original.width>1,original.height>1,let output=try? PixelBuffer(width:original.width,height:original.height) else{return image}
        let width=original.width,height=original.height,a=max(-1,min(1,amount));var warped=output
        for y in 0..<height{for x in 0..<width{
            let nx=Double(x)/Double(width-1),ny=Double(y)/Double(height-1)
            let displacement:Double
            switch preset {case .arch:displacement=a*Double(height)*0.16*sin(.pi*nx)*sin(.pi*ny);case .flag:displacement=a*Double(height)*0.14*sin(2 * .pi * nx)}
            let sourceY=Double(y)-displacement
            guard sourceY>=0,sourceY<Double(height-1) else{continue}
            let y0=Int(sourceY),fraction=sourceY-Double(y0),c0=original.color(x:x,y:y0),c1=original.color(x:x,y:min(height-1,y0+1))
            func mix(_ one:UInt8,_ two:UInt8)->UInt8{UInt8((Double(one)*(1-fraction)+Double(two)*fraction).rounded())}
            warped.set(x:x,y:y,rgba:(mix(c0.r,c1.r),mix(c0.g,c1.g),mix(c0.b,c1.b),mix(c0.a,c1.a)))
        }}
        return NSImage(data:warped.pngData()) ?? image
    }

    private static func makeMask(width: Int,height: Int,contains:(Int,Int)->Bool)->Data { guard width>0,height>0,width<=20_000,height<=20_000 else{return Data()};var bytes=[UInt8](repeating:0,count:width*height);for y in 0..<height{for x in 0..<width where contains(x,y){bytes[y*width+x]=255}};return Data(bytes) }
}

enum CoverSelectionMode: String, CaseIterable, Identifiable { case replace, add, subtract, intersect; var id:String{rawValue} }
enum CoverAlignEdge: Hashable {case left,centerX,right,top,centerY,bottom}
enum CoverDistributionAxis {case horizontal,vertical}
struct CoverTransformState: Equatable { let layerID:UUID; let original:CoverLayer; var preview:CoverLayer }
struct CoverTransformTransaction: Equatable {
    private(set) var states:[CoverTransformState]
    init(layers:[CoverLayer],ids:Set<UUID>){states=layers.filter{ids.contains($0.id)}.map{CoverTransformState(layerID:$0.id,original:$0,preview:$0)}}
    mutating func update(layerID:UUID,_ body:(inout CoverLayer)->Void){guard let i=states.firstIndex(where:{$0.layerID==layerID}) else{return};body(&states[i].preview)}
    func committedLayers()->[UUID:CoverLayer]{Dictionary(uniqueKeysWithValues:states.map{($0.layerID,$0.preview)})}
    func cancelledLayers()->[UUID:CoverLayer]{Dictionary(uniqueKeysWithValues:states.map{($0.layerID,$0.original)})}
}

struct CoverViewport:Equatable{var zoom:Double=1;var pan=CGPoint.zero;var rotation=0.0
    mutating func zoomAt(_ point:CGPoint,center:CGPoint = .zero,factor:Double,minimum:Double=0.1,maximum:Double=8){guard factor.isFinite,factor>0 else{return};let document=documentPoint(for:point,center:center),next=Swift.max(minimum,Swift.min(maximum,zoom*factor)),r=rotation * .pi/180,x=document.x-center.x,y=document.y-center.y;pan=CGPoint(x:point.x-center.x-next*(x*cos(r)-y*sin(r)),y:point.y-center.y-next*(x*sin(r)+y*cos(r)));zoom=next}
    mutating func panBy(_ delta:CGSize){pan=CGPoint(x:pan.x+delta.width,y:pan.y+delta.height)}
    mutating func rotateBy(_ degrees:Double){guard degrees.isFinite else{return};rotation=(rotation+degrees).truncatingRemainder(dividingBy:360)}
    mutating func reset(){zoom=1;pan = .zero;rotation=0}
    mutating func fitSelection(_ rect:CGRect,viewport:CGSize){guard rect.width>0,rect.height>0 else{return};zoom=min(viewport.width/rect.width,viewport.height/rect.height);pan=CGPoint(x:viewport.width/2-rect.midX*zoom,y:viewport.height/2-rect.midY*zoom)}
    func viewPoint(for documentPoint:CGPoint,center:CGPoint)->CGPoint{let x=(documentPoint.x-center.x)*zoom,y=(documentPoint.y-center.y)*zoom,r=rotation * .pi/180;return CGPoint(x:center.x+x*cos(r)-y*sin(r)+pan.x,y:center.y+x*sin(r)+y*cos(r)+pan.y)}
    func documentPoint(for viewPoint:CGPoint,center:CGPoint)->CGPoint{let x=viewPoint.x-center.x-pan.x,y=viewPoint.y-center.y-pan.y,r = -rotation * .pi/180;return CGPoint(x:center.x+(x*cos(r)-y*sin(r))/zoom,y:center.y+(x*sin(r)+y*cos(r))/zoom)}
}

private struct PixelBuffer {
    let width:Int; let height:Int; var bytes:[UInt8]
    init(data:Data) throws {
        guard let rep=NSBitmapImageRep(data:data),rep.pixelsWide>0,rep.pixelsHigh>0,rep.pixelsWide*rep.pixelsHigh<=100_000_000,let cg=rep.cgImage else{throw WriterError.message("The image layer cannot be decoded for editing.")}
        width=cg.width;height=cg.height
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:width*4,bitsPerPixel:32),let storage=bitmap.bitmapData,let ctx=CGContext(data:storage,width:width,height:height,bitsPerComponent:8,bytesPerRow:bitmap.bytesPerRow,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{throw WriterError.message("A pixel editing buffer could not be created.")}
        ctx.draw(cg,in:CGRect(x:0,y:0,width:width,height:height));bytes=Array(UnsafeBufferPointer(start:storage,count:width*height*4))
    }
    init(width:Int,height:Int) throws { guard width>0,height>0,width*height<=100_000_000 else{throw WriterError.message("The requested raster layer is too large.")};self.width=width;self.height=height;bytes=[UInt8](repeating:0,count:width*height*4) }
    func color(x:Int,y:Int)->(r:UInt8,g:UInt8,b:UInt8,a:UInt8){let i=(y*width+x)*4;return(bytes[i],bytes[i+1],bytes[i+2],bytes[i+3])}
    func distance(_ a:(r:UInt8,g:UInt8,b:UInt8,a:UInt8),_ b:(r:UInt8,g:UInt8,b:UInt8,a:UInt8))->Double{hypot(hypot(Double(a.r)-Double(b.r),Double(a.g)-Double(b.g)),Double(a.b)-Double(b.b))}
    mutating func set(x:Int,y:Int,rgba:(UInt8,UInt8,UInt8,UInt8)){let i=(y*width+x)*4;bytes[i]=rgba.0;bytes[i+1]=rgba.1;bytes[i+2]=rgba.2;bytes[i+3]=rgba.3}
    func pngData()->Data{guard let provider=CGDataProvider(data:Data(bytes) as CFData),let cg=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else{return Data()};return NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) ?? Data()}
}
