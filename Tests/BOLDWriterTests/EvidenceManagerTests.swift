import AppKit
import XCTest

@testable import BOLDWriter

@MainActor final class EvidenceManagerTests: XCTestCase {
    private struct SyntheticLibrary: EvidenceLibraryReferenceResolving {
        private struct PassagePayload: Codable { var passageID: UUID; var quotation: String }

        func passageReference(for source: CitationSource, exactQuotation: String) -> EvidenceLibraryPassageLink? {
            guard !exactQuotation.isEmpty,
                  let bytes = try? JSONEncoder().encode(PassagePayload(passageID: UUID(), quotation: exactQuotation)) else { return nil }
            return EvidenceLibraryPassageLink(documentReference: UUID().uuidString, passageReference: bytes)
        }

        func resolve(_ serializedReference: Data) -> EvidenceLibraryReferenceResolution {
            guard (try? JSONDecoder().decode(PassagePayload.self, from: serializedReference)) != nil else {
                return EvidenceLibraryReferenceResolution(status: .unresolved, verifiedLocation: nil)
            }
            return EvidenceLibraryReferenceResolution(status: .current, verifiedLocation: "page 1, section 1")
        }
    }

    func testClaimEvidenceAndExtendedCitationSourceRoundTrip() throws {
        let manuscript = "The river froze in 1848 according to the local record."
        let claimText = "The river froze in 1848"
        let range = (manuscript as NSString).range(of: claimText)
        let anchor = try XCTUnwrap(ClaimAnchor.make(text: manuscript, range: range))
        let source = CitationSource(type: .article, author: "A. Researcher", title: "Winter Ledger", year: "1848", publisher: "Town Archive", containerTitle: "Ledger", url: "", publicationDate: "1848-02", sourceLocation: "page 4", quotation: "Ice covered the river.", researchNotes: "Checked against the transcription.", verificationStatus: .authorChecked)
        let evidence = ClaimEvidence(anchor: anchor, sourceID: source.id, kind: .supporting, quotation: "Ice covered the river.", sourceLocation: "page 4", authorNote: "Contemporary account", verificationStatus: .authorChecked)
        let counterEvidence = ClaimEvidence(anchor: anchor, sourceID: source.id, kind: .challenging, quotation: "The river remained open through February.", sourceLocation: "page 9", authorNote: "Conflicting diary entry", verificationStatus: .unverified)
        var metadata = DocumentMetadata(title: "Evidence Round Trip")
        metadata.citationSources = [source]
        metadata.claimEvidence = [evidence, counterEvidence]
        let wrapper = try BOLDWriterDocument.packageWrapper(text: NSAttributedString(string: manuscript), metadata: metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument)
        let manuscriptHash = EvidenceVerification.sha256(Data(manuscript.utf8))
        XCTAssertEqual(reopened.metadata.citationSources, [source])
        XCTAssertEqual(reopened.metadata.claimEvidence, [evidence, counterEvidence])
        XCTAssertTrue(try XCTUnwrap(reopened.metadata.claimEvidence?.first).anchor.resolves(in: reopened.text.string))
        XCTAssertEqual(EvidenceVerification.sha256(Data(reopened.text.string.utf8)), manuscriptHash)
        XCTAssertEqual(try XCTUnwrap(reopened.metadata.claimEvidence?.first).anchor.selectedTextSHA256, EvidenceVerification.sha256(Data(claimText.utf8)))
    }

    func testMissingSourceAndChangedManuscriptAreWarnings() throws {
        let manuscript = "A measurable claim remains unchanged."
        let anchor = try XCTUnwrap(ClaimAnchor.make(text: manuscript, range: (manuscript as NSString).range(of: "A measurable claim")))
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("evidence-source-missing-\(UUID().uuidString).pdf")
        var source = CitationSource(title: "Missing", localFilePath: missing.path)
        let relation = ClaimEvidence(anchor: anchor, sourceID: source.id, kind: .challenging, quotation: "The opposite result was measured.", sourceLocation: "page 12", authorNote: "Counterexample", verificationStatus: .unverified)
        XCTAssertTrue(EvidenceVerification.sourceWarnings(for: source, evidence: relation, manuscript: "A substantially revised claim.").contains("The manuscript passage changed or moved."))
        XCTAssertTrue(EvidenceVerification.sourceWarnings(for: source, evidence: relation, manuscript: manuscript).contains("The source file is missing."))
        source.localFilePath = "\u{0}"
        XCTAssertNotNil(try? JSONEncoder().encode(source))
    }

    func testClaimAnchorIdentitySurvivesCitationTextInsertedAfterSelectedClaim() throws {
        let original = "The migration took place in 1848.\nThe surviving record remains disputed."
        let changed = "The migration took place in 1848. (Example, 1848)\nThe surviving record remains disputed."
        let originalAnchor = try XCTUnwrap(
            ClaimAnchor.make(
                text: original,
                range: (original as NSString).range(of: "The migration took place in 1848.")
            )
        )
        let changedAnchor = try XCTUnwrap(
            ClaimAnchor.make(
                text: changed,
                range: (changed as NSString).range(of: "The migration took place in 1848.")
            )
        )

        XCTAssertNotEqual(originalAnchor, changedAnchor, "Context fingerprints should reflect nearby manuscript edits.")
        XCTAssertTrue(originalAnchor.identifiesSameSelection(as: changedAnchor))
        XCTAssertTrue(originalAnchor.resolves(in: changed))

        let editedClaim = "The migration happened in 1848. (Example, 1848)\nThe surviving record remains disputed."
        let editedAnchor = try XCTUnwrap(
            ClaimAnchor.make(
                text: editedClaim,
                range: (editedClaim as NSString).range(of: "The migration happened in 1848.")
            )
        )
        XCTAssertFalse(originalAnchor.identifiesSameSelection(as: editedAnchor))
    }

    func testEvidenceCannotResolveToUnattachedCitationSource() throws {
        let anchor = try XCTUnwrap(ClaimAnchor.make(text: "A claim.", range: NSRange(location: 0, length: 7)))
        let evidence = ClaimEvidence(anchor: anchor, sourceID: UUID(), kind: .contextual, quotation: "Background text", sourceLocation: "section 1", authorNote: "Context", verificationStatus: .unverified)
        XCTAssertThrowsError(try DocumentEvidence.validate([evidence], sources: []))
    }

    func testSourceFingerprintDetectsChangedLocalFixture() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("evidence-fixture-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: path) }
        let original = Data("A source quotation, exactly as printed.".utf8)
        try original.write(to: path)
        let manuscript = "The study reports a result."
        let anchor = try XCTUnwrap(ClaimAnchor.make(text: manuscript, range: (manuscript as NSString).range(of: "The study reports a result.")))
        let source = CitationSource(title: "Synthetic Research Fixture", localFilePath: path.path, contentFingerprint: EvidenceVerification.sha256(original))
        let evidence = ClaimEvidence(anchor: anchor, sourceID: source.id, kind: .supporting, quotation: "A source quotation, exactly as printed.", sourceLocation: "page 1", authorNote: "Fixture", verificationStatus: .unverified)
        XCTAssertTrue(EvidenceVerification.sourceWarnings(for: source, evidence: evidence, manuscript: manuscript).isEmpty)
        try Data("A changed quotation.".utf8).write(to: path)
        XCTAssertTrue(EvidenceVerification.sourceWarnings(for: source, evidence: evidence, manuscript: manuscript).contains("The source file changed since it was recorded."))
    }

    func testKnowledgeLibraryAdapterKeepsOpaqueReferencesOnly() throws {
        let fixture = SyntheticLibrary()
        let source = CitationSource(title: "Fixture source")
        let link = try XCTUnwrap(fixture.passageReference(for: source, exactQuotation: "A precise excerpt."))
        let resolution = fixture.resolve(link.passageReference)
        XCTAssertEqual(resolution.status, .current)
        XCTAssertEqual(resolution.verifiedLocation, "page 1, section 1")
        XCTAssertNotEqual(link.documentReference, source.id.uuidString)
    }

    func testDuplicateSourceDetectionDoesNotDeleteEitherRecord() {
        let first = CitationSource(author: "A Author", title: "Same Study", year: "2024")
        let second = CitationSource(author: "A Author", title: "Same Study", year: "2024")
        XCTAssertEqual(DocumentEvidence.duplicateSourceIDs(in: [first, second]).first?.count, 2)
        XCTAssertNotEqual(first.id, second.id)
    }
}
