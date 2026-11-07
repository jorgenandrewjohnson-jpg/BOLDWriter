import AppKit
import Foundation
import XCTest
@testable import BOLDWriter

final class DocumentDropRoutingTests:
    XCTestCase
{
    func testSupportedDocumentExtensionsOpenAsDocuments() {
        for filename in [
            "Novel.boldwriter",
            "Novel.docx",
            "Novel.DOCX",
            "Legacy.doc",
            "Notes.rtf",
            "Package.rtfd",
            "Draft.txt",
            "Draft.md",
            "Draft.markdown",
            "Page.html",
            "Page.htm",
            "Proof.pdf"
        ] {
            XCTAssertTrue(
                BOLDDocumentDropRouter
                    .shouldOpenAsDocument(
                        URL(
                            fileURLWithPath:
                                "/tmp/\(filename)"
                        )
                    ),
                filename
            )
        }
    }

    func testImageFilesRemainEditorDrops() {
        for filename in [
            "Cover.png",
            "Photo.jpg",
            "Photo.jpeg",
            "Scan.tif",
            "Scan.tiff",
            "Animation.gif",
            "Photo.heic",
            "Photo.heif"
        ] {
            XCTAssertFalse(
                BOLDDocumentDropRouter
                    .shouldOpenAsDocument(
                        URL(
                            fileURLWithPath:
                                "/tmp/\(filename)"
                        )
                    ),
                filename
            )
        }
    }

    func testRemoteURLDoesNotRouteAsDocument() throws {
        XCTAssertFalse(
            BOLDDocumentDropRouter
                .shouldOpenAsDocument(
                    try XCTUnwrap(
                        URL(
                            string:
                                "https://example.com/file.docx"
                        )
                    )
                )
        )
    }

    func testPasteboardFiltersImageFromDocumentDrop() {
        let pasteboard =
            NSPasteboard(
                name:
                    NSPasteboard.Name(
                        "BOLDDocumentDropRouting-\(UUID().uuidString)"
                    )
            )

        pasteboard.clearContents()

        let docx =
            URL(
                fileURLWithPath:
                    "/tmp/Manuscript.docx"
            )

        let image =
            URL(
                fileURLWithPath:
                    "/tmp/Cover.png"
            )

        XCTAssertTrue(
            pasteboard.writeObjects(
                [
                    docx as NSURL,
                    image as NSURL
                ]
            )
        )

        XCTAssertEqual(
            BOLDDocumentDropRouter
                .documentURLs(
                    from:
                        pasteboard
                ),
            [
                docx
            ]
        )
    }
}
