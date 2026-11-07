import XCTest
import AppKit
import zlib
@testable import BOLDWriter

final class PSDImporterTests: XCTestCase {
    private func fixture() -> CoverProject {
        var p = CoverProject(type:.printFullWrap,width:2,height:1); p.dpi = 100
        p.trimWidth = 0.9; p.backWidth = 0.9; p.trimHeight = 1; p.spineWidth = 0.2; p.bleed = 0
        var a = CoverLayer(kind:.shape,name:"Lower α",frame:CoverRect(x:0.1,y:0.1,width:0.2,height:0.3)); a.fillHex = "#FF0000"
        var b = CoverLayer(kind:.shape,name:"Upper",frame:CoverRect(x:0.5,y:0.6,width:0.2,height:0.2)); b.fillHex = "#00FF00"; b.opacity = 173.0/255; b.visible = false; b.blendMode = .multiply
        p.layers = [a,b]; return p
    }
    func testLayerCountNamesOrderBoundsOpacityVisibilityAndBlend() throws {
        let p = fixture(), d = try PSDExporter.export(p)
        let imported = try CoverImport.project(data:d,filename:"layers.psd")
        XCTAssertEqual(imported.layers.map(\.name),["Lower α","Upper"])
        XCTAssertEqual(imported.layers.count,2); XCTAssertEqual(imported.dpi,100)
        XCTAssertEqual(imported.rasterPixelSize,p.rasterPixelSize)
        XCTAssertEqual(imported.layers[0].frame.x,19.0/200,accuracy:0.000001)
        XCTAssertEqual(imported.layers[0].frame.y,9.0/100,accuracy:0.000001)
        XCTAssertEqual(imported.layers[1].opacity,173.0/255,accuracy:0.000001)
        XCTAssertFalse(imported.layers[1].visible); XCTAssertEqual(imported.layers[1].blendMode,.multiply)
    }
    func testRasterPixelsAndSecondExportKeepTopDownRows() throws {
        let p = fixture(); let first = try CoverImport.project(data:PSDExporter.export(p),filename:"a.psd")
        let second = try CoverImport.project(data:PSDExporter.export(first),filename:"b.psd")
        for i in first.layers.indices {
            XCTAssertEqual(first.layers[i].frame.x,second.layers[i].frame.x,accuracy:0.005)
            XCTAssertEqual(first.layers[i].frame.y,second.layers[i].frame.y,accuracy:0.01)
            let a = try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(first.layers[i].imageData)))
            let b = try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(second.layers[i].imageData)))
            XCTAssertEqual(a.pixelsWide,b.pixelsWide); XCTAssertEqual(a.pixelsHigh,b.pixelsHigh)
            XCTAssertEqual(a.colorAt(x:2,y:2)?.usingColorSpace(.deviceRGB)?.redComponent,b.colorAt(x:2,y:2)?.usingColorSpace(.deviceRGB)?.redComponent)
        }
    }
    func testEditableTextContentStyleRotationSaveReopenAndSecondExport() throws {
        var p = fixture(); var l = CoverLayer(kind:.text,name:"Text",frame:CoverRect(x:0.2,y:0.2,width:0.6,height:0.5))
        l.text = "External text (α)"; l.fontName = "Georgia"; l.fontSize = 14; l.colorHex = "#123456"; l.rotation = 12
        l.alignment = "right"; l.letterSpacing = 2; l.leading = 20; l.underline = true
        p.layers = [l]
        let a = try CoverImport.project(data:PSDExporter.export(p),filename:"text.psd")
        let imported = try XCTUnwrap(a.layers.first); XCTAssertEqual(imported.kind,.text); XCTAssertEqual(imported.text,l.text)
        XCTAssertEqual(imported.fontSize,14); XCTAssertEqual(imported.colorHex,l.colorHex); XCTAssertEqual(imported.rotation,12,accuracy:0.00001)
        XCTAssertEqual(imported.frame.x,l.frame.x,accuracy:0.000001); XCTAssertEqual(imported.frame.y,l.frame.y,accuracy:0.000001)
        let snapshot = try JSONDecoder().decode(CoverLayerCommands.Snapshot.self,from:Data(CoverLayerCommands.inspect(a).utf8))
        XCTAssertEqual(snapshot.layers[0].colorHex,l.colorHex); XCTAssertEqual(snapshot.layers[0].leading,20)
        XCTAssertEqual(snapshot.layers[0].underline,true); XCTAssertEqual(snapshot.layers[0].referencePageWidth,200)
        XCTAssertEqual(imported.letterSpacing,2); XCTAssertEqual(imported.leading,20); XCTAssertEqual(imported.alignment,"right"); XCTAssertEqual(imported.underline,true)
        let reopened = try JSONDecoder().decode(CoverProject.self,from:JSONEncoder().encode(a)); XCTAssertEqual(reopened,a)
        let b = try CoverImport.project(data:PSDExporter.export(reopened),filename:"second.psd")
        XCTAssertEqual(b.layers.first?.text,l.text); XCTAssertEqual(b.layers.first?.kind,.text)
    }
    func testGroupStructureUsesStandardBottomFirstSectionDividers() throws {
        var p = fixture(); var g = CoverLayer(kind:.group,name:"Folder"); g.visible = false
        for i in p.layers.indices { p.layers[i].groupID = g.id }; p.layers.append(g)
        let a = try CoverImport.project(data:PSDExporter.export(p),filename:"group.psd")
        let folder = try XCTUnwrap(a.layers.first(where:{$0.kind == .group})); XCTAssertEqual(folder.name,"Folder"); XCTAssertFalse(folder.visible)
        XCTAssertEqual(a.layers.filter{$0.kind != .group}.map(\.groupID),[folder.id,folder.id])
        let b = try CoverImport.project(data:PSDExporter.export(a),filename:"group2.psd")
        XCTAssertEqual(b.layers.map(\.name),a.layers.map(\.name))
    }
    func testSharedCommandImportsAtomicallyAndPreservesPrintGeometry() throws {
        var p = fixture(); let original = p
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".psd")
        defer { try? FileManager.default.removeItem(at:url) }; try PSDExporter.export(p).write(to:url)
        let action = try BOLDTerminalCommandParser.parse(["cover","edit","psd-import","path="+url.path],source:.terminal)
        let ids = try CoverProjectOperations.apply("psd-import",to:&p,arguments:action.arguments)
        XCTAssertEqual(ids.count,2); XCTAssertEqual(p.id,original.id); XCTAssertEqual(p.canvasWidth,original.canvasWidth)
        XCTAssertEqual(p.trimWidth,original.trimWidth); XCTAssertEqual(p.spineWidth,original.spineWidth)
        XCTAssertEqual(p.layers.map(\.kind),[.image,.image])
        let snapshot = try CoverLayerCommands.inspect(p); XCTAssertTrue(snapshot.contains("psdImportWarnings"))
        let state = try JSONDecoder().decode(CoverLayerCommands.Snapshot.self,from:Data(snapshot.utf8))
        XCTAssertNotNil(state.layers[0].embeddedImageSHA256); XCTAssertNotNil(state.layers[0].imagePixelWidth)
    }
    func testLockedExistingLayerPreventsReplacementWithoutMutation() throws {
        var p = fixture(); p.layers[0].locked = true; let original = p
        XCTAssertThrowsError(try CoverImport.replacePSD(data:PSDExporter.export(fixture()),filename:"x.psd",in:&p)); XCTAssertEqual(p,original)
    }
    func testMismatchedCanvasDoesNotChangeMeasuredCover() throws {
        var p = fixture(); let original = p; var other = fixture(); other.canvasWidth = 3
        XCTAssertThrowsError(try CoverImport.replacePSD(data:PSDExporter.export(other),filename:"x.psd",in:&p)); XCTAssertEqual(p,original)
    }
    func testTruncatedCorruptAndUnsupportedDepthAreRejected() throws {
        let d = try PSDExporter.export(fixture())
        for length in [0,4,26,34,100,d.count/2] { XCTAssertThrowsError(try PSDImporter.read(d.prefix(length),filename:"bad.psd")) }
        var bad = d; bad[23] = 16; XCTAssertThrowsError(try PSDImporter.read(bad,filename:"16.psd"))
        bad = d; bad[5] = 2; XCTAssertThrowsError(try PSDImporter.read(bad,filename:"psb.psd"))
    }
    func testUnsupportedMaskRejectsRatherThanFlattens() throws {
        // A real standard mask channel ID is sufficient to demand an explicit rejection.
        var d = try PSDExporter.export(fixture())
        var i = 26; func u32(_ pos:Int)->Int { d[pos..<pos+4].reduce(0){($0<<8)|Int($1)} }
        i += 4+u32(i); i += 4+u32(i); i += 4+4+2+16+2
        d[i] = 255; d[i+1] = 254 // first channel -2, editable user mask
        XCTAssertThrowsError(try PSDImporter.read(d,filename:"mask.psd")) { XCTAssertTrue($0.localizedDescription.contains("mask")) }
    }
    func testAllSupportedBlendModesParse() throws {
        for blend in CoverBlendMode.allCases { var p = fixture(); p.layers[0].blendMode = blend
            XCTAssertEqual(try PSDImporter.read(PSDExporter.export(p),filename:"blend.psd").project.layers[0].blendMode,blend)
        }
    }
    func test3DTexturesRefreshAfterImportedVisibilityOpacityAndArtwork() throws {
        var p = fixture(); let before = PhysicalBookCoverTextures(project:p,workingLayers:false,previewDPI:100)
        var other = fixture(); other.layers[0].fillHex = "#0000FF"; other.layers[1].visible = true
        try CoverImport.replacePSD(data:PSDExporter.export(other),filename:"new.psd",in:&p)
        let after = PhysicalBookCoverTextures(project:p,workingLayers:false,previewDPI:100)
        XCTAssertNotNil(after.front); XCTAssertNotNil(after.spine); XCTAssertNotNil(after.back)
        XCTAssertNotEqual(before.back?.tiffRepresentation,after.back?.tiffRepresentation)
        XCTAssertNotEqual(before.front?.tiffRepresentation,after.front?.tiffRepresentation)
        XCTAssertEqual(p.spineWidth,0.2); XCTAssertEqual(p.layers[1].opacity,173.0/255,accuracy:0.000001)
    }
    /// A hand-encoded standard PSD, independent of the production exporter.
    /// The edited record comes first (external reorder), with integer +37/+19 bounds.
    private func externalFixture(compression: Int = 0, blend: String = "mul ", locks: UInt32 = 0, zeroWidth: Bool = false) -> Data {
        func be(_ value: UInt64, _ n: Int) -> Data { Data((0..<n).reversed().map { UInt8(truncatingIfNeeded:value >> ($0*8)) }) }
        func section(_ d: Data) -> Data { be(UInt64(d.count),4)+d }
        func channel(_ values: [UInt8]) -> Data {
            if compression == 0 { return be(0,2)+Data(values) }
            if compression == 1 { return be(1,2)+be(3,2)+be(3,2)+Data([1,values[0],values[1],1,values[2],values[3]]) }
            var input = values
            if compression == 3, !input.isEmpty { input[1] = values[1] &- values[0]; input[3] = values[3] &- values[2] }
            var output = [UInt8](repeating:0,count:100); var length = uLongf(100)
            _ = output.withUnsafeMutableBufferPointer { o in input.withUnsafeBufferPointer { i in compress2(o.baseAddress,&length,i.baseAddress,uLong(i.count),6) } }
            return be(UInt64(compression),2)+Data(output.prefix(Int(length)))
        }
        let colors: [[UInt8]] = zeroWidth ? Array(repeating:[],count:4) : [[10,20,30,40],[50,60,70,80],[90,100,110,120],[255,255,255,255]]
        let channels = colors.map(channel)
        func record(_ name: String, _ x: Int, _ y: Int, _ edited: Bool) -> Data {
            var d = be(UInt64(y),4)+be(UInt64(x),4)+be(UInt64(y+2),4)+be(UInt64(x+(zeroWidth ? 0 : 2)),4)+be(4,2)
            for i in 0..<4 { d += be(i == 3 ? 65535 : UInt64(i),2)+be(UInt64(channels[i].count),4) }
            d += Data("8BIM".utf8)+Data((edited ? blend : "norm").utf8)+Data([edited ? 173 : 255,0,edited ? 10 : 8,0])
            var extra = be(0,4)+be(0,4)+be(UInt64(name.utf8.count),1)+Data(name.utf8)
            while extra.count%4 != 0 { extra.append(0) }
            extra += Data("8BIMlspf".utf8)+be(4,4)+be(UInt64(locks),4)
            return d+section(extra)
        }
        var info = be(2,2)+record("External renamed",47,29,true)+record("Other",10,10,false)
        for _ in 0..<2 { for c in channels { info += c } }
        if info.count%2 != 0 { info.append(0) }
        let layers = section(info)+be(0,4)
        var result = Data("8BPS".utf8)+be(1,2)+Data(repeating:0,count:6)+be(3,2)+be(100,4)+be(100,4)+be(8,2)+be(3,2)
        result += be(0,4)+be(0,4)+section(layers)+be(0,2)+Data(repeating:0,count:30000)
        return result
    }
    func testIndependentExternalRenameMovementReorderAndPixels() throws {
        let p = try PSDImporter.read(externalFixture(),filename:"external.psd").project
        XCTAssertEqual(p.layers.map(\.name),["External renamed","Other"])
        let l = p.layers[0]; XCTAssertEqual(l.frame.x*100-10,37,accuracy:0.000001); XCTAssertEqual(l.frame.y*100-10,19,accuracy:0.000001)
        XCTAssertEqual(l.opacity,173.0/255); XCTAssertFalse(l.visible); XCTAssertEqual(l.blendMode,.multiply)
        let image = try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(l.imageData)))
        XCTAssertEqual(image.pixelsWide,2); XCTAssertEqual(image.pixelsHigh,2)
        var samples = [Int](repeating:0,count:4); image.getPixel(&samples,atX:0,y:0)
        XCTAssertEqual(samples,[10,50,90,255])
    }
    func testIndependentRawRLEZIPAndZIPPredictionChannelParsing() throws {
        for compression in 0...3 {
            let p = try PSDImporter.read(externalFixture(compression:compression),filename:"compression.psd").project
            let image = try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(p.layers[0].imageData)))
            var samples = [Int](repeating:0,count:4); image.getPixel(&samples,atX:1,y:1); XCTAssertEqual(samples[0],40)
        }
    }
    func testUnsupportedBlendRejectsAndPSDLocksRemainEditableModelState() throws {
        XCTAssertThrowsError(try PSDImporter.read(externalFixture(blend:"nope"),filename:"unsupported.psd"))
        let layer = try PSDImporter.read(externalFixture(locks:0x80000007),filename:"locks.psd").project.layers[0]
        XCTAssertTrue(layer.locked); XCTAssertEqual(layer.positionLocked,true); XCTAssertEqual(layer.pixelsLocked,true); XCTAssertEqual(layer.transparencyLocked,true)
    }

    func testReferencePageTextUsesEffectivePSDPixelsAndScalesInto3DPreview() throws {
        var p = fixture(); var l = CoverLayer(kind:.text,name:"Referenced",frame:CoverRect(x:0.1,y:0.1,width:0.8,height:0.8))
        l.text = "Lantern"; l.fontSize = 10; l.referencePageWidth = 100; p.layers = [l]
        let imported = try PSDImporter.read(PSDExporter.export(p),filename:"reference.psd").project
        XCTAssertEqual(imported.layers[0].fontSize,20,accuracy:0.000001)
        XCTAssertEqual(imported.layers[0].referencePageWidth,200)
        let second = try PSDImporter.read(PSDExporter.export(imported),filename:"again.psd").project
        XCTAssertEqual(second.layers[0].fontSize,20,accuracy:0.000001)
        let a = try CoverArtwork.render(p,includeGuides:false,includeTemplate:false,scale:50)
        let b = try CoverArtwork.render(imported,includeGuides:false,includeTemplate:false,scale:50)
        XCTAssertEqual(a.size,b.size)
        XCTAssertNotNil(b.tiffRepresentation)
    }

    func testIndependentRasterSamplesAndBoundsSurviveSecondExportExactly() throws {
        let original = try PSDImporter.read(externalFixture(),filename:"external.psd").project
        let second = try PSDImporter.read(PSDExporter.export(original),filename:"second.psd").project
        for i in original.layers.indices {
            XCTAssertEqual(original.layers[i].frame,second.layers[i].frame)
            let a = try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(original.layers[i].imageData)))
            let b = try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(second.layers[i].imageData)))
            for y in 0..<2 { for x in 0..<2 {
                var before = [Int](repeating:0,count:4), after = before
                a.getPixel(&before,atX:x,y:y); b.getPixel(&after,atX:x,y:y)
                XCTAssertEqual(before,after)
            } }
        }
    }

    func testDefaultLineHeightKeepsUnchangedNativeTextRasterBounds() throws {
        var p = CoverProject(width:2,height:2); p.dpi = 100
        var l = CoverLayer(kind:.text,name:"Default metrics",frame:CoverRect(x:0.1,y:0.1,width:0.8,height:0.8))
        l.text = "THE\nLANTERN"; l.fontName = "Georgia"; l.fontSize = 20; l.referencePageWidth = 100; p.layers = [l]
        let imported = try CoverImport.project(data:PSDExporter.export(p),filename:"metrics.psd")
        func inkBounds(_ project: CoverProject) throws -> [Int] {
            let image = try XCTUnwrap(NSBitmapImageRep(data:CoverArtwork.export(project,format:"png")))
            var minX = image.pixelsWide, minY = image.pixelsHigh, maxX = 0, maxY = 0
            var rgba = [Int](repeating:0,count:4)
            for y in 0..<image.pixelsHigh { for x in 0..<image.pixelsWide {
                image.getPixel(&rgba,atX:x,y:y)
                if rgba[0] < 128 { minX = min(minX,x); minY = min(minY,y); maxX = max(maxX,x); maxY = max(maxY,y) }
            } }
            return [minX,minY,maxX,maxY]
        }
        XCTAssertEqual(try inkBounds(imported),try inkBounds(p))
    }

    func testEmptyZIPBoundsRejectWithoutPredictionRangeTrap() throws {
        for compression in [2,3] {
            XCTAssertThrowsError(try PSDImporter.read(externalFixture(compression:compression,zeroWidth:true),filename:"empty.psd")) {
                XCTAssertTrue($0.localizedDescription.contains("empty layer bounds"))
            }
        }
    }

}
