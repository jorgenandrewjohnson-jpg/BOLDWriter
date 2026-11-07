import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

/// Opt-in local production acceptance. Assets are proof copies outside the repository.
@MainActor
final class RealCoverManuscriptAcceptanceTests: XCTestCase {
    func testMeasuredCoverCoexistsWithUnmodifiedRealManuscriptThroughEditingAndDiskReopen() throws {
        guard let path = ProcessInfo.processInfo.environment["BOLD_REAL_ACCEPTANCE_DIR"] else {
            throw XCTSkip("Set BOLD_REAL_ACCEPTANCE_DIR to the authorized proof workspace.")
        }
        let root = URL(fileURLWithPath:path)
        let session = try BookAutomationSession(input:root.appendingPathComponent("manuscript.docx"))
        let originalText = NSAttributedString(attributedString:session.document.text)
        let page = session.document.metadata.page
        let sections = session.document.metadata.sections
        let bookmarks = session.document.metadata.bookmarks
        XCTAssertGreaterThanOrEqual(bookmarks.count,38,"Referenced generated heading targets must survive real DOCX import")
        try session.importMeasuredCover(template:root.appendingPathComponent("kdp-hardcover.pdf"),artwork:root.appendingPathComponent("cover.jpg"))
        XCTAssertTrue(session.document.text.isEqual(to:originalText))
        XCTAssertEqual(session.document.metadata.page,page)
        XCTAssertEqual(session.document.metadata.sections,sections)
        let p = try XCTUnwrap(session.document.metadata.coverProjects?.last)
        XCTAssertNotNil(p.activeKDPHardcoverLayout)
        XCTAssertEqual(p.trimWidth,8.25,accuracy:0.001); XCTAssertEqual(p.trimHeight,11,accuracy:0.001)
        XCTAssertEqual(p.canvasWidth,19.469,accuracy:0.002); XCTAssertEqual(p.canvasHeight,12.417,accuracy:0.002)
        XCTAssertEqual(p.spineWidth,1.394,accuracy:0.002)
        XCTAssertEqual(p.layers.count,48)
        var resized = p
        XCTAssertThrowsError(try CoverProjectOperations.apply("canvas-resize",to:&resized,arguments:["width":"20","height":"13"]))
        XCTAssertEqual(resized,p)
        let artwork = try XCTUnwrap(p.layers.last), id = artwork.id.uuidString
        _ = try session.execute(BOLDTerminalCommandParser.parse(["cover","edit","move","layerID="+id,"dx=0.001","dy=0.002"]))
        _ = try session.execute(BOLDTerminalCommandParser.parse(["undo"]))
        XCTAssertEqual(session.document.metadata.coverProjects?.last,p)
        _ = try session.execute(BOLDTerminalCommandParser.parse(["cover","update-layer",id,"name=Acceptance artwork"]))
        let edited = try XCTUnwrap(session.document.metadata.coverProjects?.last)
        XCTAssertEqual(edited.layers.last?.frame,artwork.frame)
        XCTAssertEqual(edited.activeKDPHardcoverLayout,p.activeKDPHardcoverLayout)
        let output = root.appendingPathComponent("acceptance-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let saved = output.appendingPathComponent("Real-Manuscript-Cover.boldwriter")
        try BOLDWriterDocument.packageWrapper(text:session.document.text,metadata:session.document.metadata).write(to:saved,options:.atomic,originalContentsURL:nil)
        let reopened = try BookAutomationSession(input:saved)
        XCTAssertEqual(reopened.document.metadata.coverProjects,session.document.metadata.coverProjects)
        XCTAssertEqual(reopened.document.metadata.page,page)
        XCTAssertEqual(reopened.document.metadata.sections,sections)
        XCTAssertEqual(reopened.document.metadata.bookmarks,bookmarks)
        XCTAssertEqual(reopened.document.text.string,originalText.string)
        // Native persistence should preserve rich character and paragraph attributes, not just text.
        var differences = Set<String>()
        originalText.enumerateAttributes(in:NSRange(location:0,length:originalText.length)) { attributes,range,_ in
            let restored = reopened.document.text.attributes(at:range.location,effectiveRange:nil)
            for key in Set(attributes.keys).union(restored.keys) {
                if !NSDictionary(dictionary:["v":attributes[key] ?? NSNull()]).isEqual(to:["v":restored[key] ?? NSNull()]) {
                    differences.insert(key.rawValue)
                }
            }
        }
        print("BOLD_FORMAT_ATTRIBUTE_DIFFERENCES="+differences.sorted().joined(separator:","))
        XCTAssertTrue(reopened.document.text.isEqual(to:originalText))
        let preflight = try reopened.execute(BOLDTerminalCommandParser.parse(["publishing","preflight"]))
        XCTAssertFalse(try XCTUnwrap(preflight.values["trimMismatchPages"]).isEmpty,"Known manuscript/cover trim mismatch must be reported")
        XCTAssertEqual(preflight.values["productionReady"], "false", "The 535-page, 8.25 × 11 template cannot be treated as production-ready for a 356-page, 5.5 × 8.5 manuscript")
        XCTAssertTrue(try XCTUnwrap(preflight.values["preflightErrors"]).contains("535 pages"))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(preflight).write(to:output.appendingPathComponent("preflight.json"))
        for format in ["png","jpg","psd"] {
            let bytes = try CoverArtwork.export(edited,format:format)
            XCTAssertGreaterThan(bytes.count,1000)
            try bytes.write(to:output.appendingPathComponent("real-cover."+format))
            if format == "pdf" {
                let pdf = try XCTUnwrap(PDFDocument(data:bytes)); XCTAssertEqual(pdf.pageCount,1)
                XCTAssertEqual(try XCTUnwrap(pdf.page(at:0)).bounds(for:.mediaBox).width,edited.canvasWidth*72,accuracy:0.1)
            } else if format == "psd" { XCTAssertEqual(String(data:bytes.prefix(4),encoding:.ascii),"8BPS") }
            else {
                let image = try XCTUnwrap(NSBitmapImageRep(data:bytes))
                XCTAssertEqual(image.pixelsWide,Int(ceil(edited.canvasWidth*edited.dpi)))
                XCTAssertEqual(image.pixelsHigh,Int(ceil(edited.canvasHeight*edited.dpi)))
            }
        }
        let blockedPDF = output.appendingPathComponent("obsolete-template-production.pdf")
        XCTAssertThrowsError(try reopened.execute(BOLDTerminalCommandParser.parse(["cover","export",blockedPDF.path])))
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedPDF.path), "Preflight must block a production PDF without leaving a partial output")
        try Data(saved.path.utf8).write(to:root.appendingPathComponent("latest-real-project.txt"))
        print("BOLD_REAL_ACCEPTANCE_OUTPUT="+output.path)
    }
    func testRealBookRendersAllCoverPanelsAndOpenManuscriptPostures() throws {
        guard let path = ProcessInfo.processInfo.environment["BOLD_REAL_ACCEPTANCE_DIR"] else { throw XCTSkip("Authorized proof workspace required") }
        let root = URL(fileURLWithPath:path)
        let saved = try String(contentsOf:root.appendingPathComponent("latest-real-project.txt"),encoding:.utf8)
        let session = try BookAutomationSession(input:URL(fileURLWithPath:saved))
        let output = root.appendingPathComponent("studio-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let preflight = try session.execute(BOLDTerminalCommandParser.parse(["publishing","preflight"]))
        let count = try XCTUnwrap(preflight.values["pageCount"].flatMap(Int.init))
        var evidence:[BOLDCommandResult] = [preflight]
        for camera in ["front","back","spine"] {
            _ = try session.execute(BOLDTerminalCommandParser.parse(["studio","preset",camera]))
            evidence.append(try session.execute(BOLDTerminalCommandParser.parse(["studio","render",output.appendingPathComponent(camera+".png").path])))
        }
        var partial = try BOLDTerminalCommandParser.parse(["studio","camera","perspective"])
        partial.arguments["open"] = "true"; partial.arguments["openAngle"] = "80"
        _ = try session.execute(partial)
        evidence.append(try session.execute(BOLDTerminalCommandParser.parse(["studio","render",output.appendingPathComponent("partial-open.png").path])))
        _ = try session.execute(BOLDTerminalCommandParser.parse(["studio","preset","reading"]))
        for spread in [0,1,count/4,count/2] {
            var action = try BOLDTerminalCommandParser.parse(["studio","render",output.appendingPathComponent("reading-"+String(spread)+".png").path])
            action.arguments["spread"] = String(spread)
            evidence.append(try session.execute(action))
        }
        let p = try XCTUnwrap(session.document.metadata.coverProjects?.last)
        let textures = PhysicalBookCoverTextures(project:p,workingLayers:false,previewDPI:360)
        XCTAssertNotNil(textures.spine)
        XCTAssertLessThan(textures.estimatedMemoryCost,64_000_000)
        for image in [textures.front,textures.spine,textures.back].compactMap({ $0 }) {
            XCTAssertLessThanOrEqual(try XCTUnwrap(image.cgImage(forProposedRect:nil,context:nil,hints:nil)).width,8192)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(evidence).write(to:output.appendingPathComponent("render-evidence.json"))
        print("BOLD_REAL_STUDIO_OUTPUT="+output.path)
        print("BOLD_REAL_TEXTURE_BYTES="+String(textures.estimatedMemoryCost))
    }

}
