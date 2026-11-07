import AppKit
import UniformTypeIdentifiers
import XCTest

@testable import BOLDWriter

final class CitationTests: XCTestCase {
    func testAPAInlineCitationUsesSurnameAndYear() {
        let source = CitationSource(
            author: "John Smith",
            title: "History of Writing",
            year: "2024"
        )

        XCTAssertEqual(
            CitationFormatter.citation(
                for: source,
                style: .apa
            ),
            "(Smith, 2024)"
        )
    }

    func testMLAInlineCitationUsesFirstAuthorAndEtAl() {
        let source = CitationSource(
            author: "John Smith; Mary Jones",
            title: "Shared Study",
            year: "2022"
        )

        XCTAssertEqual(
            CitationFormatter.citation(
                for: source,
                style: .mla
            ),
            "(Smith et al.)"
        )
    }

    func testChicagoInlineCitationUsesSurnameAndYear() {
        let source = CitationSource(
            author: "Smith, John",
            title: "Archive",
            year: "1999"
        )

        XCTAssertEqual(
            CitationFormatter.citation(
                for: source,
                style: .chicago
            ),
            "(Smith 1999)"
        )
    }

    func testBibliographySortsSourcesByAuthor()
        throws
    {
        let zulu = CitationSource(
            author: "Zulu, Zoe",
            title: "Later",
            year: "2020"
        )

        let alpha = CitationSource(
            author: "Alpha, Amy",
            title: "Earlier",
            year: "2021"
        )

        let bibliography =
            CitationFormatter.bibliography(
                sources: [
                    zulu,
                    alpha
                ],
                style: .apa
            )

        XCTAssertTrue(
            bibliography.hasPrefix(
                "References\n"
            )
        )

        let alphaRange =
            try XCTUnwrap(
                bibliography.range(
                    of: "Alpha"
                )
            )

        let zuluRange =
            try XCTUnwrap(
                bibliography.range(
                    of: "Zulu"
                )
            )

        XCTAssertLessThan(
            alphaRange.lowerBound,
            zuluRange.lowerBound
        )
    }

    func testContextualCitationDoesNotDuplicateExistingSpace() {
        let source = CitationSource(
            author: "John Smith",
            title: "Book",
            year: "2024"
        )

        XCTAssertEqual(
            CitationFormatter.contextualInlineInsertion(
                source: source,
                style: .apa,
                documentText: "Before after",
                range: NSRange(
                    location: 6,
                    length: 0
                )
            ),
            " (Smith, 2024)"
        )
    }

    func testEvidenceCitationInsertionPreservesSelectedClaimRange() {
        let text = "The migration took place in 1848. Remaining text."
        let claim = (text as NSString).range(of: "The migration took place in 1848.")

        XCTAssertEqual(
            CitationFormatter.insertionRangeAfterSelection(in: text, selection: claim),
            NSRange(location: NSMaxRange(claim), length: 0)
        )
        XCTAssertNil(
            CitationFormatter.insertionRangeAfterSelection(
                in: text,
                selection: NSRange(location: (text as NSString).length + 1, length: 0)
            )
        )
    }

    func testBibliographyBlockAddsParagraphBoundaries() {
        XCTAssertEqual(
            CitationFormatter.contextualBlockInsertion(
                "References\nSmith.",
                documentText: "BeforeAfter",
                range: NSRange(
                    location: 6,
                    length: 0
                )
            ),
            "\nReferences\nSmith.\n"
        )
    }

    func testBibliographyCanSelectOnlySourcesActuallyCitedInManuscript() {
        let cited = CitationSource(author: "John Smith", title: "Book A", year: "2024")
        let unused = CitationSource(author: "Jane Jones", title: "Book B", year: "2023")
        let resolution = DocumentCitations.citedSourceResolution(
            in: "The account appears in the ledger (Smith, 2024).",
            sources: [cited, unused],
            style: .apa
        )

        XCTAssertEqual(resolution.citedSourceIDs, [cited.id])
        XCTAssertTrue(resolution.ambiguousDisplays.isEmpty)
        XCTAssertTrue(CitationFormatter.bibliography(sources: [cited, unused].filter { resolution.citedSourceIDs.contains($0.id) }, style: .apa).contains("Book A"))
        XCTAssertFalse(CitationFormatter.bibliography(sources: [cited, unused].filter { resolution.citedSourceIDs.contains($0.id) }, style: .apa).contains("Book B"))
    }

    func testNativePackagePreservesCitationSourcesAndStyle()
        throws
    {
        let source = CitationSource(
            type: .website,
            author: "Writer, Ada",
            title: "Research Notes",
            year: "2025",
            publisher: "",
            containerTitle: "Example Archive",
            url: "https://example.com"
        )
        var linkedSource = source
        linkedSource.citationDisplayHistory = [.chicago: "(Old Archive 2024)"]

        var metadata = DocumentMetadata(
            title: "Citation Round Trip"
        )

        metadata.citationSources = [linkedSource]
        metadata.citationStyle = .chicago

        let wrapper =
            try BOLDWriterDocument.packageWrapper(
                text: NSAttributedString(
                    string: "Body"
                ),
                metadata: metadata
            )

        let reopened =
            try BOLDWriterDocument(
                fileWrapper: wrapper,
                contentType: .boldWriterDocument
            )

        XCTAssertEqual(
            reopened.metadata.citationSources,
            [linkedSource]
        )

        XCTAssertEqual(
            reopened.metadata.citationStyle,
            .chicago
        )
    }

    func testRevisionRestorePreservesCitationLibrary()
        throws
    {
        let document = BOLDWriterDocument()

        document.replaceText(
            with: NSAttributedString(
                string: "Original"
            )
        )

        let source = CitationSource(
            author: "Scholar, Sam",
            title: "Source One",
            year: "2023"
        )

        document.metadata.citationSources = [source]
        document.metadata.citationStyle = .mla

        XCTAssertTrue(
            document.createRevision(
                named: "With Sources"
            )
        )

        let revision =
            try XCTUnwrap(
                document.metadata.revisions.first
            )

        document.metadata.citationSources = []
        document.metadata.citationStyle = .apa

        try document.restore(revision)

        XCTAssertEqual(
            document.metadata.citationSources,
            [source]
        )

        XCTAssertEqual(
            document.metadata.citationStyle,
            .mla
        )
    }

    func testCitationValidationRejectsDuplicateIdentifiers() {
        let identity = UUID()

        let first = CitationSource(
            id: identity,
            author: "A",
            title: "One"
        )

        let second = CitationSource(
            id: identity,
            author: "B",
            title: "Two"
        )

        XCTAssertThrowsError(
            try DocumentCitations.validate(
                [
                    first,
                    second
                ]
            )
        )
    }
}
