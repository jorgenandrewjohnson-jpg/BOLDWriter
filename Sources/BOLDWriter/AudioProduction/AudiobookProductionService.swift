import AVFoundation
import CryptoKit
import Darwin
import Foundation

struct AudiobookSourceItem: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var chapterID: String
    var chapterTitle: String
    var sourceTextFingerprint: String
    var narrationText: String
}

struct AudiobookNarratorProfile: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var providerID: String
    var voiceIdentifier: String
    var modelIdentifier: String = ""
    /// Apple AVSpeech rate, e.g. 0.48. Nil means the provider's default rate.
    var speed: Double?
    var pronunciationFingerprint: String = ""
    /// The provider's verified maximum request length. It is a safety ceiling, not a quota.
    var maximumRequestCharacters: Int = 3_500
    /// Only supported provider-specific options belong here. The M1 ElevenLabs adapter sends none.
    var supportedOptions: [String: String] = [:]
}

struct AudiobookNarratorAssignmentPlan: Codable, Equatable, Sendable {
    var defaultNarratorID: String
    var chapterNarrators: [String: String] = [:]
    var segmentNarrators: [String: String] = [:]
    var narrators: [String: AudiobookNarratorProfile]

    func profile(for item: AudiobookSourceItem) throws -> AudiobookNarratorProfile {
        let narratorID = segmentNarrators[item.id] ?? chapterNarrators[item.chapterID] ?? defaultNarratorID
        guard let profile = narrators[narratorID] else { throw AudiobookProductionError.narratorNotConfigured(narratorID) }
        return profile
    }
}

struct AudiobookBillableApproval: Codable, Equatable, Sendable {
    var providerID: String
    var voiceIdentifier: String
    var modelIdentifier: String
    var reviewedCharacterCount: Int
    /// Fingerprint of the exact ordered narration chunks shown for approval.
    var reviewedTextFingerprint: String
    var characterBudget: Int
    var charactersAlreadyUsed: Int = 0
}

struct AudiobookBillablePreflight: Codable, Equatable, Sendable, Identifiable {
    var providerID: String
    var voiceIdentifier: String
    var modelIdentifier: String
    var exactCharacterCount: Int
    var reviewedTextFingerprint: String
    var priorAttemptedCharacters: Int
    var maximumChunkCharacters: Int
    var selectedChapterIDs: [String]
    var id: String { "\(providerID)|\(voiceIdentifier)|\(modelIdentifier)" }
}

struct AudiobookRenderScope: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case selectedChapters, wholeBook }
    var kind: Kind
    var selectedChapterIDs: [String] = []
}

struct AudiobookRenderRequest: Codable, Equatable, Sendable {
    var projectID: UUID
    var sourceFingerprint: String
    var scope: AudiobookRenderScope
    var items: [AudiobookSourceItem]
    var assignmentPlan: AudiobookNarratorAssignmentPlan
    var billableApprovals: [AudiobookBillableApproval] = []
    /// Stable source segment IDs that the author explicitly asks to render again.
    var forceRegenerationIDs: Set<String> = []
    var maximumRetries: Int = 3
}

struct AudiobookChunkCheckpoint: Codable, Equatable, Sendable, Identifiable {
    enum State: String, Codable, Sendable { case queued, rendering, complete, failed, stale }
    var id: String
    var chapterID: String
    var chapterTitle: String
    var itemID: String
    var chunkIndex: Int
    var sourceTextFingerprint: String
    var narrationTextFingerprint: String
    var settingsFingerprint: String
    var providerID: String
    var voiceIdentifier: String
    var modelIdentifier: String
    var relativePath: String
    var itemOrder: Int
    var checksum: String?
    var bytes: Int64?
    var durationSeconds: Double?
    var charactersSubmitted: Int
    /// Characters successfully submitted to a billable provider. Retained when a chunk later becomes stale.
    var billedCharacters: Int = 0
    /// Conservative character reservation made before each external synthesis request.
    var billableCharactersAttempted: Int = 0
    var state: State
    var lastError: String?
    var completedAt: Date?
}

struct AudiobookProductionManifest: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case idle, queued, rendering, partial, complete, cancelled, failed }
    var schemaVersion = 1
    var projectID: UUID
    var sourceFingerprint: String
    var chapterOrder: [String] = []
    var currentJobID: UUID?
    var state: State = .idle
    var chunks: [AudiobookChunkCheckpoint] = []
    var lastError: String?
    var updatedAt = Date()

    init(projectID: UUID, sourceFingerprint: String) {
        self.projectID = projectID
        self.sourceFingerprint = sourceFingerprint
    }
}

struct AudiobookJobSnapshot: Codable, Equatable, Sendable {
    var projectID: UUID
    var jobID: UUID?
    var state: AudiobookProductionManifest.State
    var totalChunks: Int
    var completedChunks: Int
    var currentChapterID: String?
    var currentChunkIndex: Int?
    var charactersSubmitted: Int
    var lastError: String?
    var updatedAt: Date
    var progress: Double { totalChunks > 0 ? Double(completedChunks) / Double(totalChunks) : 0 }
}

struct AudiobookExportRequest: Sendable {
    enum Format: String, Codable, CaseIterable, Sendable { case mp3, wav, m4a }
    var chapterIDs: [String]?
    var format: Format
    var destination: URL
    var title: String
    var author: String
    var album: String = ""
    var mp3Settings = AudiobookMP3Settings.productionDefaults
    var mastering = AudiobookMasteringSettings.original
}

struct AudiobookVerifiedExport: Codable, Equatable, Sendable {
    var fileURL: URL
    var format: AudiobookExportRequest.Format
    var bytes: Int64
    var durationSeconds: Double
    var sampleRate: Double
    var channels: Int
    var bitrateKbps: Int?
    var metadataTitle: String
    var metadataAuthor: String
    var quality: AudiobookAudioQualityReport
    var mastering: AudiobookMasteringPlan
}

enum AudiobookProductionError: LocalizedError {
    case narratorNotConfigured(String)
    case providerUnavailable(String)
    case providerError(String)
    case invalidSource(String)
    case requestTooLarge(provider: String, count: Int, limit: Int)
    case billableApprovalRequired(provider: String, voice: String, model: String, characters: Int)
    case characterBudgetExceeded(provider: String, requested: Int, available: Int)
    case insufficientDiskSpace(required: Int64, available: Int64)
    case noSelectedAudio
    case invalidManifest
    case missingVerifiedAudio(String)
    case exportVerification(String)

    var errorDescription: String? {
        switch self {
        case .narratorNotConfigured(let id): "Narrator assignment '\(id)' is missing from the production plan."
        case .providerUnavailable(let id): "Narration provider '\(id)' is not available in this production service."
        case .providerError(let message): message
        case .invalidSource(let message): message
        case .requestTooLarge(let provider, let count, let limit): "The \(provider) provider request contains \(count) UTF-16 code units; the verified limit is \(limit)."
        case .billableApprovalRequired(let provider, let voice, let model, let count): "Explicit billable approval is required for \(count) characters sent to \(provider) voice \(voice), model \(model)."
        case .characterBudgetExceeded(let provider, let requested, let available): "The \(provider) character budget allows \(available) more characters, but this render needs \(requested)."
        case .insufficientDiskSpace(let required, let available): "Production needs about \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)) of free disk space; \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) is available."
        case .noSelectedAudio: "Select at least one chapter or segment with narration text."
        case .invalidManifest: "The production checkpoint manifest is unreadable or uses an unsupported version."
        case .missingVerifiedAudio(let id): "Verified audio for chunk \(id) is missing or damaged. Regenerate that chunk before export."
        case .exportVerification(let message): "The exported audiobook did not pass verification: \(message)"
        }
    }
}

enum AudiobookProviderFailure: Error, Sendable {
    case retryable(message: String)
    case permanent(message: String)
}

protocol AudiobookNarrationProvider: Sendable {
    var providerID: String { get }
    func validate(profile: AudiobookNarratorProfile, maximumCharacters: Int) async throws
    func synthesize(text: String, profile: AudiobookNarratorProfile, to destination: URL) async throws
}

struct AppleSystemNarrationProvider: AudiobookNarrationProvider {
    let providerID = "apple.system"

    func validate(profile: AudiobookNarratorProfile, maximumCharacters: Int) async throws {
        guard profile.providerID == providerID, profile.maximumRequestCharacters > 0 else { throw AudiobookProviderFailure.permanent(message: "Invalid Apple system voice settings.") }
        let voiceExists = await MainActor.run { AVSpeechSynthesisVoice(identifier: profile.voiceIdentifier) != nil }
        guard voiceExists else { throw AudiobookProviderFailure.permanent(message: "The selected Mac voice is no longer installed: \(profile.voiceIdentifier).") }
    }

    func synthesize(text: String, profile: AudiobookNarratorProfile, to destination: URL) async throws {
        guard text.utf16.count <= profile.maximumRequestCharacters else { throw AudiobookProductionError.requestTooLarge(provider: providerID, count: text.utf16.count, limit: profile.maximumRequestCharacters) }
        try await Self.synthesizeOnMain(text: text, profile: profile, destination: destination)
    }

    @MainActor
    private static func synthesizeOnMain(text: String, profile: AudiobookNarratorProfile, destination: URL) async throws {
        guard let voice = AVSpeechSynthesisVoice(identifier: profile.voiceIdentifier) else { throw AudiobookProviderFailure.permanent(message: "The selected Mac voice is unavailable: \(profile.voiceIdentifier).") }
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Float(min(max(profile.speed ?? 0.48, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let sink = SpeechChunkSink(destination: destination, continuation: continuation)
            synthesizer.write(utterance) { buffer in sink.receive(buffer) }
        }
    }
}

private final class SpeechChunkSink: @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let continuation: CheckedContinuation<Void, Error>
    private var file: AVAudioFile?
    private var finished = false
    private var hasAudio = false

    init(destination: URL, continuation: CheckedContinuation<Void, Error>) {
        self.destination = destination
        self.continuation = continuation
    }

    func receive(_ buffer: AVAudioBuffer) {
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        do {
            if pcm.frameLength == 0 {
                finished = true
                // AVAudioFile finalizes container metadata when its last reference
                // is released. Close it before returning so the production service
                // hashes and verifies the final CAF bytes, not an open file whose
                // header can still change after the checkpoint is written.
                let producedAudio = hasAudio
                file = nil
                if producedAudio { continuation.resume() }
                else { continuation.resume(throwing: AudiobookProviderFailure.permanent(message: "The selected Mac voice produced no audio for this text.")) }
                return
            }
            if file == nil {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                file = try AVAudioFile(forWriting: destination, settings: pcm.format.settings)
            }
            try file?.write(from: pcm)
            hasAudio = true
        } catch {
            finished = true
            file = nil
            continuation.resume(throwing: error)
        }
    }
}

struct ElevenLabsNarrationProvider: AudiobookNarrationProvider {
    let providerID = "elevenlabs"
    private let apiKey: String
    init(apiKey: String) { self.apiKey = apiKey }

    func validate(profile: AudiobookNarratorProfile, maximumCharacters: Int) async throws {
        guard profile.providerID == providerID else { throw AudiobookProviderFailure.permanent(message: "The selected ElevenLabs narrator has a different provider ID.") }
        let api = ElevenLabsProvider(apiKey: apiKey)
        do {
            async let models = api.models()
            async let voices = api.voices()
            let (accountModels, accountVoices) = try await (models, voices)
            guard let model = accountModels.first(where: { $0.model_id == profile.modelIdentifier }) else {
                throw AudiobookProviderFailure.permanent(message: "The selected ElevenLabs model is not available for this account or does not support text to speech.")
            }
            guard accountVoices.contains(where: { $0.voice_id == profile.voiceIdentifier }) else {
                throw AudiobookProviderFailure.permanent(message: "The selected ElevenLabs voice is no longer available for this account.")
            }
            if let limit = model.maximum_text_length_per_request, maximumCharacters > limit {
                throw AudiobookProductionError.requestTooLarge(provider: providerID, count: maximumCharacters, limit: limit)
            }
            guard profile.maximumRequestCharacters <= model.maximum_text_length_per_request ?? profile.maximumRequestCharacters else {
                throw AudiobookProviderFailure.permanent(message: "The configured passage limit exceeds the account model's verified request limit.")
            }
        } catch let error as ElevenLabsAPIError {
            switch error {
            case .http(let status, let body) where status == 429 || status >= 500: throw AudiobookProviderFailure.retryable(message: "ElevenLabs account verification can be retried (HTTP \(status)): \(body)")
            case .http(let status, let body) where status == 401 || status == 403: throw AudiobookProviderFailure.permanent(message: "ElevenLabs authentication failed (HTTP \(status)): \(body)")
            default: throw AudiobookProviderFailure.permanent(message: error.localizedDescription)
            }
        } catch let error as URLError where error.code != .cancelled {
            throw AudiobookProviderFailure.retryable(message: "ElevenLabs account verification had a temporary network failure: \(error.localizedDescription)")
        } catch is CancellationError {
            throw CancellationError()
        }
    }

    func synthesize(text: String, profile: AudiobookNarratorProfile, to destination: URL) async throws {
        guard text.utf16.count <= profile.maximumRequestCharacters else {
            throw AudiobookProductionError.requestTooLarge(provider: providerID, count: text.utf16.count, limit: profile.maximumRequestCharacters)
        }
        do {
            let data = try await ElevenLabsProvider(apiKey: apiKey).synthesize(text: text, voiceID: profile.voiceIdentifier, modelID: profile.modelIdentifier, limit: profile.maximumRequestCharacters)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        } catch let error as ElevenLabsAPIError {
            switch error {
            case .http(let status, let body) where status == 429 || status >= 500: throw AudiobookProviderFailure.retryable(message: "ElevenLabs narration can be retried (HTTP \(status)): \(body)")
            case .http(let status, let body) where status == 401 || status == 403: throw AudiobookProviderFailure.permanent(message: "ElevenLabs authentication failed (HTTP \(status)): \(body)")
            default: throw AudiobookProviderFailure.permanent(message: error.localizedDescription)
            }
        } catch let error as URLError where error.code != .cancelled {
            throw AudiobookProviderFailure.retryable(message: "ElevenLabs narration had a temporary network failure: \(error.localizedDescription)")
        } catch is CancellationError {
            throw CancellationError()
        }
    }
}

actor AudiobookProductionService {
    private struct Work: Sendable {
        var item: AudiobookSourceItem
        var profile: AudiobookNarratorProfile
        var itemOrder: Int
        var chunkIndex: Int
        var chunkText: String
        var checkpoint: AudiobookChunkCheckpoint
        var reusable: Bool
    }
    private struct RunningJob {
        var task: Task<Void, Never>
        var snapshot: AudiobookJobSnapshot
    }

    let projectID: UUID
    let projectDirectory: URL
    private let manifestURL: URL
    private let providers: [String: any AudiobookNarrationProvider]
    private var manifest: AudiobookProductionManifest
    private var jobs: [UUID: RunningJob] = [:]
    private var currentJob: UUID?
    private var updateContinuations: [UUID: [UUID: AsyncStream<AudiobookJobSnapshot>.Continuation]] = [:]

    init(projectID: UUID, projectDirectory: URL, providers: [any AudiobookNarrationProvider]) throws {
        self.projectID = projectID
        self.projectDirectory = projectDirectory
        self.manifestURL = projectDirectory.appendingPathComponent("production-manifest.json")
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.providerID, $0) })
        if let data = try? Data(contentsOf: manifestURL) {
            let decoder = JSONDecoder()
            guard let saved = try? decoder.decode(AudiobookProductionManifest.self, from: data), saved.schemaVersion == 1, saved.projectID == projectID else {
                throw AudiobookProductionError.invalidManifest
            }
            self.manifest = saved
        } else {
            self.manifest = AudiobookProductionManifest(projectID: projectID, sourceFingerprint: "")
        }
        Self.removeAbandonedChunkTemporaries(in: projectDirectory)
    }

    static var supportedExportFormats: [AudiobookExportRequest.Format] { [.mp3, .wav, .m4a] }

    func render(_ request: AudiobookRenderRequest) async throws -> UUID {
        guard request.projectID == projectID else { throw AudiobookProductionError.invalidManifest }
        guard request.maximumRetries >= 0, request.maximumRetries <= 3 else { throw AudiobookProductionError.providerError("Retry count must be between zero and three.") }
        let work = try await prepareWork(request)
        guard !work.isEmpty else { throw AudiobookProductionError.noSelectedAudio }
        try validateBillableApprovals(work: work, approvals: request.billableApprovals)
        try validateDiskSpace(work: work)

        for profile in uniqueProfiles(work.filter { !$0.reusable }) {
            guard let provider = providers[profile.providerID] else { throw AudiobookProductionError.providerUnavailable(profile.providerID) }
            let maxChars = work.filter { $0.profile == profile }.map { $0.chunkText.utf16.count }.max() ?? 0
            var validationAttempt = 0
            while true {
                do {
                    try await provider.validate(profile: profile, maximumCharacters: maxChars)
                    break
                } catch let failure as AudiobookProviderFailure {
                    if case .retryable = failure, validationAttempt < request.maximumRetries {
                        try await Task.sleep(for: .milliseconds(250 * (1 << validationAttempt)))
                        validationAttempt += 1
                        continue
                    }
                    throw failure
                }
            }
        }

        let jobID = UUID()
        currentJob = jobID
        manifest.currentJobID = jobID
        manifest.sourceFingerprint = request.sourceFingerprint
        var chapterOrder: [String] = []
        for item in request.items where !chapterOrder.contains(item.chapterID) { chapterOrder.append(item.chapterID) }
        if request.scope.kind == .wholeBook || manifest.chapterOrder.isEmpty {
            manifest.chapterOrder = chapterOrder
        } else {
            for chapterID in chapterOrder where !manifest.chapterOrder.contains(chapterID) { manifest.chapterOrder.append(chapterID) }
        }
        manifest.state = .queued
        manifest.lastError = nil
        try persistManifest()
        let initial = makeSnapshot(jobID: jobID, total: work.count, completed: 0, current: nil)
        jobs[jobID] = RunningJob(task: Task { await self.execute(work, request: request, jobID: jobID) }, snapshot: initial)
        publish(initial)
        return jobID
    }

    /// `resume` revalidates all paths/checksums/fingerprints and queues only missing or stale audio.
    @discardableResult
    func resume(_ request: AudiobookRenderRequest) async throws -> UUID { try await render(request) }

    /// Computes exact external text/count/settings disclosures without making a provider request.
    func billablePreflight(for request: AudiobookRenderRequest) async throws -> [AudiobookBillablePreflight] {
        guard request.projectID == projectID else { throw AudiobookProductionError.invalidManifest }
        let work = try await prepareWork(request).filter { !$0.reusable && $0.profile.providerID == "elevenlabs" }
        let grouped = Dictionary(grouping: work) { "\($0.profile.providerID)|\($0.profile.voiceIdentifier)|\($0.profile.modelIdentifier)" }
        return grouped.keys.sorted().compactMap { key in
            guard let items = grouped[key], let first = items.first else { return nil }
            let prior = manifest.chunks.filter {
                $0.providerID == first.profile.providerID &&
                $0.voiceIdentifier == first.profile.voiceIdentifier &&
                $0.modelIdentifier == first.profile.modelIdentifier
            }.reduce(0) { $0 + $1.billableCharactersAttempted }
            let textFingerprint = AudiobookChapter.digest(items.map(\.chunkText).joined(separator: "\u{0000}"))
            let chapterIDs = Array(NSOrderedSet(array: items.map { $0.item.chapterID })) as? [String] ?? []
            return AudiobookBillablePreflight(providerID: first.profile.providerID, voiceIdentifier: first.profile.voiceIdentifier, modelIdentifier: first.profile.modelIdentifier, exactCharacterCount: items.reduce(0) { $0 + $1.chunkText.utf16.count }, reviewedTextFingerprint: textFingerprint, priorAttemptedCharacters: prior, maximumChunkCharacters: items.map { $0.chunkText.utf16.count }.max() ?? 0, selectedChapterIDs: chapterIDs)
        }
    }

    func cancel(_ jobID: UUID? = nil) {
        let target = jobID ?? currentJob
        jobs[target ?? UUID()]?.task.cancel()
    }

    func snapshot(for jobID: UUID? = nil) -> AudiobookJobSnapshot? {
        let target = jobID ?? currentJob
        guard let target, let job = jobs[target] else { return snapshotFromManifest() }
        return job.snapshot
    }

    func updates(for projectID: UUID) -> AsyncStream<AudiobookJobSnapshot> {
        let streamID = UUID()
        let (stream, continuation) = AsyncStream<AudiobookJobSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(32))
        if projectID == self.projectID {
            updateContinuations[projectID, default: [:]][streamID] = continuation
            continuation.yield(snapshotFromManifest())
        } else { continuation.finish() }
        continuation.onTermination = { [weak self] _ in Task { await self?.removeContinuation(projectID: projectID, id: streamID) } }
        return stream
    }

    func verifiedAudio(chapterIDs: [String]? = nil) throws -> [AudiobookChunkCheckpoint] {
        let selectedChapterIDs = chapterIDs.map(Set.init) ?? Set(manifest.chapterOrder)
        let expected = manifest.chunks.filter { $0.state != .stale && selectedChapterIDs.contains($0.chapterID) }
        guard !expected.isEmpty else { throw AudiobookProductionError.noSelectedAudio }
        for record in expected where record.state != .complete || !isVerified(record) {
            throw AudiobookProductionError.missingVerifiedAudio(record.id)
        }
        let selected = expected.sorted {
            if $0.chapterID != $1.chapterID { return manifestOrder($0.chapterID) < manifestOrder($1.chapterID) }
            if $0.itemOrder != $1.itemOrder { return $0.itemOrder < $1.itemOrder }
            return $0.chunkIndex < $1.chunkIndex
        }
        return selected
    }

    func inspect(chapterIDs: [String]? = nil) async throws -> AudiobookAudioQualityReport {
        let records = try verifiedAudio(chapterIDs: chapterIDs)
        let sources = records.map { projectDirectory.appendingPathComponent($0.relativePath) }
        return try await AudiobookAudioQualityAnalyzer.inspect(sources: sources, sourceIDs: records.map(\.chapterID))
    }

    func export(_ request: AudiobookExportRequest) async throws -> AudiobookVerifiedExport {
        let records = try verifiedAudio(chapterIDs: request.chapterIDs)
        try FileManager.default.createDirectory(at: request.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sources = records.map { projectDirectory.appendingPathComponent($0.relativePath) }
        let sourceIDs = records.map(\.chapterID)
        let plan = try await AudiobookAudioQualityAnalyzer.plan(sources: sources, settings: request.mastering, sourceIDs: sourceIDs)
        let gain = plan.appliedGainDB
        try Self.validateExportDiskSpace(request, duration: plan.measured.totalDurationSeconds)
        let staging = Self.stagingURL(for: request.destination)
        defer { try? FileManager.default.removeItem(at: staging) }
        switch request.format {
        case .mp3:
            let exported = try await AudiobookMP3Exporter.export(
                sources: sources,
                metadata: AudiobookMP3Metadata(title: request.title, author: request.author, album: request.album),
                settings: request.mp3Settings,
                to: staging,
                gainDB: gain
            )
            let quality = try await AudiobookAudioQualityAnalyzer.inspect(sources: [staging])
            try Self.atomicReplace(staging, request.destination)
            return AudiobookVerifiedExport(fileURL: request.destination, format: .mp3, bytes: exported.bytes, durationSeconds: exported.duration, sampleRate: exported.sampleRate, channels: exported.channels, bitrateKbps: exported.bitrateKbps, metadataTitle: exported.title, metadataAuthor: exported.author, quality: quality, mastering: plan)
        case .wav:
            try await Task.detached {
                try AudiobookAudioExporter.exportWAV(sources: sources, to: staging, gainDB: gain)
            }.value
            let verification = try Self.verifyPCM(staging, expectedDuration: plan.measured.totalDurationSeconds)
            let quality = try await AudiobookAudioQualityAnalyzer.inspect(sources: [staging])
            try Self.atomicReplace(staging, request.destination)
            return AudiobookVerifiedExport(fileURL: request.destination, format: .wav, bytes: verification.bytes, durationSeconds: verification.duration, sampleRate: verification.sampleRate, channels: verification.channels, bitrateKbps: nil, metadataTitle: request.title, metadataAuthor: request.author, quality: quality, mastering: plan)
        case .m4a:
            try await AudiobookAudioExporter.exportM4A(sources: sources, title: request.title, author: request.author, to: staging, gainDB: gain)
            let verification = try await Self.verifyM4A(staging, expectedDuration: plan.measured.totalDurationSeconds, title: request.title, author: request.author)
            let quality = try await AudiobookAudioQualityAnalyzer.inspect(sources: [staging])
            try Self.atomicReplace(staging, request.destination)
            return AudiobookVerifiedExport(fileURL: request.destination, format: .m4a, bytes: verification.bytes, durationSeconds: verification.duration, sampleRate: verification.sampleRate, channels: verification.channels, bitrateKbps: verification.bitrate, metadataTitle: request.title, metadataAuthor: request.author, quality: quality, mastering: plan)
        }
    }

    private func prepareWork(_ request: AudiobookRenderRequest) async throws -> [Work] {
        let items = request.items.filter { item in request.scope.kind == .wholeBook || request.scope.selectedChapterIDs.contains(item.chapterID) }
        guard !items.isEmpty else { throw AudiobookProductionError.noSelectedAudio }
        guard items.allSatisfy({ !$0.id.isEmpty && !$0.chapterID.isEmpty }), Set(items.map(\.id)).count == items.count else {
            throw AudiobookProductionError.invalidSource("Narration segments must have non-empty, unique stable IDs and chapter IDs.")
        }
        var occurrenceCounts: [String: Int] = [:]
        var work: [Work] = []
        var desiredIDs = Set<String>()
        for (itemOrder, item) in items.enumerated() {
            let profile = try request.assignmentPlan.profile(for: item)
            guard profile.maximumRequestCharacters > 0 else { throw AudiobookProductionError.providerError("Provider request limit must be positive.") }
            let chunks = AudiobookProjectManifest.chunks(item.narrationText, maximumCharacters: min(3_500, profile.maximumRequestCharacters))
            let textFingerprint = item.sourceTextFingerprint.isEmpty ? AudiobookChapter.digest(item.narrationText) : item.sourceTextFingerprint
            let settingsFingerprint = try fingerprint(profile)
            for (index, chunk) in chunks.enumerated() {
                let chunkFingerprint = AudiobookChapter.digest(chunk)
                let occurrenceKey = item.chapterID + "\n" + chunkFingerprint
                let occurrence = occurrenceCounts[occurrenceKey, default: 0]
                occurrenceCounts[occurrenceKey] = occurrence + 1
                let stableID = AudiobookChapter.digest("\(item.chapterID)\n\(chunkFingerprint)\n\(occurrence)\n\(settingsFingerprint)")
                desiredIDs.insert(stableID)
                let relative = "chunks/\(item.chapterIDHash)/\(stableID).\(profile.providerID == "elevenlabs" ? "mp3" : "caf")"
                var checkpoint = AudiobookChunkCheckpoint(id: stableID, chapterID: item.chapterID, chapterTitle: item.chapterTitle, itemID: item.id, chunkIndex: index, sourceTextFingerprint: textFingerprint, narrationTextFingerprint: chunkFingerprint, settingsFingerprint: settingsFingerprint, providerID: profile.providerID, voiceIdentifier: profile.voiceIdentifier, modelIdentifier: profile.modelIdentifier, relativePath: relative, itemOrder: itemOrder, charactersSubmitted: chunk.utf16.count, state: .queued)
                var existing = manifest.chunks.first { $0.id == stableID }
                if let existing {
                    checkpoint.billedCharacters = existing.billedCharacters
                    checkpoint.billableCharactersAttempted = existing.billableCharactersAttempted
                }
                var reusable = existing.map { record in
                    !request.forceRegenerationIDs.contains(item.id) && record.state == .complete && record.narrationTextFingerprint == chunkFingerprint && record.settingsFingerprint == settingsFingerprint && isVerified(record)
                } ?? false
                // Recover a response atomically moved into place just before an interruption
                // prevented the manifest checkpoint from being written.
                if !reusable, var interrupted = existing,
                   interrupted.state == .rendering, interrupted.checksum == nil,
                   interrupted.narrationTextFingerprint == chunkFingerprint,
                   interrupted.settingsFingerprint == settingsFingerprint {
                    let url = projectDirectory.appendingPathComponent(interrupted.relativePath)
                    if FileManager.default.fileExists(atPath: url.path),
                       let media = try? Self.verifyMedia(url), let checksum = Self.checksum(url) {
                        interrupted.sourceTextFingerprint = textFingerprint
                        interrupted.itemID = item.id
                        interrupted.itemOrder = itemOrder
                        interrupted.chapterTitle = item.chapterTitle
                        interrupted.state = .complete
                        interrupted.checksum = checksum
                        interrupted.bytes = media.bytes
                        interrupted.durationSeconds = media.duration
                        interrupted.completedAt = Date()
                        if interrupted.providerID == "elevenlabs" { interrupted.billedCharacters = interrupted.charactersSubmitted }
                        interrupted.lastError = nil
                        checkpoint = interrupted
                        upsert(interrupted)
                        existing = interrupted
                        reusable = true
                    }
                }
                if reusable, let existing {
                    checkpoint = existing
                    checkpoint.sourceTextFingerprint = textFingerprint
                    checkpoint.itemID = item.id
                    checkpoint.itemOrder = itemOrder
                    checkpoint.chapterTitle = item.chapterTitle
                    upsert(checkpoint)
                }
                else {
                    checkpoint.state = .queued
                    checkpoint.lastError = nil
                    upsert(checkpoint)
                }
                work.append(Work(item: item, profile: profile, itemOrder: itemOrder, chunkIndex: index, chunkText: chunk, checkpoint: checkpoint, reusable: reusable))
            }
        }
        let selectedChapterIDs = Set(items.map(\.chapterID))
        for index in manifest.chunks.indices where selectedChapterIDs.contains(manifest.chunks[index].chapterID) && !desiredIDs.contains(manifest.chunks[index].id) {
            manifest.chunks[index].state = .stale
            manifest.chunks[index].lastError = "Source text or narration settings changed; regenerate this chunk."
        }
        return work
    }

    private func execute(_ work: [Work], request: AudiobookRenderRequest, jobID: UUID) async {
        manifest.state = .rendering
        manifest.updatedAt = Date()
        do { try persistManifest() } catch { await finish(jobID, state: .failed, error: error.localizedDescription); return }
        var completed = work.filter(\.reusable).count
        var characters = 0
        for (position, item) in work.enumerated() where !item.reusable {
            do {
                try Task.checkCancellation()
                guard let provider = providers[item.profile.providerID] else { throw AudiobookProductionError.providerUnavailable(item.profile.providerID) }
                var checkpoint = item.checkpoint
                checkpoint.state = .rendering
                checkpoint.lastError = nil
                upsert(checkpoint)
                manifest.updatedAt = Date()
                try persistManifest()
                publish(makeSnapshot(jobID: jobID, total: work.count, completed: completed, current: checkpoint))

                let mediaURL = projectDirectory.appendingPathComponent(checkpoint.relativePath)
                try FileManager.default.createDirectory(at: mediaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let temporary = mediaURL.deletingLastPathComponent().appendingPathComponent("\(mediaURL.lastPathComponent).\(UUID().uuidString).partial.\(item.profile.providerID == "elevenlabs" ? "mp3" : "caf")")
                defer { temporary.path.withCString { _ = unlink($0) } }
                var attempt = 0
                while true {
                    do {
                        try Task.checkCancellation()
                        if item.profile.providerID == "elevenlabs" {
                            let approval = request.billableApprovals.first {
                                $0.providerID == item.profile.providerID &&
                                $0.voiceIdentifier == item.profile.voiceIdentifier &&
                                $0.modelIdentifier == item.profile.modelIdentifier
                            }
                            guard let approval else {
                                throw AudiobookProductionError.billableApprovalRequired(provider: item.profile.providerID, voice: item.profile.voiceIdentifier, model: item.profile.modelIdentifier, characters: item.chunkText.utf16.count)
                            }
                            let submitted = manifest.chunks.filter {
                                $0.providerID == item.profile.providerID &&
                                $0.voiceIdentifier == item.profile.voiceIdentifier &&
                                $0.modelIdentifier == item.profile.modelIdentifier
                            }.reduce(0) { $0 + $1.billableCharactersAttempted }
                            let alreadyUsed = max(approval.charactersAlreadyUsed, submitted)
                            let available = approval.characterBudget - alreadyUsed
                            guard available >= item.chunkText.utf16.count else {
                                throw AudiobookProductionError.characterBudgetExceeded(provider: item.profile.providerID, requested: item.chunkText.utf16.count, available: max(available, 0))
                            }
                            checkpoint.billableCharactersAttempted += item.chunkText.utf16.count
                            upsert(checkpoint)
                            manifest.updatedAt = Date()
                            try persistManifest()
                        }
                        try await provider.synthesize(text: item.chunkText, profile: item.profile, to: temporary)
                        break
                    } catch let failure as AudiobookProviderFailure {
                        if case .retryable = failure, attempt < request.maximumRetries {
                            try await Task.sleep(for: .milliseconds(250 * (1 << attempt)))
                            attempt += 1
                            continue
                        }
                        throw failure
                    }
                }
                let verified = try Self.verifyMedia(temporary)
                try Self.atomicReplace(temporary, mediaURL)
                checkpoint.state = .complete
                checkpoint.checksum = Self.checksum(mediaURL)
                checkpoint.bytes = verified.bytes
                checkpoint.durationSeconds = verified.duration
                if item.profile.providerID == "elevenlabs" { checkpoint.billedCharacters += checkpoint.charactersSubmitted }
                checkpoint.completedAt = Date()
                checkpoint.lastError = nil
                upsert(checkpoint)
                characters += checkpoint.charactersSubmitted
                completed += 1
                manifest.sourceFingerprint = request.sourceFingerprint
                manifest.updatedAt = Date()
                try persistManifest()
                publish(makeSnapshot(jobID: jobID, total: work.count, completed: completed, current: nil, characters: characters))
            } catch is CancellationError {
                var checkpoint = manifest.chunks.first(where: { $0.id == item.checkpoint.id }) ?? item.checkpoint
                checkpoint.state = .queued
                upsert(checkpoint)
                manifest.state = .cancelled
                manifest.updatedAt = Date()
                try? persistManifest()
                publish(makeSnapshot(jobID: jobID, total: work.count, completed: completed, current: nil, characters: characters, state: .cancelled))
                return
            } catch {
                var checkpoint = manifest.chunks.first(where: { $0.id == item.checkpoint.id }) ?? item.checkpoint
                checkpoint.state = .failed
                checkpoint.lastError = error.localizedDescription
                upsert(checkpoint)
                manifest.state = completed > 0 ? .partial : .failed
                manifest.lastError = error.localizedDescription
                manifest.updatedAt = Date()
                try? persistManifest()
                publish(makeSnapshot(jobID: jobID, total: work.count, completed: completed, current: checkpoint, characters: characters, state: manifest.state, error: error.localizedDescription))
                jobs[jobID]?.task.cancel()
                return
            }
            _ = position
        }
        await finish(jobID, state: .complete, error: nil, completed: completed, total: work.count, characters: characters)
    }

    private func finish(_ id: UUID, state: AudiobookProductionManifest.State, error: String?, completed: Int = 0, total: Int = 0, characters: Int = 0) async {
        manifest.state = state
        manifest.lastError = error
        manifest.updatedAt = Date()
        try? persistManifest()
        publish(makeSnapshot(jobID: id, total: total, completed: completed, current: nil, characters: characters, state: state, error: error))
    }

    private func validateBillableApprovals(work: [Work], approvals: [AudiobookBillableApproval]) throws {
        let cloud = Dictionary(grouping: work.filter { !$0.reusable && $0.profile.providerID == "elevenlabs" }, by: { "\($0.profile.providerID)|\($0.profile.voiceIdentifier)|\($0.profile.modelIdentifier)" })
        for (key, chunks) in cloud {
            guard let first = chunks.first else { continue }
            let needed = chunks.reduce(0) { $0 + $1.chunkText.utf16.count }
            guard let approval = approvals.first(where: { "\($0.providerID)|\($0.voiceIdentifier)|\($0.modelIdentifier)" == key }),
                  approval.reviewedCharacterCount == needed,
                  approval.reviewedTextFingerprint == AudiobookChapter.digest(chunks.map(\.chunkText).joined(separator: "\u{0000}")) else {
                throw AudiobookProductionError.billableApprovalRequired(provider: first.profile.providerID, voice: first.profile.voiceIdentifier, model: first.profile.modelIdentifier, characters: needed)
            }
            let priorSubmitted = manifest.chunks.filter {
                $0.providerID == first.profile.providerID &&
                $0.voiceIdentifier == first.profile.voiceIdentifier &&
                $0.modelIdentifier == first.profile.modelIdentifier
            }.reduce(0) { $0 + $1.billableCharactersAttempted }
            let alreadyUsed = max(approval.charactersAlreadyUsed, priorSubmitted)
            let available = approval.characterBudget - alreadyUsed
            guard approval.characterBudget > 0, available >= needed else { throw AudiobookProductionError.characterBudgetExceeded(provider: first.profile.providerID, requested: needed, available: max(available, 0)) }
        }
    }

    private func validateDiskSpace(work: [Work]) throws {
        let pending = work.filter { !$0.reusable }
        let characters = pending.reduce(0) { $0 + $1.chunkText.utf16.count }
        let required = max(Int64(32 * 1_024 * 1_024), Int64(characters) * 128)
        let directory = FileManager.default.fileExists(atPath: projectDirectory.path) ? projectDirectory : projectDirectory.deletingLastPathComponent()
        let free = ((try? FileManager.default.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize]) as? NSNumber)?.int64Value ?? 0
        guard free >= required else { throw AudiobookProductionError.insufficientDiskSpace(required: required, available: free) }
    }

    private func uniqueProfiles(_ work: [Work]) -> [AudiobookNarratorProfile] {
        var seen = Set<String>()
        return work.compactMap { item in
            let key = (try? fingerprint(item.profile)) ?? UUID().uuidString
            return seen.insert(key).inserted ? item.profile : nil
        }
    }

    private func fingerprint(_ profile: AudiobookNarratorProfile) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return AudiobookChapter.digest(String(decoding: try encoder.encode(profile), as: UTF8.self))
    }

    private func isVerified(_ checkpoint: AudiobookChunkCheckpoint) -> Bool {
        guard checkpoint.state == .complete else { return false }
        let url = projectDirectory.appendingPathComponent(checkpoint.relativePath)
        guard FileManager.default.fileExists(atPath: url.path), let expected = checkpoint.checksum, Self.checksum(url) == expected else { return false }
        return (try? Self.verifyMedia(url)) != nil
    }

    private func upsert(_ checkpoint: AudiobookChunkCheckpoint) {
        if let index = manifest.chunks.firstIndex(where: { $0.id == checkpoint.id }) { manifest.chunks[index] = checkpoint }
        else { manifest.chunks.append(checkpoint) }
    }

    private func persistManifest() throws {
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
        let decoder = JSONDecoder()
        let verified = try decoder.decode(AudiobookProductionManifest.self, from: Data(contentsOf: manifestURL))
        guard verified == manifest else { throw AudiobookProductionError.invalidManifest }
    }

    private func makeSnapshot(jobID: UUID, total: Int, completed: Int, current: AudiobookChunkCheckpoint?, characters: Int = 0, state: AudiobookProductionManifest.State? = nil, error: String? = nil) -> AudiobookJobSnapshot {
        AudiobookJobSnapshot(projectID: projectID, jobID: jobID, state: state ?? manifest.state, totalChunks: total, completedChunks: completed, currentChapterID: current?.chapterID, currentChunkIndex: current?.chunkIndex, charactersSubmitted: characters, lastError: error ?? manifest.lastError, updatedAt: Date())
    }

    private func snapshotFromManifest() -> AudiobookJobSnapshot {
        AudiobookJobSnapshot(projectID: projectID, jobID: manifest.currentJobID, state: manifest.state, totalChunks: manifest.chunks.count, completedChunks: manifest.chunks.filter { $0.state == .complete && isVerified($0) }.count, currentChapterID: manifest.chunks.first(where: { $0.state == .rendering })?.chapterID, currentChunkIndex: manifest.chunks.first(where: { $0.state == .rendering })?.chunkIndex, charactersSubmitted: manifest.chunks.filter { $0.state == .complete }.reduce(0) { $0 + $1.charactersSubmitted }, lastError: manifest.lastError, updatedAt: manifest.updatedAt)
    }

    private func publish(_ snapshot: AudiobookJobSnapshot) {
        if let jobID = snapshot.jobID { jobs[jobID]?.snapshot = snapshot }
        for continuation in updateContinuations[projectID]?.values ?? [:].values { continuation.yield(snapshot) }
    }

    private func removeContinuation(projectID: UUID, id: UUID) { updateContinuations[projectID]?.removeValue(forKey: id) }

    private func manifestOrder(_ id: String) -> Int {
        manifest.chapterOrder.firstIndex(of: id) ?? Int.max
    }

    private static func verifyMedia(_ url: URL) throws -> (bytes: Int64, duration: Double) {
        let audio = try AVAudioFile(forReading: url)
        guard audio.length > 0, audio.processingFormat.sampleRate > 0 else { throw AudiobookProductionError.exportVerification("Audio contains no decodable frames.") }
        let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(min(audio.length, 4_096)))!
        try audio.read(into: buffer)
        guard buffer.frameLength > 0 else { throw AudiobookProductionError.exportVerification("Audio could not be decoded.") }
        let bytes = Int64((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
        return (bytes, Double(audio.length) / audio.processingFormat.sampleRate)
    }

    private static func checksum(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func removeAbandonedChunkTemporaries(in projectDirectory: URL) {
        let chunkDirectory = projectDirectory.appendingPathComponent("chunks", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: chunkDirectory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in enumerator where url.lastPathComponent.contains(".partial.") {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func atomicReplace(_ source: URL, _ destination: URL) throws {
        let result = source.path.withCString { from in destination.path.withCString { to in rename(from, to) } }
        guard result == 0 else { throw AudiobookProductionError.exportVerification("Could not atomically install the verified media file: \(String(cString: strerror(errno)))") }
    }

    private static func verifyPCM(_ url: URL, expectedDuration: Double) throws -> (bytes: Int64, duration: Double, sampleRate: Double, channels: Int) {
        let audio = try AVAudioFile(forReading: url)
        let duration = Double(audio.length) / audio.fileFormat.sampleRate
        guard audio.length > 0, abs(duration - expectedDuration) <= max(0.35, expectedDuration * 0.01) else { throw AudiobookProductionError.exportVerification("WAV duration does not match the rendered source.") }
        return (Int64((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0), duration, audio.fileFormat.sampleRate, Int(audio.fileFormat.channelCount))
    }

    private static func verifyM4A(_ url: URL, expectedDuration: Double, title: String, author: String) async throws -> (bytes: Int64, duration: Double, sampleRate: Double, channels: Int, bitrate: Int?) {
        let asset = AVURLAsset(url: url)
        let time = try await asset.load(.duration)
        let duration = CMTimeGetSeconds(time)
        guard duration.isFinite, duration > 0, abs(duration - expectedDuration) <= max(0.35, expectedDuration * 0.01) else { throw AudiobookProductionError.exportVerification("M4A duration does not match the rendered source.") }
        let metadata = try await asset.load(.commonMetadata)
        let titleItem = metadata.first(where: { $0.commonKey == .commonKeyTitle })
        let authorItem = metadata.first(where: { $0.commonKey == .commonKeyArtist })
        let actualTitle = try await titleItem?.load(.stringValue)
        let actualAuthor = try await authorItem?.load(.stringValue)
        guard actualTitle == title, actualAuthor == author else { throw AudiobookProductionError.exportVerification("M4A title/author metadata did not match the requested Unicode metadata.") }
        let audio = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4_096)!
        try audio.read(into: buffer)
        guard buffer.frameLength > 0 else { throw AudiobookProductionError.exportVerification("M4A audio could not be decoded.") }
        let bytes = Int64((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
        return (bytes, duration, audio.fileFormat.sampleRate, Int(audio.fileFormat.channelCount), nil)
    }

    private static func stagingURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent("\(destination.deletingPathExtension().lastPathComponent).\(UUID().uuidString).partial.\(destination.pathExtension)")
    }

    private static func validateExportDiskSpace(_ request: AudiobookExportRequest, duration: Double) throws {
        let estimatedBytes: Double
        switch request.format {
        case .wav: estimatedBytes = duration * 44_100 * 2 * 2 + 1_000_000
        case .m4a: estimatedBytes = duration * 192_000 / 8 + 2_000_000
        case .mp3: return // The LAME exporter performs bitrate-accurate preflight itself.
        }
        let required = Int64(ceil(estimatedBytes))
        let folder = request.destination.deletingLastPathComponent()
        let candidate = FileManager.default.fileExists(atPath: folder.path) ? folder : folder.deletingLastPathComponent()
        let free = ((try? FileManager.default.attributesOfFileSystem(forPath: candidate.path)[.systemFreeSize]) as? NSNumber)?.int64Value ?? 0
        guard free >= required else { throw AudiobookProductionError.insufficientDiskSpace(required: required, available: free) }
    }

}

private extension AudiobookSourceItem {
    var chapterIDHash: String { String(AudiobookChapter.digest(chapterID).prefix(24)) }
}
