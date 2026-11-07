import AppKit
import XCTest
@testable import BOLDWriter

final class DocumentAnalysisTests: XCTestCase {
    func testOutlineExcludesTitleAndFindsHeadingAfterPageBreak() {
        let text = NSMutableAttributedString(string: "Book Title\nBody\n\u{000C}Appendix\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 24)])
        text.addAttribute(.boldWriterStyle, value: WriterStyle.title.rawValue, range: NSRange(location: 0, length: 11))
        text.addAttribute(.boldWriterStyle, value: WriterStyle.normal.rawValue, range: NSRange(location: 11, length: 5))
        text.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: (text.string as NSString).range(of: "Appendix"))
        let outline = DocumentAnalysis.outline(for: text)
        XCTAssertEqual(outline.map(\.title), ["Appendix"])
    }
    func testStatistics() {
        let stats = DocumentAnalysis.statistics(for: "One two three.\nA second paragraph.", headingCount: 2)
        XCTAssertEqual(stats.words, 6)
        XCTAssertEqual(stats.paragraphs, 2)
        XCTAssertEqual(stats.headings, 2)
        XCTAssertEqual(stats.estimatedMinutes, 1)
    }

    func testSearchOptionsAndContext() {
        let text = "Faithful faith FAITH faithfulness\nDaniel 7 and Daniel 9"
        XCTAssertEqual(DocumentAnalysis.search("faith", in: text).count, 4)
        XCTAssertEqual(DocumentAnalysis.search("faith", in: text, wholeWord: true).count, 2)
        XCTAssertEqual(DocumentAnalysis.search("Daniel [79]", in: text, regularExpression: true).count, 2)
        XCTAssertEqual(DocumentAnalysis.search("FAITH", in: text, matchCase: true, wholeWord: true).count, 1)
    }

    func testOutlineUsesNamedStyles() {
        let value = NSMutableAttributedString(string: "Book\nChapter\nBody\n")
        value.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: NSRange(location: 0, length: 5))
        value.addAttribute(.boldWriterStyle, value: WriterStyle.heading2.rawValue, range: NSRange(location: 5, length: 8))
        let outline = DocumentAnalysis.outline(for: value)
        XCTAssertEqual(outline.map(\.title), ["Book", "Chapter"])
        XCTAssertEqual(outline.map(\.level), [1, 2])
    }

    func testSectionRangeEndsAtPeerHeading() {
        let value = NSMutableAttributedString(string: "One\ntext\nTwo\nmore\n")
        value.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: NSRange(location: 0, length: 4))
        value.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: NSRange(location: 9, length: 4))
        XCTAssertEqual(DocumentAnalysis.sectionRange(at: 5, in: value), NSRange(location: 0, length: 9))
    }

    func testQuarterMillionWordAnalysisPerformance() {
        let manuscript = Array(repeating: "original manuscript sentence", count: 83_334).joined(separator: " ")
        measure {
            let stats = DocumentAnalysis.statistics(for: manuscript)
            XCTAssertGreaterThanOrEqual(stats.words, 250_000)
        }
    }
    func testFrontMatterSectionEndsBeforeFirstHeading() {
        let value = NSMutableAttributedString(string: "Preface\nChapter\nBody\n")
        value.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: NSRange(location: 8, length: 8))
        XCTAssertEqual(DocumentAnalysis.sectionRange(at: 2, in: value), NSRange(location: 0, length: 8))
    }

    func testSectionIncludesChildHeadingsAndStopsAtPeer() {
        let value = NSMutableAttributedString(string: "One\nChild\nBody\nTwo\n")
        value.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: NSRange(location: 0, length: 4))
        value.addAttribute(.boldWriterStyle, value: WriterStyle.heading2.rawValue, range: NSRange(location: 4, length: 6))
        value.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: NSRange(location: 15, length: 4))
        XCTAssertEqual(DocumentAnalysis.sectionRange(at: 1, in: value), NSRange(location: 0, length: 15))
        XCTAssertEqual(DocumentAnalysis.sectionRange(at: 11, in: value), NSRange(location: 4, length: 11))
        XCTAssertEqual(DocumentAnalysis.sectionRange(at: 16, in: value), NSRange(location: 15, length: 4))
    }

    func testSectionWithoutHeadingsCoversDocumentIncludingEmoji() {
        let value = NSAttributedString(string: "📖 Preface\nBody")
        XCTAssertEqual(DocumentAnalysis.sectionRange(at: 0, in: value), NSRange(location: 0, length: value.length))
        XCTAssertEqual(DocumentAnalysis.sectionRange(at: 0, in: NSAttributedString(string: "")), NSRange(location: 0, length: 0))
    }

}
