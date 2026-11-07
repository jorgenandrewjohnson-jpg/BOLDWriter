import AppKit
import XCTest

@testable import BOLDWriter

final class DocumentTranslationTests:
    XCTestCase {

    func testTranslationLanguageCatalogHasUniqueIdentifiers() {
        let identifiers =
            DocumentTranslationLanguage
                .catalog
                .map(
                    \.id
                )

        XCTAssertEqual(
            identifiers.count,
            Set(
                identifiers
            ).count
        )

        XCTAssertTrue(
            identifiers.contains(
                "es"
            )
        )

        XCTAssertTrue(
            identifiers.contains(
                "fr"
            )
        )

        XCTAssertTrue(
            identifiers.contains(
                "de"
            )
        )
    }

    func testTranslationBuilderPreservesParagraphVisualFormatting() throws {
        let source =
            NSMutableAttributedString()

        let firstFont =
            NSFont.boldSystemFont(
                ofSize:
                    18
            )

        let secondFont =
            NSFont.systemFont(
                ofSize:
                    13
            )

        source.append(
            NSAttributedString(
                string:
                    "First paragraph",
                attributes: [
                    .font:
                        firstFont
                ]
            )
        )

        source.append(
            NSAttributedString(
                string:
                    "\n",
                attributes: [
                    .font:
                        firstFont
                ]
            )
        )

        source.append(
            NSAttributedString(
                string:
                    "Second paragraph",
                attributes: [
                    .font:
                        secondFont
                ]
            )
        )

        let translated =
            DocumentTranslationBuilder
                .attributedReplacement(
                    source:
                        source,
                    translatedText:
                        "Primer párrafo\nSegundo párrafo"
                )

        XCTAssertEqual(
            translated.string,
            "Primer párrafo\nSegundo párrafo"
        )

        let first =
            try XCTUnwrap(
                translated.attribute(
                    .font,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? NSFont
            )

        let secondLocation =
            (
                translated.string
                    as NSString
            )
            .range(
                of:
                    "Segundo"
            )
            .location

        let second =
            try XCTUnwrap(
                translated.attribute(
                    .font,
                    at:
                        secondLocation,
                    effectiveRange:
                        nil
                )
                as? NSFont
            )

        XCTAssertEqual(
            first.pointSize,
            18,
            accuracy:
                0.01
        )

        XCTAssertTrue(
            first.fontDescriptor
                .symbolicTraits
                .contains(
                    .bold
                )
        )

        XCTAssertEqual(
            second.pointSize,
            13,
            accuracy:
                0.01
        )
    }

    func testTranslationBuilderDoesNotCopySemanticAttributes() {
        let source =
            NSMutableAttributedString(
                string:
                    "Original",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        ),
                    .link:
                        URL(
                            string:
                                "https://example.com"
                        )!
                ]
            )

        let translated =
            DocumentTranslationBuilder
                .attributedReplacement(
                    source:
                        source,
                    translatedText:
                        "Traducido"
                )

        XCTAssertNil(
            translated.attribute(
                .link,
                at:
                    0,
                effectiveRange:
                    nil
            )
        )

        XCTAssertNotNil(
            translated.attribute(
                .font,
                at:
                    0,
                effectiveRange:
                    nil
            )
        )
    }
}
