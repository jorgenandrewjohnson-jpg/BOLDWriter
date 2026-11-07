import XCTest
import AVFoundation
@testable import BOLDWriter

final class AudiobookStudioModelTests: XCTestCase {
    func testLongAndUnicodeTextIsSplitWithinProviderRequestLimit() {
        let paragraph = String(repeating: "Yeshua שלום λόγος 👋 ", count: 900)
        let text = (0..<12).map { "Chapter \($0 + 1)\n\(paragraph)" }.joined(separator: "\n\n")
        let chunks = AudiobookProjectManifest.chunks(text, maximumCharacters: 1200)
        XCTAssertGreaterThan(chunks.count, 12)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 1200 })
        XCTAssertEqual(chunks.joined().filter { !$0.isWhitespace }, text.filter { !$0.isWhitespace })
    }

    func testChunkingRespectsSmallRequestsAndEmptyInput() {
        XCTAssertEqual(AudiobookProjectManifest.chunks("", maximumCharacters: 3), [])
        XCTAssertEqual(AudiobookProjectManifest.chunks("One. Two. Three.", maximumCharacters: 6).map(\.utf16.count), [4, 4, 6])
        XCTAssertTrue(AudiobookProjectManifest.chunks("A🙂B", maximumCharacters: 2).allSatisfy { $0.utf16.count <= 2 })
    }

    func testChapterFingerprintChangesWithTextAndNarrator() {
        let first = AudiobookChapter(id: "ch1", title: "One", text: "Same text", voiceIdentifier: "voice-a")
        let same = AudiobookChapter(id: "ch1", title: "One", text: "Same text", voiceIdentifier: "voice-a")
        let changedVoice = AudiobookChapter(id: "ch1", title: "One", text: "Same text", voiceIdentifier: "voice-b")
        let changedText = AudiobookChapter(id: "ch1", title: "One", text: "Changed text", voiceIdentifier: "voice-a")
        XCTAssertEqual(first.fingerprint, same.fingerprint)
        XCTAssertNotEqual(first.fingerprint, changedVoice.fingerprint)
        XCTAssertNotEqual(first.fingerprint, changedText.fingerprint)
    }

    func testPronunciationSubstitutionIsNonDestructiveAndLocaleAware() {
        let source = "YHVH met YHVHism in the story."
        let rule = PronunciationRule(writtenTerm: "YHVH", spokenForm: "Yahweh", locale: "en", scope: .project, matching: .wholeWord, caseSensitive: true)
        let spoken = PronunciationProcessor.apply(source, rules: [rule], locale: "en-US")
        XCTAssertEqual(spoken, "Yahweh met YHVHism in the story.")
        XCTAssertEqual(source, "YHVH met YHVHism in the story.")
        XCTAssertEqual(PronunciationProcessor.apply(source, rules: [rule], locale: "fr-FR"), source)
    }

    func testExplicitChapterHeadingsAreDetectedWithoutChangingSource() {
        let source = "Opening text.\nChapter One: The River\nYHVH and λόγος.\nPart II — The Journey\nFinal text."
        let headings = ChapterHeadingParser.explicitHeadings(in: source)
        XCTAssertEqual(headings.map(\.title), ["Chapter One: The River", "Part II — The Journey"])
        XCTAssertEqual(headings.map { (source as NSString).substring(with: $0.range) }, headings.map(\.title))
        XCTAssertTrue(source.contains("YHVH and λόγος."))
    }

    func testProjectManifestRoundTripsWithoutCredentialFields() throws {
        var chapter = AudiobookChapter(id: "chapter-1", title: "Opening", text: "A Unicode passage: שלום.")
        let generatedURL = URL(fileURLWithPath: "/tmp/audiobook-segment.caf")
        chapter.audioFiles = [generatedURL]
        chapter.audioSegments = [AudiobookAudioSegment(index: 0, fingerprint: "segment-fingerprint", url: generatedURL)]
        chapter.state = .complete
        let manifest = AudiobookProjectManifest(sourceURL: URL(fileURLWithPath: "/tmp/sample.boldwriter"), sourceFingerprint: AudiobookChapter.digest(chapter.text), title: "Sample", author: "Author", chapters: [chapter])
        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(AudiobookProjectManifest.self, from: encoded)
        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(decoded.chapters[0].audioSegments?.first?.url, generatedURL)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).localizedCaseInsensitiveContains("apiKey"))
    }

    func testChapterInclusionAndNarratorOverridesPersist() throws {
        var included = AudiobookChapter(id: "one", title: "One", text: "First.", voiceIdentifier: "voice-a")
        included.included = true
        included.narratorProviderIdentifier = "elevenlabs"
        included.narratorModelIdentifier = "model-v3"
        included.sourceLocation = 42
        included.passageNarratorAssignments = [AudiobookPassageNarratorAssignment(
            id: "passage-one-middle", location: 0, length: 5,
            textFingerprint: AudiobookChapter.digest("First"),
            providerIdentifier: "apple.system", voiceIdentifier: "voice-passage"
        )]
        var excluded = AudiobookChapter(id: "two", title: "Two", text: "Second.", voiceIdentifier: "voice-b")
        excluded.included = false
        let project = AudiobookProjectManifest(sourceFingerprint: "source", title: "Book", author: "Author", chapters: [included, excluded])
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(AudiobookProjectManifest.self, from: data)
        XCTAssertEqual(decoded.chapters.map(\.included), [true, false])
        XCTAssertEqual(decoded.chapters.map(\.voiceIdentifier), ["voice-a", "voice-b"])
        XCTAssertEqual(decoded.chapters[0].narratorProviderIdentifier, "elevenlabs")
        XCTAssertEqual(decoded.chapters[0].narratorModelIdentifier, "model-v3")
        XCTAssertEqual(decoded.chapters[0].sourceLocation, 42)
        XCTAssertEqual(decoded.chapters[0].passageNarratorAssignments?.first?.voiceIdentifier, "voice-passage")
        XCTAssertNil(decoded.chapters[1].narratorProviderIdentifier)
    }

    func testExplicitPassageNarratorSplitsOnlyMarkedTextAndInvalidatesWhenTextChanges() {
        var chapter = AudiobookChapter(id: "one", title: "One", text: "Opening passage, then another.")
        let source = chapter.text as NSString
        let marked = source.range(of: "passage")
        chapter.passageNarratorAssignments = [AudiobookPassageNarratorAssignment(
            id: "marked-passage", location: marked.location, length: marked.length,
            textFingerprint: AudiobookChapter.digest(source.substring(with: marked)),
            providerIdentifier: "apple.system", voiceIdentifier: "voice-passage"
        )]

        let ranges = chapter.narrationRanges()
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(ranges.filter { $0.passageAssignment != nil }.map { source.substring(with: $0.range) }, ["passage"])
        XCTAssertEqual(ranges.map { source.substring(with: $0.range) }.joined(), chapter.text)

        chapter.text.replaceSubrange(chapter.text.range(of: "passage")!, with: "section")
        let changed = chapter.narrationRanges()
        XCTAssertFalse(changed.contains { $0.passageAssignment != nil })
        XCTAssertEqual(changed.map { (chapter.text as NSString).substring(with: $0.range) }.joined(), chapter.text)
    }

    func testOlderChapterManifestWithoutPassageFieldsStillLoads() throws {
        let json = #"{"id":"legacy","title":"Opening","text":"Hello.","fingerprint":"legacy-fingerprint","voiceIdentifier":null,"included":true,"state":"queued","audioFiles":null,"audioSegments":null}"#.data(using: .utf8)!
        let chapter = try JSONDecoder().decode(AudiobookChapter.self, from: json)
        XCTAssertNil(chapter.sourceLocation)
        XCTAssertNil(chapter.passageNarratorAssignments)
        XCTAssertEqual(chapter.narrationRanges().map { (chapter.text as NSString).substring(with: $0.range) }, ["Hello."])
    }

    func testLargeSharePolicyWarnsAtAttachmentCautionThreshold() {
        XCTAssertFalse(AudiobookSharePolicy.shouldWarn(fileSizeBytes: AudiobookSharePolicy.attachmentCautionThresholdBytes - 1))
        XCTAssertTrue(AudiobookSharePolicy.shouldWarn(fileSizeBytes: AudiobookSharePolicy.attachmentCautionThresholdBytes))
        XCTAssertTrue(AudiobookSharePolicy.shouldWarn(fileSizeBytes: AudiobookSharePolicy.attachmentCautionThresholdBytes + 1))
    }

    func testElevenLabsModelCatalogUsesAccountProvidedCapabilities() throws {
        let json = #"{"model_id":"account-model","name":"Narration Model","can_do_text_to_speech":true,"maximum_text_length_per_request":10000}"#.data(using: .utf8)!
        let model = try JSONDecoder().decode(ElevenLabsModel.self, from: json)
        XCTAssertEqual(model.model_id, "account-model")
        XCTAssertEqual(model.can_do_text_to_speech, true)
        XCTAssertEqual(model.maximum_text_length_per_request, 10_000)
    }

    func testElevenLabsRequestSizeIsRejectedBeforeNetworkAccess() async {
        let provider = ElevenLabsProvider(apiKey: "test-only")
        do {
            _ = try await provider.synthesize(text: "too long", voiceID: "voice", modelID: "model", limit: 4)
            XCTFail("Oversized requests must be rejected before a network call.")
        } catch let ElevenLabsAPIError.requestTooLarge(count, limit) {
            XCTAssertEqual(count, 8)
            XCTAssertEqual(limit, 4)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testInstalledMacVoiceRendersAndDecodesLocalAudio() async throws {
        guard let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("en-") }) else {
            throw XCTSkip("No installed English macOS speech voice is available on this test host.")
        }
        let directory: URL
        if let evidenceDirectory = ProcessInfo.processInfo.environment["BOLD_AUDIOBOOK_EVIDENCE_DIR"] {
            directory = URL(fileURLWithPath: evidenceDirectory, isDirectory: true).appendingPathComponent("NativeVoice", isDirectory: true)
        } else {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("BOLD-Audiobook-Acceptance-\(UUID().uuidString)", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preserveEvidence = ProcessInfo.processInfo.environment["BOLD_AUDIOBOOK_EVIDENCE_DIR"] != nil
        defer { if !preserveEvidence { try? FileManager.default.removeItem(at: directory) } }

        let files = try await LocalSpeechRenderer.render("A short local narration sample.", voice: voice, rate: 0.48, directory: directory, basename: "sample")
        XCTAssertEqual(files.count, 1)
        let audio = try AVAudioFile(forReading: files[0])
        let duration = Double(audio.length) / audio.processingFormat.sampleRate
        XCTAssertGreaterThan(duration, 0.1)
        XCTAssertGreaterThan(audio.length, 0)
        let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(min(audio.length, 4096)))!
        try audio.read(into: buffer)
        XCTAssertGreaterThan(buffer.frameLength, 0)
        print("Native voice \(voice.name) (\(voice.language), quality \(voice.quality.rawValue)) rendered \(duration) seconds to CAF and decoded \(buffer.frameLength) frames.")
    }

    @MainActor
    func testCompleteBookExportsAsDecodableWAVAndM4A() async throws {
        guard let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("en-") }) else {
            throw XCTSkip("No installed English macOS speech voice is available on this test host.")
        }
        let evidenceDirectory = ProcessInfo.processInfo.environment["BOLD_AUDIOBOOK_EVIDENCE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("NativeExport", isDirectory: true) }
        let directory = evidenceDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("BOLD-Audiobook-Export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { if evidenceDirectory == nil { try? FileManager.default.removeItem(at: directory) } }
        let source = try await LocalSpeechRenderer.render("A chapter that becomes part of a complete audiobook.", voice: voice, rate: 0.48, directory: directory, basename: "chapter")
        let sourceFile = try AVAudioFile(forReading: source[0])
        let expectedDuration = Double(sourceFile.length) / sourceFile.processingFormat.sampleRate * 2
        let orderedSources = [source[0], source[0]]
        let wav = directory.appendingPathComponent("complete.wav")
        try AudiobookAudioExporter.exportWAV(sources: orderedSources, to: wav)
        let wavFile = try AVAudioFile(forReading: wav)
        XCTAssertEqual(wavFile.fileFormat.sampleRate, 44_100, accuracy: 0.1)
        XCTAssertEqual(wavFile.fileFormat.channelCount, 2)
        XCTAssertEqual(wavFile.fileFormat.commonFormat, .pcmFormatInt16)
        XCTAssertGreaterThan(wavFile.length, 0)
        XCTAssertEqual(Double(wavFile.length) / wavFile.fileFormat.sampleRate, expectedDuration, accuracy: 0.1)

        let m4a = directory.appendingPathComponent("complete.m4a")
        try await AudiobookAudioExporter.exportM4A(sources: orderedSources, title: "Sample Book", author: "Test Author", to: m4a)
        let asset = AVURLAsset(url: m4a)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(duration), expectedDuration, accuracy: 0.15)
        let m4aFile = try AVAudioFile(forReading: m4a)
        let decoded = AVAudioPCMBuffer(pcmFormat: m4aFile.processingFormat, frameCapacity: 4096)!
        try m4aFile.read(into: decoded)
        XCTAssertGreaterThan(decoded.frameLength, 0)

        // Encode the exact same ordered PCM sources in all three formats so
        // duration comparisons cannot accidentally compare different fixtures.
        let mp3 = directory.appendingPathComponent("complete.mp3")
        let mp3Verification = try await AudiobookMP3Exporter.export(
            sources: orderedSources,
            metadata: AudiobookMP3Metadata(title: "Sample Book", author: "Test Author", album: "Synthetic"),
            settings: .productionDefaults,
            to: mp3
        )
        XCTAssertEqual(mp3Verification.duration, expectedDuration, accuracy: 0.4)
        XCTAssertEqual(mp3Verification.duration, Double(wavFile.length) / wavFile.fileFormat.sampleRate, accuracy: 0.4)
        XCTAssertEqual(mp3Verification.duration, CMTimeGetSeconds(duration), accuracy: 0.4)
        XCTAssertGreaterThan(mp3Verification.decodedFrames, 0)
    }

    @MainActor
    func testYouTubeExportProducesDecodableLandscapeAndPortraitMP4() async throws {
        guard let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("en-") }) else {
            throw XCTSkip("No installed English macOS speech voice is available on this test host.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BOLD-Audiobook-MP4-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await LocalSpeechRenderer.render("A short chapter for video publishing.", voice: voice, rate: 0.48, directory: directory, basename: "chapter")
        for portrait in [false, true] {
            let destination = directory.appendingPathComponent(portrait ? "chapter-vertical.mp4" : "book-landscape.mp4")
            let metadata = AudiobookVideoMetadata(title: "Video Test", author: "Writer", chapterTitle: portrait ? "Chapter One" : nil, portrait: portrait)
            try await AudiobookVideoExporter.export(sources: source, metadata: metadata, to: destination)
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertGreaterThan((try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.intValue ?? 0, 10_000)
            let asset = AVURLAsset(url: destination)
            let playable = try await asset.load(.isPlayable)
            XCTAssertTrue(playable)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let video = try XCTUnwrap(videoTracks.first)
            let audio = try XCTUnwrap(audioTracks.first)
            XCTAssertEqual(CMFormatDescriptionGetMediaSubType(video.formatDescriptions.first as! CMFormatDescription), kCMVideoCodecType_H264)
            XCTAssertEqual(CMFormatDescriptionGetMediaSubType(audio.formatDescriptions.first as! CMFormatDescription), kAudioFormatMPEG4AAC)
            let duration = CMTimeGetSeconds(try await asset.load(.duration))
            XCTAssertGreaterThan(duration, 0.5)
        }
    }

    @MainActor
    func testMP3ChapterAndCompleteBookExportAreRealUnicodeTaggedAndDecodable() async throws {
        guard let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("en-") }) else {
            throw XCTSkip("No installed English macOS speech voice is available on this test host.")
        }
        let base = ProcessInfo.processInfo.environment["BOLD_AUDIOBOOK_EVIDENCE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("MP3", isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("BOLD-Audiobook-MP3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { if ProcessInfo.processInfo.environment["BOLD_AUDIOBOOK_EVIDENCE_DIR"] == nil { try? FileManager.default.removeItem(at: base) } }

        let chapterOne = try await LocalSpeechRenderer.render("This is the first synthetic chapter.", voice: voice, rate: 0.48, directory: base, basename: "chapter-1")
        let chapterTwo = try await LocalSpeechRenderer.render("This is the next synthetic chapter.", voice: voice, rate: 0.48, directory: base, basename: "chapter-2")
        let metadata = AudiobookMP3Metadata(title: "λόγος — Sample Book", author: "Élodie Author", album: "Synthetic Series", track: 2)
        let settings = AudiobookMP3Settings(quality: .speech, encoderQuality: 2)

        let chapterURL = base.appendingPathComponent("chapter-1.mp3")
        let chapter = try await AudiobookMP3Exporter.export(sources: [chapterOne[0]], metadata: metadata, settings: settings, to: chapterURL)
        XCTAssertEqual(chapter.fileURL, chapterURL)
        XCTAssertEqual(chapter.bitrateKbps, 128)
        XCTAssertTrue(chapter.hasID3v2Header)
        XCTAssertEqual(chapter.sampleRate, 44_100, accuracy: 1)
        XCTAssertEqual(chapter.channels, 2)
        XCTAssertEqual(chapter.title, metadata.title)
        XCTAssertEqual(chapter.author, metadata.author)
        XCTAssertGreaterThan(chapter.duration, 0.1)
        XCTAssertGreaterThan(chapter.decodedFrames, 0)
        XCTAssertGreaterThan(chapter.bytes, 1_000)

        let bookURL = base.appendingPathComponent("complete.mp3")
        let complete = try await AudiobookMP3Exporter.export(sources: [chapterOne[0], chapterTwo[0]], metadata: metadata, settings: settings, to: bookURL)
        XCTAssertEqual(complete.bitrateKbps, 128)
        XCTAssertEqual(complete.title, metadata.title)
        XCTAssertEqual(complete.author, metadata.author)
        XCTAssertEqual(complete.duration, chapter.duration + (try AVAudioFile(forReading: chapterTwo[0])).lengthAsDuration, accuracy: 0.4)
        XCTAssertGreaterThan(complete.decodedFrames, chapter.decodedFrames)

        let prefix = try Data(contentsOf: bookURL).prefix(3)
        XCTAssertEqual(Array(prefix), [0x49, 0x44, 0x33])
        let decoded = try AVAudioFile(forReading: bookURL)
        XCTAssertGreaterThan(decoded.length, 0)
    }

    func testStreamingLoudnessPeakSilenceAndBalancedGainPlan() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BOLD-Audiobook-Meter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("tone-and-silence.wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2, interleaved: true)!
        var file: AVAudioFile? = try AVAudioFile(forWriting: source, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let toneFrames = 144_000
        let silenceFrames = 288_000
        let blockSize = 8_192
        var cursor = 0
        while cursor < toneFrames + silenceFrames {
            let count = min(blockSize, toneFrames + silenceFrames - cursor)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
            buffer.frameLength = AVAudioFrameCount(count)
            let samples = buffer.int16ChannelData!.pointee
            for frame in 0..<count {
                let globalFrame = cursor + frame
                let value: Int16
                if globalFrame < toneFrames {
                    value = Int16((sin(2 * Double.pi * 997 * Double(globalFrame) / 48_000) * 3_276.7).rounded())
                } else { value = 0 }
                samples[frame * 2] = value
                samples[frame * 2 + 1] = 0
            }
            try file?.write(from: buffer)
            cursor += count
        }
        file = nil

        let report = try await AudiobookAudioQualityAnalyzer.inspect(sources: [source], sourceIDs: ["chapter-one"])
        XCTAssertEqual(report.integratedLoudnessLUFS ?? 0, -23.0, accuracy: 0.6)
        XCTAssertEqual(report.samplePeakDBFS, -20.0, accuracy: 0.1)
        XCTAssertEqual(report.clippedSampleCount, 0)
        XCTAssertEqual(report.longestQuietRunSeconds, 6.0, accuracy: 0.05)
        XCTAssertEqual(report.totalDurationSeconds, 9.0, accuracy: 0.05)
        XCTAssertEqual(report.analysisSampleRate, 48_000)
        XCTAssertEqual(report.channelCount, 2)

        let plan = try await AudiobookAudioQualityAnalyzer.plan(sources: [source], settings: .balancedSpokenWord)
        XCTAssertEqual(plan.appliedGainDB, 5.0, accuracy: 0.6)
        XCTAssertLessThan(plan.predictedSamplePeakDBFS, plan.settings.samplePeakCeilingDBFS)
    }
}

private extension AVAudioFile { var lengthAsDuration: Double { Double(length) / processingFormat.sampleRate } }
