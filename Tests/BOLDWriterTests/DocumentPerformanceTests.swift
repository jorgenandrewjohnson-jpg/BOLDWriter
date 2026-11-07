import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import BOLDWriter

final class DocumentPerformanceTests: XCTestCase {
    func testAuthorizedManuscriptImportTiming() throws {
        guard let path=ProcessInfo.processInfo.environment["BOLD_PERFORMANCE_DOCX"] else {
            throw XCTSkip("Set BOLD_PERFORMANCE_DOCX to an explicitly authorized manuscript.")
        }
        let start=Date()
        let data=try Data(contentsOf:URL(fileURLWithPath:path))
        let wrapper=FileWrapper(regularFileWithContents:data)
        wrapper.preferredFilename="Performance manuscript.docx"
        let document=try BOLDWriterDocument(fileWrapper:wrapper,contentType:.docx)
        print("BOLD_IMPORT_SECONDS=\(Date().timeIntervalSince(start)) CHARACTERS=\(document.text.length)")
        XCTAssertGreaterThan(document.text.length,0)
    }
}

@MainActor
final class CurrentProjectManuscriptImportTests: XCTestCase {
    func testReplacementKeepsCoverAndStudioAndSupportsUndoRedo() throws {
        let document=BOLDWriterDocument()
        document.replaceText(with:NSAttributedString(string:"Existing manuscript"))
        let cover=CoverProject()
        document.metadata.coverProjects=[cover]
        document.metadata.activeCoverProjectID=cover.id
        document.metadata.bookStudioPresentation=BookStudioPresentation()
        document.metadata.comments=[DocumentComment(text:"Old",location:0,length:1)]
        let original=WriterDocumentSnapshot(text:document.text,metadata:document.metadata)
        var metadata=DocumentMetadata()
        metadata.page.paper = .custom
        metadata.page.customPaperSize=CGSize(width:594,height:792)
        let imported=WriterDocumentSnapshot(text:NSAttributedString(string:"New manuscript"),metadata:metadata)
        let undo=UndoManager(); undo.groupsByEvent=false
        document.importManuscript(imported,undoManager:undo)
        XCTAssertEqual(document.text.string,"New manuscript")
        XCTAssertEqual(document.metadata.coverProjects,[cover])
        XCTAssertEqual(document.metadata.bookStudioPresentation,original.metadata.bookStudioPresentation)
        XCTAssertEqual(document.metadata.page,metadata.page)
        XCTAssertTrue(document.metadata.comments.isEmpty)
        undo.undo()
        XCTAssertEqual(document.text.string,"Existing manuscript")
        XCTAssertEqual(document.metadata.comments,original.metadata.comments)
        undo.redo()
        XCTAssertEqual(document.text.string,"New manuscript")
        XCTAssertEqual(document.manuscriptReplacementRevisionID,document.revisionID)
    }

    func testEyedropperSamplesCompositeWithoutImageSelection() throws {
        var project=CoverProject(width:2,height:2); project.dpi=72
        project.backgroundHex="#FFFFFF"
        var shape=CoverLayer(kind:.shape,name:"Red top",frame:CoverRect(x:0,y:0,width:1,height:0.5))
        shape.fillHex="#FF0000"; project.layers=[shape]
        let top=try CoverEditorEngine.sampledCanvasColor(project:project,point:CGPoint(x:0.5,y:0.25))
        let bottom=try CoverEditorEngine.sampledCanvasColor(project:project,point:CGPoint(x:0.5,y:0.75))
        XCTAssertEqual(top.hexRGB.uppercased(),"#FF0000")
        XCTAssertEqual(bottom.hexRGB.uppercased(),"#FFFFFF")
        XCTAssertThrowsError(try CoverEditorEngine.sampledCanvasColor(project:project,point:CGPoint(x:-1,y:0)))
    }
}
