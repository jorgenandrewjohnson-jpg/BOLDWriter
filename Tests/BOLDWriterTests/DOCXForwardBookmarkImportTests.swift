import Foundation
import XCTest
@testable import BOLDWriter

final class DOCXForwardBookmarkImportTests:
    XCTestCase
{
    func testWordSystemAndGeneratedBookmarksAreNotUserBookmarks() {
        XCTAssertFalse(
            DOCXImporter
                .shouldRestoreWordBookmarkAsUserBookmark(
                    "_TocGenerated"
                )
        )

        XCTAssertFalse(
            DOCXImporter
                .shouldRestoreWordBookmarkAsUserBookmark(
                    "319n0033w412"
                )
        )
    }

    func testLegitimateWordBookmarkNamesRemainUserBookmarks() {
        XCTAssertTrue(
            DOCXImporter
                .shouldRestoreWordBookmarkAsUserBookmark(
                    "BookmarkOne"
                )
        )

        XCTAssertTrue(
            DOCXImporter
                .shouldRestoreWordBookmarkAsUserBookmark(
                    "Inserted_Word"
                )
        )

        XCTAssertTrue(
            DOCXImporter
                .shouldRestoreWordBookmarkAsUserBookmark(
                    "A1"
                )
        )
    }

    func testRawBookmarkValidationIncludesForwardAndGeneratedTargets() throws {
        let xml =
            try XMLDocument(
                xmlString:
                    """
                    <w:document
                        xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
                      <w:body>
                        <w:p>
                          <w:hyperlink w:anchor="_Later">
                            <w:r>
                              <w:t>Jump</w:t>
                            </w:r>
                          </w:hyperlink>
                        </w:p>
                        <w:p>
                          <w:bookmarkStart
                              w:id="1"
                              w:name="319n0033w412"/>
                          <w:bookmarkEnd
                              w:id="1"/>
                        </w:p>
                        <w:p>
                          <w:bookmarkStart
                              w:id="2"
                              w:name="_Later"/>
                          <w:bookmarkEnd
                              w:id="2"/>
                        </w:p>
                        <w:p>
                          <w:bookmarkStart
                              w:id="3"
                              w:name="BookmarkOne"/>
                          <w:bookmarkEnd
                              w:id="3"/>
                        </w:p>
                      </w:body>
                    </w:document>
                    """,
                options:
                    []
            )

        XCTAssertEqual(
            Set(
                try DOCXImporter
                    .allBookmarkNamesForHyperlinkValidation(
                        in:
                            xml
                    )
            ),
            Set(
                [
                    "319n0033w412",
                    "_Later",
                    "BookmarkOne"
                ]
            )
        )
    }
}
