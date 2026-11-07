import AppKit
import AVFoundation
import XCTest
@testable import BOLDWriter

@MainActor
final class ReadAloudRegressionTests: XCTestCase {
    func testSpeechHighlightMapsToOriginalDocumentScope() {
        let utterance = AVSpeechUtterance(string: "A short paragraph")
        let session = SpeechPlaybackSession(utterance: utterance, documentRange: NSRange(location: 25, length: 17))
        XCTAssertEqual(session.identifier, ObjectIdentifier(utterance))
        XCTAssertEqual(session.highlightRange(for: NSRange(location: 2, length: 5), documentLength: 100), NSRange(location: 27, length: 5))
    }

    func testSpeechHighlightRejectsRangesOutsideUtteranceOrChangedDocument() {
        let session = SpeechPlaybackSession(utterance: AVSpeechUtterance(string: "Hello"), documentRange: NSRange(location: 10, length: 5))
        XCTAssertNil(session.highlightRange(for: NSRange(location: 4, length: 2), documentLength: 30))
        XCTAssertNil(session.highlightRange(for: NSRange(location: 0, length: 5), documentLength: 12))
        XCTAssertNil(session.highlightRange(for: NSRange(location: 0, length: 1), documentLength: 8))
        XCTAssertNil(session.highlightRange(for: NSRange(location: 5, length: 0), documentLength: 30))
    }

    func testMalformedSpeechRangesDoNotOverflow() {
        let session = SpeechPlaybackSession(utterance: AVSpeechUtterance(string: "Hello"), documentRange: NSRange(location: 10, length: 5))
        for range in [NSRange(location: NSNotFound, length: 5), NSRange(location: -1, length: 2), NSRange(location: 1, length: Int.max), NSRange(location: 0, length: -1)] {
            XCTAssertNil(session.highlightRange(for: range, documentLength: 30))
        }
        let invalidSession = SpeechPlaybackSession(utterance: AVSpeechUtterance(string: "Hello"), documentRange: NSRange(location: Int.max, length: 5))
        XCTAssertNil(invalidSession.highlightRange(for: NSRange(location: 1, length: 1), documentLength: 30))
    }

    func testClearingHighlightClampsAfterDocumentShrinks() {
        XCTAssertEqual(ReadAloudManager.clampedHighlightRange(NSRange(location: 5, length: 20), documentLength: 10), NSRange(location: 5, length: 5))
        XCTAssertEqual(ReadAloudManager.clampedHighlightRange(NSRange(location: 5, length: Int.max), documentLength: 10), NSRange(location: 5, length: 5))
        XCTAssertNil(ReadAloudManager.clampedHighlightRange(NSRange(location: 10, length: 2), documentLength: 10))
        XCTAssertNil(ReadAloudManager.clampedHighlightRange(NSRange(location: NSNotFound, length: 2), documentLength: 10))
        XCTAssertNil(ReadAloudManager.clampedHighlightRange(NSRange(location: -1, length: 2), documentLength: 10))
        XCTAssertNil(ReadAloudManager.clampedHighlightRange(NSRange(location: 0, length: 2), documentLength: 0))
    }

    func testInvalidReadRequestsNeverStartSpeech() {
        let manager = ReadAloudManager()
        for range in [NSRange(location: NSNotFound, length: 1), NSRange(location: -1, length: 2), NSRange(location: 0, length: Int.max), NSRange(location: 5, length: 1), NSRange(location: 0, length: 0)] {
            manager.read("Hello", range: range, label: "Invalid", in: nil)
            XCTAssertFalse(manager.isSpeaking)
            XCTAssertFalse(manager.isPaused)
            XCTAssertEqual(manager.activeLabel, "Stopped")
        }
    }

    func testDelayedCallbacksAfterStopDoNotChangePlaybackOrFormatting() async throws {
        let manager = ReadAloudManager()
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let text = NSAttributedString(string: "Unchanged manuscript", attributes: [.backgroundColor: NSColor.systemBlue])
        view.textStorage?.setAttributedString(text)
        manager.attach(to: view)
        manager.stop()
        let oldUtterance = AVSpeechUtterance(string: "Older speech")
        let synthesizer = AVSpeechSynthesizer()
        manager.speechSynthesizer(synthesizer, willSpeakRangeOfSpeechString: NSRange(location: 0, length: 5), utterance: oldUtterance)
        manager.speechSynthesizer(synthesizer, didFinish: oldUtterance)
        manager.speechSynthesizer(synthesizer, didCancel: oldUtterance)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertFalse(manager.isSpeaking)
        XCTAssertFalse(manager.isPaused)
        XCTAssertEqual(manager.activeLabel, "Stopped")
        XCTAssertTrue(text.isEqual(to: view.attributedString()))
    }
}
