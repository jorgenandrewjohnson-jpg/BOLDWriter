import AVFoundation
import XCTest
@testable import BOLDWriter

final class AudiobookProductionServiceTests: XCTestCase {
    private var testDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in testDirectories { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    @MainActor
    func testAppleVoiceChunkIsClosedBeforeProductionCheckpointVerification() async throws {
        guard let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("en-") }) else {
            throw XCTSkip("No installed English macOS speech voice is available on this test host.")
        }
        let directory = try temporaryDirectory()
        let projectID = UUID()
        let provider = AppleSystemNarrationProvider()
        let service = try AudiobookProductionService(projectID: projectID, projectDirectory: directory, providers: [provider])
        let item = AudiobookSourceItem(id: "paragraph-1", chapterID: "chapter-1", chapterTitle: "One", sourceTextFingerprint: "source-v1", narrationText: "A short local system voice checkpoint test.")
        let narrator = AudiobookNarratorProfile(id: "mac-voice", providerID: "apple.system", voiceIdentifier: voice.identifier, speed: 0.48)
        let request = AudiobookRenderRequest(
            projectID: projectID,
            sourceFingerprint: "source-v1",
            scope: AudiobookRenderScope(kind: .selectedChapters, selectedChapterIDs: ["chapter-1"]),
            items: [item],
            assignmentPlan: AudiobookNarratorAssignmentPlan(defaultNarratorID: narrator.id, narrators: [narrator.id: narrator])
        )

        let jobID = try await service.render(request)
        let finished = try await waitForTerminalSnapshot(service, jobID: jobID)
        XCTAssertEqual(finished.state, .complete, finished.lastError ?? "")
        let records = try await service.verifiedAudio(chapterIDs: ["chapter-1"])
        XCTAssertEqual(records.count, 1)
        let mediaURL = directory.appendingPathComponent(records[0].relativePath)
        let audio = try AVAudioFile(forReading: mediaURL)
        XCTAssertGreaterThan(audio.length, 0)
    }

    func testVerifiedUnchangedChunkReuseMissingMediaRecoveryAndNarratorInvalidation() async throws {
        let directory = try temporaryDirectory()
        let projectID = UUID()
        let provider = DeterministicAudioProvider(providerID: "test.local")
        let service = try AudiobookProductionService(projectID: projectID, projectDirectory: directory, providers: [provider])
        let item = AudiobookSourceItem(id: "paragraph-1", chapterID: "chapter-1", chapterTitle: "One", sourceTextFingerprint: "source-v1", narrationText: "Synthetic words for the first paragraph.")
        var request = renderRequest(projectID: projectID, items: [item], providerID: "test.local", voiceID: "voice-one")

        let firstJob = try await service.render(request)
        let first = try await waitForTerminalSnapshot(service, jobID: firstJob)
        XCTAssertEqual(first.state, .complete)
        XCTAssertEqual(first.completedChunks, 1)
        var audio = try await service.verifiedAudio(chapterIDs: ["chapter-1"])
        XCTAssertEqual(audio.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(audio[0].relativePath).path))
        var callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)

        let reopened = try AudiobookProductionService(projectID: projectID, projectDirectory: directory, providers: [provider])
        let beforeResume = try await reopened.verifiedAudio(chapterIDs: ["chapter-1"])
        XCTAssertEqual(beforeResume.first?.checksum, audio.first?.checksum)
        let missingURL = directory.appendingPathComponent(beforeResume[0].relativePath)
        try FileManager.default.removeItem(at: missingURL)
        let recoveryJob = try await reopened.resume(request)
        let recovered = try await waitForTerminalSnapshot(reopened, jobID: recoveryJob)
        XCTAssertEqual(recovered.state, .complete)
        callCount = await provider.callCount()
        XCTAssertEqual(callCount, 2, "Only the missing chunk should be regenerated.")
        audio = try await reopened.verifiedAudio(chapterIDs: ["chapter-1"])
        XCTAssertEqual(audio.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(audio[0].relativePath).path))

        request.items[0].sourceTextFingerprint = "source-v2"
        request.items[0].narrationText = "Synthetic words for the changed paragraph."
        let changedJob = try await reopened.resume(request)
        let changed = try await waitForTerminalSnapshot(reopened, jobID: changedJob)
        XCTAssertEqual(changed.state, .complete)
        callCount = await provider.callCount()
        XCTAssertEqual(callCount, 3)
        let current = try await reopened.verifiedAudio(chapterIDs: ["chapter-1"])
        XCTAssertEqual(current.count, 1)
        XCTAssertEqual(current[0].sourceTextFingerprint, "source-v2")

        request = renderRequest(projectID: projectID, items: request.items, providerID: "test.local", voiceID: "voice-two")
        let narratorJob = try await reopened.resume(request)
        let narratorSnapshot = try await waitForTerminalSnapshot(reopened, jobID: narratorJob)
        XCTAssertEqual(narratorSnapshot.state, .complete)
        callCount = await provider.callCount()
        XCTAssertEqual(callCount, 4, "Changing narrator settings must regenerate audio.")
        let newNarrator = try await reopened.verifiedAudio(chapterIDs: ["chapter-1"])
        XCTAssertEqual(newNarrator.first?.voiceIdentifier, "voice-two")
    }

    func testCompletedChunksSurviveLaterFailureAndResumeWithoutRepeat() async throws {
        let directory = try temporaryDirectory()
        let projectID = UUID()
        let provider = DeterministicAudioProvider(providerID: "test.local", permanentFailureText: "FAIL THIS ONCE", failureCount: 1)
        let service = try AudiobookProductionService(projectID: projectID, projectDirectory: directory, providers: [provider])
        let items = [
            AudiobookSourceItem(id: "paragraph-1", chapterID: "chapter-1", chapterTitle: "One", sourceTextFingerprint: "src-1", narrationText: "This first chunk succeeds."),
            AudiobookSourceItem(id: "paragraph-2", chapterID: "chapter-1", chapterTitle: "One", sourceTextFingerprint: "src-2", narrationText: "FAIL THIS ONCE")
        ]
        let request = renderRequest(projectID: projectID, items: items, providerID: "test.local", voiceID: "voice-one", retries: 0)
        let failedJob = try await service.render(request)
        let failed = try await waitForTerminalSnapshot(service, jobID: failedJob)
        XCTAssertEqual(failed.state, .partial)
        XCTAssertEqual(failed.completedChunks, 1)
        let failedManifest = try JSONDecoder().decode(AudiobookProductionManifest.self, from: Data(contentsOf: directory.appendingPathComponent("production-manifest.json")))
        let completedAfterFailure = failedManifest.chunks.filter { $0.state == .complete && $0.chapterID == "chapter-1" }
        XCTAssertEqual(completedAfterFailure.count, 1)
        XCTAssertEqual(completedAfterFailure.first?.itemID, "paragraph-1")
        var callCount = await provider.callCount()
        XCTAssertEqual(callCount, 2)
        do {
            _ = try await service.verifiedAudio(chapterIDs: ["chapter-1"])
            XCTFail("A partial chapter must not be exposed to export as a complete verified chapter.")
        } catch is AudiobookProductionError { }

        let retryJob = try await service.resume(request)
        let recovered = try await waitForTerminalSnapshot(service, jobID: retryJob)
        XCTAssertEqual(recovered.state, .complete)
        XCTAssertEqual(recovered.completedChunks, 2)
        callCount = await provider.callCount()
        XCTAssertEqual(callCount, 3, "The successful first chunk must not be submitted twice.")
        let audio = try await service.verifiedAudio(chapterIDs: ["chapter-1"])
        XCTAssertEqual(audio.count, 2)
    }

    func testCancelMarksActiveJobCancelledAndKeepsWorkResumable() async throws {
        let directory = try temporaryDirectory()
        let projectID = UUID()
        let provider = DeterministicAudioProvider(providerID: "test.local", synthesisDelay: .seconds(30))
        let service = try AudiobookProductionService(projectID: projectID, projectDirectory: directory, providers: [provider])
        let item = AudiobookSourceItem(id: "paragraph-1", chapterID: "chapter-1", chapterTitle: "One", sourceTextFingerprint: "source-v1", narrationText: "This local chunk is cancelled while synthesis is in progress.")
        let request = renderRequest(projectID: projectID, items: [item], providerID: "test.local", voiceID: "voice-one")

        let jobID = try await service.render(request)
        var observedSubmission = false
        for _ in 0..<1_000 {
            if await provider.callCount() == 1 {
                observedSubmission = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(observedSubmission, "The test provider should be inside synthesis before cancellation.")

        await service.cancel(jobID)
        let cancelled = try await waitForTerminalSnapshot(service, jobID: jobID)
        XCTAssertEqual(cancelled.state, .cancelled)
        XCTAssertEqual(cancelled.completedChunks, 0)

        let manifestData = try Data(contentsOf: directory.appendingPathComponent("production-manifest.json"))
        let manifest = try JSONDecoder().decode(AudiobookProductionManifest.self, from: manifestData)
        XCTAssertEqual(manifest.state, .cancelled)
        XCTAssertEqual(manifest.chunks.first?.state, .queued)
        do {
            _ = try await service.verifiedAudio(chapterIDs: ["chapter-1"])
            XCTFail("Cancelled chapter audio must not be offered as a completed export.")
        } catch is AudiobookProductionError { }

        let resumedJobID = try await service.resume(request)
        let resumed = try await waitForTerminalSnapshot(service, jobID: resumedJobID)
        XCTAssertEqual(resumed.state, .complete)
        let resumedAudio = try await service.verifiedAudio(chapterIDs: ["chapter-1"])
        XCTAssertEqual(resumedAudio.count, 1)
        let synthesisCalls = await provider.callCount()
        XCTAssertEqual(synthesisCalls, 2)
    }

    func testAtomicallyRenamedMediaIsRecoveredWhenManifestCheckpointWasInterrupted() async throws {
        let directory = try temporaryDirectory()
        let projectID = UUID()
        let provider = DeterministicAudioProvider(providerID: "test.local")
        let service = try AudiobookProductionService(projectID: projectID, projectDirectory: directory, providers: [provider])
        let item = AudiobookSourceItem(id: "paragraph-1", chapterID: "chapter-1", chapterTitle: "One", sourceTextFingerprint: "source-v1", narrationText: "A completed local chunk.")
        let request = renderRequest(projectID: projectID, items: [item], providerID: "test.local", voiceID: "voice-one")
        let firstJob = try await service.render(request)
        let first = try await waitForTerminalSnapshot(service, jobID: firstJob)
        XCTAssertEqual(first.state, .complete)

        let manifestURL = directory.appendingPathComponent("production-manifest.json")
        var manifest = try JSONDecoder().decode(AudiobookProductionManifest.self, from: Data(contentsOf: manifestURL))
        manifest.state = .rendering
        manifest.chunks[0].state = .rendering
        manifest.chunks[0].checksum = nil
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        let partial = directory.appendingPathComponent(manifest.chunks[0].relativePath).deletingLastPathComponent().appendingPathComponent("orphan.partial.caf")
        try Data([0, 1, 2]).write(to: partial)

        let reopened = try AudiobookProductionService(projectID: projectID, projectDirectory: directory, providers: [provider])
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path), "Orphaned chunk temporaries are cleaned on project recovery.")
        let recoveryJob = try await reopened.resume(request)
        let recovered = try await waitForTerminalSnapshot(reopened, jobID: recoveryJob)
        XCTAssertEqual(recovered.state, .complete)
        let calls = await provider.callCount()
        XCTAssertEqual(calls, 1, "The verified final audio path is adopted without synthesizing the same text again.")
        let audio = try await reopened.verifiedAudio(chapterIDs: ["chapter-1"])
        XCTAssertEqual(audio.count, 1)
    }

    func testMockRateLimitRetryIsBoundedAndPersistedAgainstBillableBudget() async throws {
        let directory = try temporaryDirectory()
        let projectID = UUID()
        let provider = DeterministicAudioProvider(providerID: "elevenlabs", retryFailureCount: 1)
        let service = try AudiobookProductionService(projectID: projectID, projectDirectory: directory, providers: [provider])
        let item = AudiobookSourceItem(id: "chapter-1", chapterID: "chapter-1", chapterTitle: "One", sourceTextFingerprint: "source", narrationText: "A retryable synthetic narration request.")
        var request = renderRequest(projectID: projectID, items: [item], providerID: "elevenlabs", voiceID: "account-voice", modelID: "account-model", retries: 1)
        request.billableApprovals[0].characterBudget = item.narrationText.utf16.count * 2
        let job = try await service.render(request)
        let snapshot = try await waitForTerminalSnapshot(service, jobID: job)
        XCTAssertEqual(snapshot.state, .complete)
        let calls = await provider.callCount()
        XCTAssertEqual(calls, 2)
        let manifest = try JSONDecoder().decode(AudiobookProductionManifest.self, from: Data(contentsOf: directory.appendingPathComponent("production-manifest.json")))
        XCTAssertEqual(manifest.chunks[0].billableCharactersAttempted, item.narrationText.utf16.count * 2)
        XCTAssertEqual(manifest.chunks[0].billedCharacters, item.narrationText.utf16.count)
    }

    func testBillableApprovalIsExactBudgetBoundedAndPrecedesProviderCall() async throws {
        let directory = try temporaryDirectory()
        let projectID = UUID()
        let provider = DeterministicAudioProvider(providerID: "elevenlabs")
        let service = try AudiobookProductionService(projectID: projectID, projectDirectory: directory, providers: [provider])
        let item = AudiobookSourceItem(id: "chapter-1", chapterID: "chapter-1", chapterTitle: "One", sourceTextFingerprint: "source", narrationText: "Billable synthetic passage.")
        var request = renderRequest(projectID: projectID, items: [item], providerID: "elevenlabs", voiceID: "account-voice", modelID: "account-model")
        request.billableApprovals = []
        let initialPreflight = try await service.billablePreflight(for: request)
        let review = try XCTUnwrap(initialPreflight.first)
        XCTAssertEqual(review.exactCharacterCount, item.narrationText.utf16.count)
        XCTAssertEqual(review.reviewedTextFingerprint, reviewedFingerprint([item]))

        do {
            _ = try await service.render(request)
            XCTFail("The provider must not be called without explicit approval.")
        } catch let AudiobookProductionError.billableApprovalRequired(_, _, _, count) {
            XCTAssertEqual(count, item.narrationText.utf16.count)
        }
        var callCount = await provider.callCount()
        XCTAssertEqual(callCount, 0)

        var overBudget = request
        overBudget.billableApprovals = [AudiobookBillableApproval(providerID: review.providerID, voiceIdentifier: review.voiceIdentifier, modelIdentifier: review.modelIdentifier, reviewedCharacterCount: review.exactCharacterCount, reviewedTextFingerprint: review.reviewedTextFingerprint, characterBudget: item.narrationText.utf16.count - 1)]
        do {
            _ = try await service.render(overBudget)
            XCTFail("The generation budget must reject over-budget work.")
        } catch let AudiobookProductionError.characterBudgetExceeded(_, requested, available) {
            XCTAssertEqual(requested, item.narrationText.utf16.count)
            XCTAssertEqual(available, item.narrationText.utf16.count - 1)
        }
        callCount = await provider.callCount()
        XCTAssertEqual(callCount, 0)

        var approved = request
        approved.billableApprovals = [AudiobookBillableApproval(providerID: review.providerID, voiceIdentifier: review.voiceIdentifier, modelIdentifier: review.modelIdentifier, reviewedCharacterCount: review.exactCharacterCount, reviewedTextFingerprint: review.reviewedTextFingerprint, characterBudget: 1_000)]
        let job = try await service.render(approved)
        let snapshot = try await waitForTerminalSnapshot(service, jobID: job)
        XCTAssertEqual(snapshot.state, .complete)
        callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1)
        let audio = try await service.verifiedAudio(chapterIDs: ["chapter-1"])
        XCTAssertEqual(audio.first?.providerID, "elevenlabs")

        var additional = approved
        additional.items[0].narrationText = "A second paid sample that exceeds the remaining author budget."
        let additionalCount = additional.items[0].narrationText.utf16.count
        let updatedPreflight = try await service.billablePreflight(for: additional)
        let updatedReview = try XCTUnwrap(updatedPreflight.first)
        additional.billableApprovals[0].reviewedCharacterCount = updatedReview.exactCharacterCount
        additional.billableApprovals[0].reviewedTextFingerprint = updatedReview.reviewedTextFingerprint
        additional.billableApprovals[0].characterBudget = item.narrationText.utf16.count + additionalCount - 1
        do {
            _ = try await service.resume(additional)
            XCTFail("A later render must count successfully billed characters from the persistent manifest.")
        } catch let AudiobookProductionError.characterBudgetExceeded(_, requested, available) {
            XCTAssertEqual(requested, additionalCount)
            XCTAssertEqual(available, additionalCount - 1)
        }
        callCount = await provider.callCount()
        XCTAssertEqual(callCount, 1, "The persisted budget must block the provider call.")
    }

    func testExplicitNarratorAssignmentsUseSegmentThenChapterThenDefault() throws {
        let profiles = [
            "default": profile("default", voiceID: "voice-default"),
            "chapter": profile("chapter", voiceID: "voice-chapter"),
            "segment": profile("segment", voiceID: "voice-segment")
        ]
        let plan = AudiobookNarratorAssignmentPlan(defaultNarratorID: "default", chapterNarrators: ["chapter-1": "chapter"], segmentNarrators: ["paragraph-1": "segment"], narrators: profiles)
        let chapter = AudiobookSourceItem(id: "paragraph-2", chapterID: "chapter-1", chapterTitle: "One", sourceTextFingerprint: "a", narrationText: "A")
        let segment = AudiobookSourceItem(id: "paragraph-1", chapterID: "chapter-1", chapterTitle: "One", sourceTextFingerprint: "b", narrationText: "B")
        let otherChapter = AudiobookSourceItem(id: "paragraph-3", chapterID: "chapter-2", chapterTitle: "Two", sourceTextFingerprint: "c", narrationText: "C")
        XCTAssertEqual(try plan.profile(for: chapter).id, "chapter")
        XCTAssertEqual(try plan.profile(for: segment).id, "segment")
        XCTAssertEqual(try plan.profile(for: otherChapter).id, "default")
    }

    func testProductionExportReturnsMeasuredMasteringAndRealWAV() async throws {
        let directory = try temporaryDirectory()
        let projectID = UUID()
        let provider = DeterministicAudioProvider(providerID: "test.local")
        let service = try AudiobookProductionService(projectID: projectID, projectDirectory: directory, providers: [provider])
        let items = [
            AudiobookSourceItem(id: "paragraph-1", chapterID: "chapter-1", chapterTitle: "One", sourceTextFingerprint: "a", narrationText: "One chapter.")
        ]
        let job = try await service.render(renderRequest(projectID: projectID, items: items, providerID: "test.local", voiceID: "voice-one"))
        let snapshot = try await waitForTerminalSnapshot(service, jobID: job)
        XCTAssertEqual(snapshot.state, .complete)
        let destination = directory.appendingPathComponent("completed.wav")
        let result = try await service.export(AudiobookExportRequest(chapterIDs: ["chapter-1"], format: .wav, destination: destination, title: "Synthetic", author: "Test", mastering: .balancedSpokenWord))
        XCTAssertEqual(result.format, .wav)
        XCTAssertEqual(result.metadataTitle, "Synthetic")
        XCTAssertGreaterThan(result.durationSeconds, 0)
        XCTAssertEqual(result.sampleRate, 44_100)
        XCTAssertEqual(result.channels, 2)
        XCTAssertEqual(result.quality.analysisSampleRate, 48_000)
        XCTAssertEqual(result.mastering.settings.preset, .balancedSpokenWord)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        let m4aDestination = directory.appendingPathComponent("completed-unicode-κείμενο.m4a")
        let m4a = try await service.export(AudiobookExportRequest(chapterIDs: ["chapter-1"], format: .m4a, destination: m4aDestination, title: "Synthetic βιβλίο", author: "Test Author"))
        XCTAssertEqual(m4a.format, .m4a)
        XCTAssertEqual(m4a.metadataTitle, "Synthetic βιβλίο")
        XCTAssertEqual(m4a.metadataAuthor, "Test Author")
        XCTAssertEqual(m4a.channels, 2)
        XCTAssertGreaterThan(m4a.durationSeconds, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: m4aDestination.path))
    }

    func testExplicitMultiNarratorPlanRendersDifferentChaptersAndPronunciationChangesInvalidateAudio() async throws {
        let directory = try temporaryDirectory()
        let projectID = UUID()
        let provider = DeterministicAudioProvider(providerID: "test.local")
        let service = try AudiobookProductionService(projectID: projectID, projectDirectory: directory, providers: [provider])
        let defaultVoice = profile("default", voiceID: "voice-default")
        let secondVoice = profile("second", voiceID: "voice-second")
        let first = AudiobookSourceItem(id: "p-1", chapterID: "c-1", chapterTitle: "One", sourceTextFingerprint: "src-1", narrationText: "A passage.")
        let second = AudiobookSourceItem(id: "p-2", chapterID: "c-2", chapterTitle: "Two", sourceTextFingerprint: "src-2", narrationText: "Another passage.")
        var request = AudiobookRenderRequest(
            projectID: projectID,
            sourceFingerprint: "book-source",
            scope: AudiobookRenderScope(kind: .wholeBook),
            items: [first, second],
            assignmentPlan: AudiobookNarratorAssignmentPlan(defaultNarratorID: defaultVoice.id, chapterNarrators: ["c-2": secondVoice.id], narrators: [defaultVoice.id: defaultVoice, secondVoice.id: secondVoice])
        )
        let job = try await service.render(request)
        let rendered = try await waitForTerminalSnapshot(service, jobID: job)
        XCTAssertEqual(rendered.state, .complete)
        let audio = try await service.verifiedAudio()
        XCTAssertEqual(audio.map(\.voiceIdentifier), ["voice-default", "voice-second"])

        var revisedVoice = defaultVoice
        revisedVoice.pronunciationFingerprint = "dictionary-revision-2"
        request.assignmentPlan.narrators[defaultVoice.id] = revisedVoice
        let revisedJob = try await service.resume(request)
        let revised = try await waitForTerminalSnapshot(service, jobID: revisedJob)
        XCTAssertEqual(revised.state, .complete)
        let calls = await provider.callCount()
        XCTAssertEqual(calls, 3, "A changed pronunciation fingerprint regenerates only the affected narrator's segment.")
    }

    func testOneHundredThousandWordBookUsesBoundedRequestChunksAndCompletes() async throws {
        let directory = try temporaryDirectory()
        let projectID = UUID()
        let provider = DeterministicAudioProvider(providerID: "test.local")
        let service = try AudiobookProductionService(projectID: projectID, projectDirectory: directory, providers: [provider])
        let narration = Array(repeating: "narration", count: 100_000).joined(separator: " ")
        XCTAssertEqual(narration.split(separator: " ").count, 100_000)
        let item = AudiobookSourceItem(id: "long-body", chapterID: "long-chapter", chapterTitle: "Long", sourceTextFingerprint: "long-book-v1", narrationText: narration)
        let request = renderRequest(projectID: projectID, items: [item], providerID: "test.local", voiceID: "voice-long")
        let job = try await service.render(request)
        let snapshot = try await waitForTerminalSnapshot(service, jobID: job)
        XCTAssertEqual(snapshot.state, .complete)
        XCTAssertGreaterThan(snapshot.totalChunks, 100)
        XCTAssertEqual(snapshot.completedChunks, snapshot.totalChunks)
        let maxRequest = await provider.maximumSubmittedCharacters()
        XCTAssertLessThanOrEqual(maxRequest, 3_500)
        let records = try await service.verifiedAudio(chapterIDs: ["long-chapter"])
        XCTAssertEqual(records.count, snapshot.totalChunks)
        XCTAssertTrue(records.allSatisfy { $0.checksum != nil && ($0.durationSeconds ?? 0) > 0 })
    }

    func testInstalledMacVoiceIsDiscoveredAndProducesDecodableLocalAudio() async throws {
        let voices = await MainActor.run { AVSpeechSynthesisVoice.speechVoices() }
        XCTAssertFalse(voices.isEmpty, "This Mac must expose at least one installed system speech voice.")
        let qualityCounts = Dictionary(grouping: voices, by: \.quality).map { "\(qualityName($0.key)):\($0.value.count)" }.sorted().joined(separator: ",")
        print("NATIVE_VOICE_SUMMARY count=\(voices.count) languages=\(Set(voices.map(\.language)).count) quality_counts=\(qualityCounts)")
        let provider = AppleSystemNarrationProvider()
        let directory = try temporaryDirectory()
        for (index, voice) in voices.prefix(2).enumerated() {
            print("NATIVE_VOICE_ACCEPTANCE id=\(voice.identifier) name=\(voice.name) language=\(voice.language) quality=\(qualityName(voice.quality))")
            let profile = AudiobookNarratorProfile(id: "installed-voice-\(index)", providerID: "apple.system", voiceIdentifier: voice.identifier, speed: 0.48, maximumRequestCharacters: 3_500)
            try await provider.validate(profile: profile, maximumCharacters: 49)
            let destination = directory.appendingPathComponent("local-voice-sample-\(index).caf")
            try await provider.synthesize(text: "A short synthetic audiobook voice test.", profile: profile, to: destination)
            let audio = try AVAudioFile(forReading: destination)
            XCTAssertGreaterThan(audio.length, 0)
            XCTAssertGreaterThan(Double(audio.length) / audio.processingFormat.sampleRate, 0)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BOLD-Audiobook-Production-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        testDirectories.append(url)
        return url
    }

    private func renderRequest(projectID: UUID, items: [AudiobookSourceItem], providerID: String, voiceID: String, modelID: String = "", retries: Int = 3) -> AudiobookRenderRequest {
        let narrator = profile("narrator-\(voiceID)", providerID: providerID, voiceID: voiceID, modelID: modelID)
        var approvals: [AudiobookBillableApproval] = []
        if providerID == "elevenlabs" {
            let count = items.reduce(0) { $0 + $1.narrationText.utf16.count }
            approvals = [AudiobookBillableApproval(providerID: providerID, voiceIdentifier: voiceID, modelIdentifier: modelID, reviewedCharacterCount: count, reviewedTextFingerprint: reviewedFingerprint(items), characterBudget: 1_000_000)]
        }
        let chapters = Array(NSOrderedSet(array: items.map(\.chapterID))) as? [String] ?? []
        return AudiobookRenderRequest(projectID: projectID, sourceFingerprint: AudiobookChapter.digest(items.map(\.sourceTextFingerprint).joined()), scope: AudiobookRenderScope(kind: .selectedChapters, selectedChapterIDs: chapters), items: items, assignmentPlan: AudiobookNarratorAssignmentPlan(defaultNarratorID: narrator.id, narrators: [narrator.id: narrator]), billableApprovals: approvals, maximumRetries: retries)
    }

    private func profile(_ id: String, providerID: String = "test.local", voiceID: String? = nil, modelID: String = "") -> AudiobookNarratorProfile {
        AudiobookNarratorProfile(id: id, providerID: providerID, voiceIdentifier: voiceID ?? id, modelIdentifier: modelID, speed: 0.48, maximumRequestCharacters: 3_500)
    }

    private func reviewedFingerprint(_ items: [AudiobookSourceItem]) -> String {
        let chunks = items.flatMap { AudiobookProjectManifest.chunks($0.narrationText, maximumCharacters: 3_500) }
        return AudiobookChapter.digest(chunks.joined(separator: "\u{0000}"))
    }

    private func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .default: "default"
        case .enhanced: "enhanced"
        case .premium: "premium"
        @unknown default: "unknown"
        }
    }

    private func waitForTerminalSnapshot(_ service: AudiobookProductionService, jobID: UUID, file: StaticString = #filePath, line: UInt = #line) async throws -> AudiobookJobSnapshot {
        for _ in 0..<3_000 {
            if let snapshot = await service.snapshot(for: jobID), [.complete, .partial, .failed, .cancelled].contains(snapshot.state) { return snapshot }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Production job did not finish in ten seconds.", file: file, line: line)
        throw CancellationError()
    }
}

private actor DeterministicAudioProvider: AudiobookNarrationProvider {
    nonisolated let providerID: String
    private var calls = 0
    private var maxCharacters = 0
    private var failuresRemaining: Int
    private var retryFailuresRemaining: Int
    private let failureText: String?
    private var synthesisDelay: Duration?

    init(providerID: String, permanentFailureText: String? = nil, failureCount: Int = 0, retryFailureCount: Int = 0, synthesisDelay: Duration? = nil) {
        self.providerID = providerID
        self.failureText = permanentFailureText
        self.failuresRemaining = failureCount
        self.retryFailuresRemaining = retryFailureCount
        self.synthesisDelay = synthesisDelay
    }

    func validate(profile: AudiobookNarratorProfile, maximumCharacters: Int) async throws {
        guard profile.providerID == providerID, maximumCharacters <= profile.maximumRequestCharacters else {
            throw AudiobookProviderFailure.permanent(message: "Mock provider rejected invalid voice settings.")
        }
    }

    func synthesize(text: String, profile: AudiobookNarratorProfile, to destination: URL) async throws {
        calls += 1
        maxCharacters = max(maxCharacters, text.utf16.count)
        if let synthesisDelay {
            self.synthesisDelay = nil
            try await Task.sleep(for: synthesisDelay)
        }
        if retryFailuresRemaining > 0 {
            retryFailuresRemaining -= 1
            throw AudiobookProviderFailure.retryable(message: "Synthetic HTTP 429 rate limit response.")
        }
        if text == failureText, failuresRemaining > 0 {
            failuresRemaining -= 1
            throw AudiobookProviderFailure.permanent(message: "Synthetic provider interruption.")
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 22_050, channels: 1, interleaved: true)!
        let source = destination.deletingLastPathComponent().appendingPathComponent("mock-\(UUID().uuidString).caf")
        do {
            let audio = try AVAudioFile(forWriting: source, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096)!
            buffer.frameLength = 4_096
            for index in 0..<4_096 { buffer.int16ChannelData!.pointee[index] = Int16((sin(2 * Double.pi * 440 * Double(index) / 22_050) * 4_000).rounded()) }
            try audio.write(from: buffer)
            // AVAudioFile closes when this local reference leaves the helper scope.
            if providerID == "elevenlabs" {
                try await AudiobookMP3Exporter.export(sources: [source], metadata: AudiobookMP3Metadata(title: "Mock", author: "Synthetic", album: ""), settings: .init(quality: .speech), to: destination)
            } else {
                let decoded = try AVAudioFile(forReading: source)
                let output = try AVAudioFile(forWriting: destination, settings: decoded.processingFormat.settings)
                let copy = AVAudioPCMBuffer(pcmFormat: decoded.processingFormat, frameCapacity: AVAudioFrameCount(decoded.length))!
                try decoded.read(into: copy)
                try output.write(from: copy)
            }
            try? FileManager.default.removeItem(at: source)
        } catch {
            try? FileManager.default.removeItem(at: source)
            throw error
        }
    }

    func callCount() -> Int { calls }
    func maximumSubmittedCharacters() -> Int { maxCharacters }
}
