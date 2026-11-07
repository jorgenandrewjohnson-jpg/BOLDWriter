@preconcurrency import AVFoundation
import Foundation

struct AudiobookMasteringSettings: Codable, Equatable, Sendable {
    enum Preset: String, Codable, Sendable { case original, balancedSpokenWord }
    var preset: Preset = .original
    var targetIntegratedLUFS: Double = -18
    var samplePeakCeilingDBFS: Double = -1.5
    var appliesConstantGain: Bool { preset == .balancedSpokenWord }

    static let original = AudiobookMasteringSettings()
    static let balancedSpokenWord = AudiobookMasteringSettings(preset: .balancedSpokenWord)
}

struct AudiobookChapterJoinMeasurement: Codable, Equatable, Sendable {
    var leftChapterID: String
    var rightChapterID: String
    var sampleJumpDBFS: Double
    var warning: String?
}

struct AudiobookAudioQualityReport: Codable, Equatable, Sendable {
    var integratedLoudnessLUFS: Double?
    var samplePeakDBFS: Double
    var clippedSampleCount: Int64
    var longestQuietRunSeconds: Double
    var totalDurationSeconds: Double
    var analysisSampleRate: Double
    var channelCount: Int
    var sourceFormats: [String]
    var duplicateSourceCount: Int
    var missingSources: [URL]
    var chapterJoins: [AudiobookChapterJoinMeasurement]
    var warnings: [String]
}

struct AudiobookMasteringPlan: Codable, Equatable, Sendable {
    var settings: AudiobookMasteringSettings
    var measured: AudiobookAudioQualityReport
    var appliedGainDB: Double
    var predictedSamplePeakDBFS: Double
    var warnings: [String]
}

enum AudiobookAudioInspectionError: LocalizedError {
    case noReadableAudio
    case unsupportedPCM(URL)
    case decode(URL, String)
    case invalidMasteringSettings

    var errorDescription: String? {
        switch self {
        case .noReadableAudio: "No readable audio segments were supplied for inspection."
        case .unsupportedPCM(let url): "Audio from \(url.lastPathComponent) could not be converted to the analysis format."
        case .decode(let url, let message): "Could not inspect \(url.lastPathComponent): \(message)"
        case .invalidMasteringSettings: "The mastering target or peak ceiling is outside the supported range."
        }
    }
}

/// Streaming loudness / peak / silence inspection and non-destructive gain planning.
/// K-weighting coefficients and the 400 ms / 75% overlap / absolute and relative gates
/// follow ITU-R BS.1770-5 Annex 1. The two-channel path is intended for audiobook speech.
enum AudiobookAudioQualityAnalyzer {
    private static let analysisRate = 48_000.0
    private static let analysisFrames: AVAudioFrameCount = 8_192
    private static let gateWindow = 19_200
    private static let gateHop = 4_800
    private static let quietSampleThreshold: Float = 0.001

    static func inspect(
        sources: [URL],
        sourceIDs: [String]? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> AudiobookAudioQualityReport {
        guard !sources.isEmpty else { throw AudiobookAudioInspectionError.noReadableAudio }
        var meter = StreamingMeter()
        var formats: [String] = []
        var missing: [URL] = []
        var duplicates = 0
        var seenPaths = Set<String>()
        var previous: (id: String, left: Float, right: Float)?
        var joins: [AudiobookChapterJoinMeasurement] = []
        let readable = sources.enumerated().filter { _, source in
            guard FileManager.default.fileExists(atPath: source.path) else { missing.append(source); return false }
            let key = source.standardizedFileURL.path
            if !seenPaths.insert(key).inserted { duplicates += 1 }
            return true
        }
        guard !readable.isEmpty else { throw AudiobookAudioInspectionError.noReadableAudio }
        let expectedDuration = try readable.reduce(0.0) { total, item in
            let file = try AVAudioFile(forReading: item.element)
            return total + Double(file.length) / file.processingFormat.sampleRate
        }
        var elapsed: TimeInterval = 0

        for (sourceIndex, source) in readable {
            try Task.checkCancellation()
            do {
                let file = try AVAudioFile(forReading: source)
                formats.append("\(Int(file.fileFormat.sampleRate)) Hz / \(file.fileFormat.channelCount) ch / \(file.fileFormat.commonFormat)")
                guard let target = AVAudioFormat(standardFormatWithSampleRate: analysisRate, channels: 2),
                      let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
                    throw AudiobookAudioInspectionError.unsupportedPCM(source)
                }
                let id = sourceIDs.flatMap { $0.indices.contains(sourceIndex) ? $0[sourceIndex] : nil } ?? source.deletingPathExtension().lastPathComponent
                var firstSample: (Float, Float)?
                var lastSample: (Float, Float)?
                while file.framePosition < file.length {
                    try Task.checkCancellation()
                    let remaining = file.length - file.framePosition
                    let readCount = AVAudioFrameCount(min(remaining, AVAudioFramePosition(analysisFrames)))
                    guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: readCount) else { throw AudiobookAudioInspectionError.unsupportedPCM(source) }
                    try file.read(into: input, frameCount: readCount)
                    guard input.frameLength > 0 else { break }
                    let outputCapacity = AVAudioFrameCount(ceil(Double(input.frameLength) * analysisRate / file.processingFormat.sampleRate) + 2_048)
                    guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outputCapacity) else { throw AudiobookAudioInspectionError.unsupportedPCM(source) }
                    var supplied = false
                    var error: NSError?
                    let status = converter.convert(to: output, error: &error) { _, inputStatus in
                        if !supplied { supplied = true; inputStatus.pointee = .haveData; return input }
                        inputStatus.pointee = .noDataNow; return nil
                    }
                    if status == .error { throw AudiobookAudioInspectionError.decode(source, error?.localizedDescription ?? "The sample-rate converter failed.") }
                    guard output.frameLength > 0, let channels = output.floatChannelData, output.format.channelCount == 2 else { continue }
                    for frame in 0..<Int(output.frameLength) {
                        let left = channels[0][frame]
                        let right = channels[1][frame]
                        if firstSample == nil { firstSample = (left, right) }
                        lastSample = (left, right)
                        meter.consume(left: left, right: right)
                    }
                    elapsed += Double(input.frameLength) / file.processingFormat.sampleRate
                    progress?(min(elapsed / expectedDuration, 0.99))
                }
                if let previous, let firstSample {
                    let delta = max(abs(previous.left - firstSample.0), abs(previous.right - firstSample.1))
                    let jumpDB = 20 * log10(max(Double(delta), 0.000_001))
                    let warning = delta > 0.25 ? "Abrupt sample discontinuity at chapter join (\(String(format: "%.1f", jumpDB)) dBFS)." : nil
                    joins.append(AudiobookChapterJoinMeasurement(leftChapterID: previous.id, rightChapterID: id, sampleJumpDBFS: jumpDB, warning: warning))
                }
                if let lastSample { previous = (id, lastSample.0, lastSample.1) }
            } catch let error as AudiobookAudioInspectionError { throw error }
            catch { throw AudiobookAudioInspectionError.decode(source, error.localizedDescription) }
        }
        let loudness = meter.integratedLoudnessLUFS
        var warnings: [String] = []
        if !missing.isEmpty { warnings.append("\(missing.count) audio source(s) are missing.") }
        if duplicates > 0 { warnings.append("\(duplicates) duplicate source URL(s) were supplied.") }
        if meter.clippedSamples > 0 { warnings.append("\(meter.clippedSamples) decoded samples reached digital full scale.") }
        if meter.longestQuietFrames > Int64(analysisRate * 5) { warnings.append("A quiet run longer than five seconds was detected.") }
        if loudness == nil { warnings.append("Integrated loudness could not be measured because all gating blocks were below −70 LKFS.") }
        warnings += joins.compactMap(\.warning)
        warnings.append("Sample peak is reported; inter-sample true peak was not measured.")
        progress?(1)
        return AudiobookAudioQualityReport(
            integratedLoudnessLUFS: loudness,
            samplePeakDBFS: meter.peak > 0 ? 20 * log10(Double(meter.peak)) : -120,
            clippedSampleCount: meter.clippedSamples,
            longestQuietRunSeconds: Double(meter.longestQuietFrames) / analysisRate,
            totalDurationSeconds: meter.totalFrames / analysisRate,
            analysisSampleRate: analysisRate,
            channelCount: 2,
            sourceFormats: Array(Set(formats)).sorted(),
            duplicateSourceCount: duplicates,
            missingSources: missing,
            chapterJoins: joins,
            warnings: warnings
        )
    }

    static func plan(sources: [URL], settings: AudiobookMasteringSettings, sourceIDs: [String]? = nil) async throws -> AudiobookMasteringPlan {
        guard settings.targetIntegratedLUFS <= -8, settings.targetIntegratedLUFS >= -30,
              settings.samplePeakCeilingDBFS <= -0.1, settings.samplePeakCeilingDBFS >= -12 else {
            throw AudiobookAudioInspectionError.invalidMasteringSettings
        }
        let report = try await inspect(sources: sources, sourceIDs: sourceIDs)
        guard settings.appliesConstantGain, let loudness = report.integratedLoudnessLUFS else {
            return AudiobookMasteringPlan(settings: settings, measured: report, appliedGainDB: 0, predictedSamplePeakDBFS: report.samplePeakDBFS, warnings: report.warnings)
        }
        let loudnessGain = settings.targetIntegratedLUFS - loudness
        let peakLimitedGain = settings.samplePeakCeilingDBFS - report.samplePeakDBFS
        let gain = min(loudnessGain, peakLimitedGain)
        let predictedPeak = report.samplePeakDBFS + gain
        var warnings = report.warnings
        if gain < loudnessGain - 0.01 { warnings.append("Normalization was limited by the configured sample-peak ceiling; target loudness was not reached.") }
        if abs(gain) > 12 { warnings.append("The requested constant gain is large. Review the original recording for noise or unusually low level.") }
        return AudiobookMasteringPlan(settings: settings, measured: report, appliedGainDB: gain, predictedSamplePeakDBFS: predictedPeak, warnings: warnings)
    }

    private struct StreamingMeter {
        private var shelfLeft = BiquadState.shelf
        private var shelfRight = BiquadState.shelf
        private var highPassLeft = BiquadState.highPass
        private var highPassRight = BiquadState.highPass
        private var ring = [Double](repeating: 0, count: AudiobookAudioQualityAnalyzer.gateWindow)
        private var ringPosition = 0
        private var samplesInWindow = 0
        private var samplesSinceGate = 0
        private var windowEnergy = 0.0
        private var gateEnergyByTenth = [Double](repeating: 0, count: 1_101)
        private var gateCountByTenth = [Int64](repeating: 0, count: 1_101)
        private var quietFrames: Int64 = 0
        private(set) var longestQuietFrames: Int64 = 0
        private(set) var totalFrames: Double = 0
        private(set) var peak: Float = 0
        private(set) var clippedSamples: Int64 = 0

        var integratedLoudnessLUFS: Double? {
            let absolute = gatedEnergy(above: -70)
            guard absolute.count > 0, absolute.energy > 0 else { return nil }
            let absoluteLUFS = -0.691 + 10 * log10(absolute.energy / Double(absolute.count))
            let threshold = max(-70, absoluteLUFS - 10)
            let relative = gatedEnergy(above: threshold)
            guard relative.count > 0, relative.energy > 0 else { return nil }
            return -0.691 + 10 * log10(relative.energy / Double(relative.count))
        }

        mutating func consume(left: Float, right: Float) {
            let absL = abs(left), absR = abs(right)
            peak = max(peak, max(absL, absR))
            if absL >= 0.99999 { clippedSamples += 1 }
            if absR >= 0.99999 { clippedSamples += 1 }
            if max(absL, absR) < AudiobookAudioQualityAnalyzer.quietSampleThreshold {
                quietFrames += 1
                longestQuietFrames = max(longestQuietFrames, quietFrames)
            } else { quietFrames = 0 }

            let filteredL = highPassLeft.process(shelfLeft.process(Double(left)))
            let filteredR = highPassRight.process(shelfRight.process(Double(right)))
            let energy = filteredL * filteredL + filteredR * filteredR
            if samplesInWindow == AudiobookAudioQualityAnalyzer.gateWindow { windowEnergy -= ring[ringPosition] }
            else { samplesInWindow += 1 }
            ring[ringPosition] = energy
            windowEnergy += energy
            ringPosition = (ringPosition + 1) % AudiobookAudioQualityAnalyzer.gateWindow
            samplesSinceGate += 1
            if samplesInWindow == AudiobookAudioQualityAnalyzer.gateWindow && samplesSinceGate >= AudiobookAudioQualityAnalyzer.gateHop {
                recordGate(power: windowEnergy / Double(AudiobookAudioQualityAnalyzer.gateWindow))
                samplesSinceGate = 0
            }
            totalFrames += 1
        }

        private mutating func recordGate(power: Double) {
            guard power > 0 else { return }
            let lufs = -0.691 + 10 * log10(power)
            let bin = min(max(Int((lufs + 100) * 10), 0), gateEnergyByTenth.count - 1)
            gateEnergyByTenth[bin] += power
            gateCountByTenth[bin] += 1
        }

        private func gatedEnergy(above threshold: Double) -> (energy: Double, count: Int64) {
            let firstBin = min(max(Int(ceil((threshold + 100) * 10)), 0), gateEnergyByTenth.count)
            guard firstBin < gateEnergyByTenth.count else { return (0, 0) }
            var energy = 0.0
            var count: Int64 = 0
            for bin in firstBin..<gateEnergyByTenth.count {
                energy += gateEnergyByTenth[bin]
                count += gateCountByTenth[bin]
            }
            return (energy, count)
        }
    }

    private struct BiquadState {
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
        static let shelf = BiquadState(b0: 1.53512485958697, b1: -2.69169618940638, b2: 1.19839281085285, a1: -1.69065929318241, a2: 0.73248077421585)
        static let highPass = BiquadState(b0: 1, b1: -2, b2: 1, a1: -1.99004745483398, a2: 0.99007225036621)
    }
}
