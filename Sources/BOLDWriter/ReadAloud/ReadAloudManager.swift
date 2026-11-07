import AppKit
import AVFoundation
import Foundation

// Only an immutable identity crosses actors. Retaining the utterance until the
// callback is handled also prevents its address being reused by a newer session.
private final class SpeechCallbackIdentity: @unchecked Sendable {
    let identifier: ObjectIdentifier
    private let retainedUtterance: AVSpeechUtterance

    init(_ utterance: AVSpeechUtterance) {
        identifier = ObjectIdentifier(utterance)
        retainedUtterance = utterance
    }
}

struct SpeechPlaybackSession {
    let utterance: AVSpeechUtterance
    let documentRange: NSRange

    var identifier: ObjectIdentifier { ObjectIdentifier(utterance) }

    func highlightRange(for characterRange: NSRange, documentLength: Int) -> NSRange? {
        guard documentRange.location >= 0, documentRange.length >= 0,
              characterRange.location >= 0, characterRange.length > 0,
              characterRange.location <= documentRange.length,
              characterRange.length <= documentRange.length - characterRange.location,
              documentRange.location <= documentLength,
              characterRange.location <= documentLength - documentRange.location else { return nil }
        let location = documentRange.location + characterRange.location
        guard characterRange.length <= documentLength - location else { return nil }
        return NSRange(location: location, length: characterRange.length)
    }
}

@MainActor
final class ReadAloudManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published var rate: Double = 0.48
    @Published var volume: Double = 1.0
    @Published var selectedVoiceIdentifier: String = UserDefaults.standard.string(forKey: "speechVoice") ?? ""
    @Published private(set) var activeLabel = "Stopped"

    private let synthesizer = AVSpeechSynthesizer()
    private weak var textView: NSTextView?
    private var activeSession: SpeechPlaybackSession?
    private var highlightRange: NSRange?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func attach(to textView: NSTextView?) {
        guard self.textView !== textView else { return }
        stop()
        if let storage = self.textView?.textStorage {
            NotificationCenter.default.removeObserver(self, name: NSTextStorage.didProcessEditingNotification, object: storage)
        }
        self.textView = textView
        if let storage = textView?.textStorage {
            NotificationCenter.default.addObserver(self, selector: #selector(textStorageDidChange(_:)), name: NSTextStorage.didProcessEditingNotification, object: storage)
        }
    }

    @objc private func textStorageDidChange(_ notification: Notification) {
        guard let storage = notification.object as? NSTextStorage,
              storage === textView?.textStorage,
              storage.editedMask.contains(.editedCharacters), activeSession != nil else { return }
        stop()
    }

    func read(_ text: String, range: NSRange, label: String, in textView: NSTextView?) {
        stop()
        let documentLength = (text as NSString).length
        guard range.location >= 0, range.length > 0,
              range.location <= documentLength, range.length <= documentLength - range.location else { return }
        attach(to: textView)
        let speech = (text as NSString).substring(with: range)
        let utterance = AVSpeechUtterance(string: speech)
        utterance.rate = Float(min(max(rate.isFinite ? rate : 0.48, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
        utterance.volume = Float(min(max(volume.isFinite ? volume : 1.0, 0), 1))
        if !selectedVoiceIdentifier.isEmpty { utterance.voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) }
        activeSession = SpeechPlaybackSession(utterance: utterance, documentRange: range)
        isSpeaking = true
        isPaused = false
        activeLabel = label
        synthesizer.speak(utterance)
    }

    func readSelection(in editor: EditorController) {
        guard let textView = editor.textView else { return }
        let selected = textView.selectedRange()
        read(textView.string, range: selected, label: "Selection", in: textView)
    }

    func readFromCursor(in editor: EditorController) {
        guard let textView = editor.textView else { return }
        let start = min(max(0, editor.selection.location), (textView.string as NSString).length)
        read(textView.string, range: NSRange(location: start, length: (textView.string as NSString).length - start), label: "From Cursor", in: textView)
    }

    func readParagraph(in editor: EditorController) {
        guard let textView = editor.textView else { return }
        let range = DocumentAnalysis.paragraphRange(at: editor.selection.location, in: textView.string)
        read(textView.string, range: range, label: "Paragraph", in: textView)
    }

    func readDocument(in editor: EditorController) {
        guard let textView = editor.textView else { return }
        let length = (textView.string as NSString).length
        read(textView.string, range: NSRange(location: 0, length: length), label: "Document", in: textView)
    }

    func readSection(in editor: EditorController) {
        guard let textView = editor.textView else { return }
        let range = DocumentAnalysis.sectionRange(at: editor.selection.location, in: textView.attributedString())
        read(textView.string, range: range, label: "Current Section", in: textView)
    }

    func pauseOrResume() {
        if synthesizer.isPaused {
            if synthesizer.continueSpeaking() { isPaused = false }
        } else if synthesizer.isSpeaking {
            if synthesizer.pauseSpeaking(at: .word) { isPaused = true }
        }
    }

    func stop() {
        // Invalidate first: cancellation callbacks may arrive after another read starts.
        activeSession = nil
        if synthesizer.isSpeaking || synthesizer.isPaused { synthesizer.stopSpeaking(at: .immediate) }
        clearHighlight()
        isSpeaking = false
        isPaused = false
        activeLabel = "Stopped"
    }

    func moveSentence(direction: Int, editor: EditorController) {
        guard let textView = editor.textView else { return }
        let ranges = sentenceRanges(textView.string)
        guard !ranges.isEmpty else { return }
        let current = highlightRange?.location ?? editor.selection.location
        let index = ranges.firstIndex(where: { NSLocationInRange(current, $0) }) ?? 0
        let step = direction < 0 ? -1 : direction > 0 ? 1 : 0
        let next = min(max(0, index + step), ranges.count - 1)
        read(textView.string, range: ranges[next], label: "Sentence \(next + 1)", in: textView)
    }

    func moveParagraph(direction: Int, editor: EditorController) {
        guard let textView = editor.textView else { return }
        let source = textView.string as NSString
        guard source.length > 0 else { return }
        let current = highlightRange?.location ?? editor.selection.location
        let paragraph = DocumentAnalysis.paragraphRange(at: current, in: textView.string)
        let location: Int
        if direction < 0 {
            location = max(0, paragraph.location - 1)
        } else if direction > 0 {
            location = min(source.length - 1, NSMaxRange(paragraph))
        } else {
            location = paragraph.location
        }
        read(textView.string, range: DocumentAnalysis.paragraphRange(at: location, in: textView.string), label: "Paragraph", in: textView)
    }

    private func sentenceRanges(_ text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        (text as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (text as NSString).length), options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let identity = SpeechCallbackIdentity(utterance)
        Task { @MainActor [weak self] in
            self?.highlight(characterRange, for: identity.identifier)
        }
    }

    private func highlight(_ characterRange: NSRange, for identifier: ObjectIdentifier) {
        guard let session = activeSession, session.identifier == identifier else { return }
        clearHighlight()
        if let layout = textView?.layoutManager,
           let range = session.highlightRange(for: characterRange, documentLength: textView?.textStorage?.length ?? 0) {
            layout.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), forCharacterRange: range)
            highlightRange = range
            textView?.scrollRangeToVisible(range)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identity = SpeechCallbackIdentity(utterance)
        Task { @MainActor [weak self] in
            self?.completeSession(identity.identifier, label: "Finished")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identity = SpeechCallbackIdentity(utterance)
        Task { @MainActor [weak self] in
            self?.completeSession(identity.identifier, label: "Stopped")
        }
    }

    private func completeSession(_ identifier: ObjectIdentifier, label: String) {
        guard activeSession?.identifier == identifier else { return }
        activeSession = nil
        clearHighlight()
        isSpeaking = false
        isPaused = false
        activeLabel = label
    }

    static func clampedHighlightRange(_ range: NSRange, documentLength: Int) -> NSRange? {
        guard range.location >= 0, range.length > 0,
              range.location < documentLength else { return nil }
        return NSRange(location: range.location, length: min(range.length, documentLength - range.location))
    }

    private func clearHighlight() {
        if let range = highlightRange,
           let safeRange = Self.clampedHighlightRange(range, documentLength: textView?.textStorage?.length ?? 0) {
            textView?.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: safeRange)
        }
        highlightRange = nil
    }
}
