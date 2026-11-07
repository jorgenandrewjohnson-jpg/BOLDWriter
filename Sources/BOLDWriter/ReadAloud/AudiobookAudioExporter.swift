@preconcurrency import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum AudiobookExportFormat {
    case m4a
    case wav

    var fileExtension: String { switch self { case .m4a: "m4a"; case .wav: "wav" } }
    var contentType: UTType { switch self { case .m4a: .mpeg4Audio; case .wav: .wav } }
}

enum AudiobookAudioExportError: LocalizedError {
    case noSources
    case cannotCreateComposition
    case noAudioTrack(URL)
    case conversion(String)
    case export(String)

    var errorDescription: String? {
        switch self {
        case .noSources: "Render at least one chapter before exporting the audiobook."
        case .cannotCreateComposition: "The audiobook audio composition could not be created."
        case .noAudioTrack(let url): "No audio track was found in \(url.lastPathComponent)."
        case .conversion(let message): "WAV audio conversion failed: \(message)"
        case .export(let message): "M4A audio export failed: \(message)"
        }
    }
}

enum AudiobookAudioExporter {
    static func exportM4A(sources: [URL], title: String, author: String, to destination: URL, gainDB: Double = 0) async throws {
        guard !sources.isEmpty else { throw AudiobookAudioExportError.noSources }
        guard gainDB.isFinite, (-24...24).contains(gainDB) else { throw AudiobookAudioExportError.export("The mastering gain must be between -24 and +24 dB.") }
        try removeExistingDestination(destination)
        let composition = AVMutableComposition()
        guard let destinationTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AudiobookAudioExportError.cannotCreateComposition
        }

        var insertionTime = CMTime.zero
        for source in sources {
            let asset = AVURLAsset(url: source)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let track = tracks.first else { throw AudiobookAudioExportError.noAudioTrack(source) }
            let duration = try await asset.load(.duration)
            try destinationTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: insertionTime)
            insertionTime = CMTimeAdd(insertionTime, duration)
        }

        let mix: AVAudioMix?
        if gainDB != 0 {
            let mutableMix = AVMutableAudioMix()
            let parameters = AVMutableAudioMixInputParameters(track: destinationTrack)
            parameters.setVolume(Float(pow(10, gainDB / 20)), at: .zero)
            mutableMix.inputParameters = [parameters]
            mix = mutableMix
        } else { mix = nil }

        // Reader output fixes the delivery layout before AAC encoding. Apple speech
        // synthesis commonly returns mono CAF, so a plain preset export can otherwise
        // produce a mono M4A while WAV and MP3 are 44.1 kHz stereo.
        let reader = try AVAssetReader(asset: composition)
        let pcmSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let readerOutput = AVAssetReaderAudioMixOutput(audioTracks: [destinationTrack], audioSettings: pcmSettings)
        readerOutput.audioMix = mix
        guard reader.canAdd(readerOutput) else { throw AudiobookAudioExportError.export("The Apple audio reader cannot produce normalized 44.1 kHz stereo PCM.") }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .m4a)
        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { throw AudiobookAudioExportError.export("The Apple AAC encoder cannot create the requested 44.1 kHz stereo M4A.") }
        writer.add(writerInput)
        writer.metadata = [
            commonMetadata(.commonIdentifierTitle, value: title),
            commonMetadata(.commonIdentifierArtist, value: author)
        ].compactMap { $0 }
        guard reader.startReading() else { throw AudiobookAudioExportError.export(reader.error?.localizedDescription ?? "The Apple audio reader could not start.") }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw AudiobookAudioExportError.export(writer.error?.localizedDescription ?? "The Apple AAC encoder could not start.")
        }
        writer.startSession(atSourceTime: .zero)

        let context = M4AEncodingContext(reader: reader, readerOutput: readerOutput, writer: writer, writerInput: writerInput)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "com.boldwriter.audiobook.m4a-encoder")
            writerInput.requestMediaDataWhenReady(on: queue) {
                while context.writerInput.isReadyForMoreMediaData {
                    if let sample = context.readerOutput.copyNextSampleBuffer() {
                        guard context.writerInput.append(sample) else {
                            let error = context.writer.error ?? AudiobookAudioExportError.export("The AAC writer rejected a decoded audio block.")
                            context.reader.cancelReading()
                            context.writer.cancelWriting()
                            continuation.resume(throwing: error)
                            return
                        }
                    } else {
                        if context.reader.status == .failed {
                            let error = context.reader.error ?? AudiobookAudioExportError.export("The audio reader failed while encoding M4A.")
                            context.writer.cancelWriting()
                            continuation.resume(throwing: error)
                            return
                        }
                        context.writerInput.markAsFinished()
                        context.writer.finishWriting {
                            if context.writer.status == .completed { continuation.resume() }
                            else { continuation.resume(throwing: context.writer.error ?? AudiobookAudioExportError.export("The AAC encoder did not complete the M4A file.")) }
                        }
                        return
                    }
                }
            }
        }
    }

    static func exportWAV(sources: [URL], to destination: URL, sampleRate: Double = 44_100, channelCount: AVAudioChannelCount = 2, gainDB: Double = 0) throws {
        guard !sources.isEmpty else { throw AudiobookAudioExportError.noSources }
        guard gainDB.isFinite, (-24...24).contains(gainDB) else { throw AudiobookAudioExportError.conversion("The mastering gain must be between -24 and +24 dB.") }
        let linearGain = pow(10, gainDB / 20)
        try removeExistingDestination(destination)
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channelCount, interleaved: true) else {
            throw AudiobookAudioExportError.conversion("Could not configure the PCM output format.")
        }
        let output = try AVAudioFile(forWriting: destination, settings: targetFormat.settings, commonFormat: .pcmFormatInt16, interleaved: true)

        for source in sources {
            let input = try AVAudioFile(forReading: source)
            guard let converter = AVAudioConverter(from: input.processingFormat, to: targetFormat) else {
                throw AudiobookAudioExportError.conversion("Could not convert \(source.lastPathComponent) to 44.1 kHz stereo PCM.")
            }
            while input.framePosition < input.length {
                let remaining = input.length - input.framePosition
                let capacity = AVAudioFrameCount(min(remaining, 8_192))
                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: capacity) else {
                    throw AudiobookAudioExportError.conversion("Could not allocate an input audio buffer.")
                }
                try input.read(into: inputBuffer, frameCount: capacity)
                guard inputBuffer.frameLength > 0 else { break }

                let outputCapacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * sampleRate / input.processingFormat.sampleRate) + 1_024)
                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
                    throw AudiobookAudioExportError.conversion("Could not allocate an output audio buffer.")
                }
                var conversionError: NSError?
                var suppliedInput = false
                let isLastBuffer = input.framePosition >= input.length
                let result = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
                    if !suppliedInput {
                        suppliedInput = true
                        inputStatus.pointee = .haveData
                        return inputBuffer
                    }
                    inputStatus.pointee = isLastBuffer ? .endOfStream : .noDataNow
                    return nil
                }
                if result == .error {
                    throw AudiobookAudioExportError.conversion(conversionError?.localizedDescription ?? "The PCM converter returned an error.")
                }
                if outputBuffer.frameLength > 0 {
                    if linearGain != 1, let samples = outputBuffer.int16ChannelData?.pointee {
                        let sampleCount = Int(outputBuffer.frameLength) * Int(channelCount)
                        for index in 0..<sampleCount {
                            let scaled = (Double(samples[index]) * linearGain).rounded()
                            samples[index] = Int16(min(max(scaled, -32_768), 32_767))
                        }
                    }
                    try output.write(from: outputBuffer)
                }
            }
        }
    }

    private static func commonMetadata(_ identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem? {
        guard !value.isEmpty else { return nil }
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item.copy() as? AVMetadataItem
    }

    private static func removeExistingDestination(_ destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
    }
}

/// AVFoundation's pull-based reader/writer callback is serialized on one private queue.
/// The checked box documents that confinement for Swift's stricter Sendable diagnostics.
private final class M4AEncodingContext: @unchecked Sendable {
    let reader: AVAssetReader
    let readerOutput: AVAssetReaderAudioMixOutput
    let writer: AVAssetWriter
    let writerInput: AVAssetWriterInput

    init(reader: AVAssetReader, readerOutput: AVAssetReaderAudioMixOutput, writer: AVAssetWriter, writerInput: AVAssetWriterInput) {
        self.reader = reader
        self.readerOutput = readerOutput
        self.writer = writer
        self.writerInput = writerInput
    }
}
