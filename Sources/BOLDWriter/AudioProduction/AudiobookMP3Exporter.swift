import AVFoundation
import Darwin
import Foundation
import LAMEEncoder

struct AudiobookMP3Settings: Codable, Hashable, Sendable {
    enum Quality: String, Codable, CaseIterable, Sendable {
        case speech = "Speech 128 kbps"
        case balanced = "Balanced 192 kbps"
        case high = "High 256 kbps"
        case archival = "Maximum 320 kbps"

        var bitrateKbps: Int {
            switch self { case .speech: 128; case .balanced: 192; case .high: 256; case .archival: 320 }
        }
    }

    var quality: Quality = .balanced
    var encoderQuality: Int = 2
    var sampleRate: Double = 44_100
    var channelCount: AVAudioChannelCount = 2

    static let productionDefaults = AudiobookMP3Settings()

    func validate() throws {
        guard [128, 192, 256, 320].contains(quality.bitrateKbps), (0...9).contains(encoderQuality), sampleRate == 44_100, channelCount == 2 else {
            throw AudiobookMP3ExportError.unsupportedSettings
        }
    }
}

struct AudiobookMP3Metadata: Sendable {
    var title: String
    var author: String
    var album: String
    var track: Int?
}

struct AudiobookMP3Verification: Codable, Equatable, Sendable {
    var fileURL: URL
    var bytes: Int64
    var duration: TimeInterval
    var sampleRate: Double
    var channels: Int
    var decodedFrames: Int64
    var bitrateKbps: Int
    var hasID3v2Header: Bool
    var title: String
    var author: String
}

enum AudiobookMP3ExportError: LocalizedError {
    case noSources
    case unsupportedSettings
    case diskSpace(required: Int64, available: Int64)
    case cannotCreateEncoder
    case conversion(String)
    case encode(Int32)
    case corruptOutput(String)
    case replaceDestination(String)

    var errorDescription: String? {
        switch self {
        case .noSources: "Choose at least one rendered audio segment before exporting MP3."
        case .unsupportedSettings: "The selected MP3 settings are not supported by the bundled encoder."
        case .diskSpace(let required, let available): "MP3 export needs about \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)) free, but only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) is available."
        case .cannotCreateEncoder: "The bundled LAME MP3 encoder could not initialize these settings."
        case .conversion(let message): "Audio conversion failed: \(message)"
        case .encode(let code): "The MP3 encoder failed with code \(code)."
        case .corruptOutput(let message): "The MP3 output could not be independently decoded: \(message)"
        case .replaceDestination(let message): "The verified MP3 could not safely replace the destination: \(message)"
        }
    }
}

enum AudiobookMP3Exporter {
    private static let pcmBlockFrames: AVAudioFrameCount = 8_192
    private static let mp3OutputCapacity = 65_536

    /// Encodes a sequence of CAF/WAV/M4A chapter files as one continuous MP3 stream.
    /// PCM conversion and MP3 output are bounded to small blocks regardless of book length.
    @discardableResult
    static func export(
        sources: [URL],
        metadata: AudiobookMP3Metadata,
        settings: AudiobookMP3Settings = .productionDefaults,
        to destination: URL,
        gainDB: Double = 0,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> AudiobookMP3Verification {
        guard !sources.isEmpty else { throw AudiobookMP3ExportError.noSources }
        try settings.validate()
        guard gainDB.isFinite, (-24...24).contains(gainDB) else { throw AudiobookMP3ExportError.unsupportedSettings }
        let linearGain = pow(10, gainDB / 20)
        let expectedDuration = try sourceDuration(sources)
        let required = Int64(ceil(expectedDuration * Double(settings.quality.bitrateKbps * 1_000) / 8.0)) + 2_000_000
        let available = availableDiskSpace(at: destination.deletingLastPathComponent())
        guard available >= required else { throw AudiobookMP3ExportError.diskSpace(required: required, available: available) }

        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent("\(destination.lastPathComponent).\(UUID().uuidString).partial.mp3")
        defer { temporary.path.withCString { _ = unlink($0) } }

        let encoder = makeEncoder(metadata: metadata, settings: settings)
        guard let encoder else { throw AudiobookMP3ExportError.cannotCreateEncoder }
        defer { bold_lame_close(encoder) }

        let descriptor = temporary.path.withCString { open($0, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR) }
        guard descriptor >= 0 else { throw AudiobookMP3ExportError.conversion("Could not create the temporary MP3 output: \(String(cString: strerror(errno)))") }
        _ = close(descriptor)
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: mp3OutputCapacity)
        defer { outputBuffer.deallocate() }

        var processedDuration: TimeInterval = 0
        for source in sources {
            try Task.checkCancellation()
            let file = try AVAudioFile(forReading: source)
            let sourceRate = file.processingFormat.sampleRate
            let converter = makePCMConverter(from: file.processingFormat, settings: settings)
            var framesRead: AVAudioFramePosition = 0
            while file.framePosition < file.length {
                try Task.checkCancellation()
                let remaining = file.length - file.framePosition
                let capacity = AVAudioFrameCount(min(remaining, AVAudioFramePosition(pcmBlockFrames)))
                guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else {
                    throw AudiobookMP3ExportError.conversion("Could not allocate a bounded decoder buffer.")
                }
                try file.read(into: input, frameCount: capacity)
                guard input.frameLength > 0 else { break }
                framesRead += AVAudioFramePosition(input.frameLength)
                let converted = try convert(input, with: converter, settings: settings)
                if converted.frameLength > 0 {
                    guard let samples = converted.int16ChannelData?.pointee else {
                        throw AudiobookMP3ExportError.conversion("The PCM converter did not produce interleaved 16-bit audio.")
                    }
                    if linearGain != 1 {
                        let sampleCount = Int(converted.frameLength) * Int(settings.channelCount)
                        for index in 0..<sampleCount {
                            let scaled = (Double(samples[index]) * linearGain).rounded()
                            samples[index] = Int16(min(max(scaled, -32_768), 32_767))
                        }
                    }
                    let encoded = bold_lame_encode(encoder, samples, Int32(converted.frameLength), outputBuffer, Int32(mp3OutputCapacity))
                    guard encoded >= 0 else { throw AudiobookMP3ExportError.encode(encoded) }
                    if encoded > 0 { try output.write(contentsOf: Data(bytes: outputBuffer, count: Int(encoded))) }
                }
                processedDuration += Double(input.frameLength) / sourceRate
                progress?(min(processedDuration / expectedDuration, 0.99))
            }
        }
        let flushed = bold_lame_flush(encoder, outputBuffer, Int32(mp3OutputCapacity))
        guard flushed >= 0 else { throw AudiobookMP3ExportError.encode(flushed) }
        if flushed > 0 { try output.write(contentsOf: Data(bytes: outputBuffer, count: Int(flushed))) }
        try output.synchronize()
        try output.close()

        let verification = try verify(file: temporary, settings: settings, metadata: metadata, expectedDuration: expectedDuration)
        try atomicReplace(temporary, destination)
        let result = AudiobookMP3Verification(
            fileURL: destination,
            bytes: Int64((try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0),
            duration: verification.duration,
            sampleRate: verification.sampleRate,
            channels: verification.channels,
            decodedFrames: verification.decodedFrames,
            bitrateKbps: settings.quality.bitrateKbps,
            hasID3v2Header: verification.hasID3v2Header,
            title: verification.title,
            author: verification.author
        )
        progress?(1.0)
        return result
    }

    private static func makeEncoder(metadata: AudiobookMP3Metadata, settings: AudiobookMP3Settings) -> UnsafeMutableRawPointer? {
        let title = utf16Z(metadata.title)
        let author = utf16Z(metadata.author)
        let album = utf16Z(metadata.album)
        let track = metadata.track.map { utf16Z(String($0)) }
        return title.withUnsafeBufferPointer { titlePointer in
            author.withUnsafeBufferPointer { authorPointer in
                album.withUnsafeBufferPointer { albumPointer in
                    if let track {
                        return track.withUnsafeBufferPointer { trackPointer in
                            bold_lame_create(Int32(settings.sampleRate), Int32(settings.quality.bitrateKbps), Int32(settings.encoderQuality), titlePointer.baseAddress, authorPointer.baseAddress, albumPointer.baseAddress, trackPointer.baseAddress)
                        }
                    }
                    return bold_lame_create(Int32(settings.sampleRate), Int32(settings.quality.bitrateKbps), Int32(settings.encoderQuality), titlePointer.baseAddress, authorPointer.baseAddress, albumPointer.baseAddress, nil)
                }
            }
        }
    }

    private static func utf16Z(_ value: String) -> [UInt16] { [0xFEFF] + Array(value.utf16) + [0] }

    private static func makePCMConverter(from input: AVAudioFormat, settings: AudiobookMP3Settings) -> AVAudioConverter? {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: settings.sampleRate, channels: settings.channelCount, interleaved: true) else { return nil }
        return AVAudioConverter(from: input, to: output)
    }

    private static func convert(_ input: AVAudioPCMBuffer, with converter: AVAudioConverter?, settings: AudiobookMP3Settings) throws -> AVAudioPCMBuffer {
        guard let converter,
              let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: settings.sampleRate, channels: settings.channelCount, interleaved: true) else {
            throw AudiobookMP3ExportError.conversion("The system cannot convert this chapter's audio format to 44.1 kHz stereo PCM.")
        }
        let ratio = settings.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio) + 2_048)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AudiobookMP3ExportError.conversion("Could not allocate a bounded resampling buffer.")
        }
        var supplied = false
        var converterError: NSError?
        let status = converter.convert(to: output, error: &converterError) { _, inputStatus in
            if !supplied {
                supplied = true
                inputStatus.pointee = .haveData
                return input
            }
            inputStatus.pointee = .noDataNow
            return nil
        }
        if status == .error { throw AudiobookMP3ExportError.conversion(converterError?.localizedDescription ?? "The sample-rate converter returned an error.") }
        return output
    }

    private static func sourceDuration(_ sources: [URL]) throws -> TimeInterval {
        try sources.reduce(0) { total, url in
            let file = try AVAudioFile(forReading: url)
            return total + Double(file.length) / file.processingFormat.sampleRate
        }
    }

    private static func availableDiskSpace(at directory: URL) -> Int64 {
        let path = FileManager.default.fileExists(atPath: directory.path) ? directory : directory.deletingLastPathComponent()
        return ((try? FileManager.default.attributesOfFileSystem(forPath: path.path)[.systemFreeSize]) as? NSNumber)?.int64Value ?? 0
    }

    private static func verify(file: URL, settings: AudiobookMP3Settings, metadata: AudiobookMP3Metadata, expectedDuration: TimeInterval) throws -> (duration: TimeInterval, sampleRate: Double, channels: Int, decodedFrames: Int64, hasID3v2Header: Bool, title: String, author: String) {
        let tags = try readID3v23Metadata(file)
        guard tags.title == metadata.title, tags.author == metadata.author else {
            throw AudiobookMP3ExportError.corruptOutput("ID3v2 title/author tags did not match the requested Unicode metadata.")
        }
        do {
            let decoded = try AVAudioFile(forReading: file)
            let sampleRate = decoded.processingFormat.sampleRate
            let channels = Int(decoded.processingFormat.channelCount)
            guard sampleRate > 0, channels > 0, decoded.length > 0 else { throw AudiobookMP3ExportError.corruptOutput("The decoded stream has no audio frames.") }
            var frames: Int64 = 0
            while decoded.framePosition < decoded.length {
                let count = AVAudioFrameCount(min(decoded.length - decoded.framePosition, AVAudioFramePosition(pcmBlockFrames)))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: decoded.processingFormat, frameCapacity: count) else { throw AudiobookMP3ExportError.corruptOutput("Could not allocate an independent decode buffer.") }
                try decoded.read(into: buffer, frameCount: count)
                guard buffer.frameLength > 0 else { break }
                frames += Int64(buffer.frameLength)
            }
            let duration = Double(frames) / sampleRate
            guard frames > 0, abs(duration - expectedDuration) <= max(0.35, expectedDuration * 0.01) else {
                throw AudiobookMP3ExportError.corruptOutput("Decoded duration \(duration)s differs from source duration \(expectedDuration)s.")
            }
            guard sampleRate == settings.sampleRate, channels == Int(settings.channelCount) else {
                throw AudiobookMP3ExportError.corruptOutput("Decoded format is \(sampleRate) Hz / \(channels) channels, expected \(settings.sampleRate) Hz / \(settings.channelCount).")
            }
            return (duration, sampleRate, channels, frames, true, tags.title, tags.author)
        } catch let error as AudiobookMP3ExportError { throw error }
        catch { throw AudiobookMP3ExportError.corruptOutput(error.localizedDescription) }
    }

    private static func readID3v23Metadata(_ file: URL) throws -> (title: String, author: String) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 10) ?? Data()
        guard header.count == 10, header.prefix(3) == Data([0x49, 0x44, 0x33]), header[3] == 3 else {
            throw AudiobookMP3ExportError.corruptOutput("A valid ID3v2.3 metadata header is missing.")
        }
        let bodySize = (Int(header[6] & 0x7F) << 21) | (Int(header[7] & 0x7F) << 14) | (Int(header[8] & 0x7F) << 7) | Int(header[9] & 0x7F)
        guard bodySize <= 1_048_576 else { throw AudiobookMP3ExportError.corruptOutput("The ID3v2 tag is unexpectedly large.") }
        let body = try handle.read(upToCount: bodySize) ?? Data()
        guard body.count == bodySize else { throw AudiobookMP3ExportError.corruptOutput("The ID3v2 metadata tag is truncated.") }
        var title = ""
        var author = ""
        var offset = 0
        while offset + 10 <= body.count {
            let frameIDData = body[offset..<(offset + 4)]
            guard let frameID = String(data: frameIDData, encoding: .ascii), frameID.utf8.count == 4 else { break }
            if frameID == "\0\0\0\0" { break }
            let size = (Int(body[offset + 4]) << 24) | (Int(body[offset + 5]) << 16) | (Int(body[offset + 6]) << 8) | Int(body[offset + 7])
            let payloadStart = offset + 10
            let payloadEnd = payloadStart + size
            guard size > 0, payloadEnd <= body.count else { throw AudiobookMP3ExportError.corruptOutput("An ID3v2 text frame is malformed.") }
            let payload = body[payloadStart..<payloadEnd]
            let value = decodeID3Text(payload)
            if frameID == "TIT2" { title = value }
            if frameID == "TPE1" { author = value }
            offset = payloadEnd
        }
        return (title, author)
    }

    private static func decodeID3Text(_ payload: Data.SubSequence) -> String {
        guard let encoding = payload.first else { return "" }
        let text = Data(payload.dropFirst())
        return switch encoding {
        case 0: String(data: text, encoding: .isoLatin1) ?? ""
        case 1: String(data: text, encoding: .utf16) ?? ""
        case 2: String(data: text, encoding: .utf16BigEndian) ?? ""
        case 3: String(data: text, encoding: .utf8) ?? ""
        default: ""
        }
    }

    private static func atomicReplace(_ source: URL, _ destination: URL) throws {
        let status = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in rename(sourcePath, destinationPath) }
        }
        guard status == 0 else { throw AudiobookMP3ExportError.replaceDestination(String(cString: strerror(errno))) }
    }
}
