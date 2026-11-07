@preconcurrency import AVFoundation
import AppKit
import CoreText
import CoreVideo

struct AudiobookVideoMetadata: @unchecked Sendable {
    var title: String
    var author: String
    var chapterTitle: String?
    var backgroundColor: NSColor = .black
    var portrait: Bool = false
    var coverImage: NSImage?
}

enum AudiobookVideoExportError: LocalizedError {
    case noSources
    case missingAudio(URL)
    case cannotCreateTrack
    case unsupportedMP4
    case export(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .noSources: "Render audio before creating a YouTube video."
        case .missingAudio(let url): "No audio track was found in \(url.lastPathComponent)."
        case .cannotCreateTrack: "The video composition could not create its media tracks."
        case .unsupportedMP4: "This Mac does not provide an H.264/AAC MP4 export preset."
        case .export(let message): "Video export failed: \(message)"
        case .invalidOutput(let message): "The exported MP4 could not be verified: \(message)"
        }
    }
}

enum AudiobookVideoExporter {
    static func export(sources: [URL], metadata: AudiobookVideoMetadata, to destination: URL) async throws {
        guard !sources.isEmpty else { throw AudiobookVideoExportError.noSources }
        let stagingDirectory = destination.deletingLastPathComponent().appendingPathComponent("BOLDVideo-\(UUID().uuidString)", isDirectory: true)
        let audioURL = stagingDirectory.appendingPathComponent("audio.m4a")
        let temporary = stagingDirectory.appendingPathComponent("export.mp4")
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try await AudiobookAudioExporter.exportM4A(sources: sources, title: metadata.title, author: metadata.author, to: audioURL)

        let audioAsset = AVURLAsset(url: audioURL)
        let duration = try await audioAsset.load(.duration)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        let audioDescriptions = try await audioTracks.first?.load(.formatDescriptions) ?? []
        guard duration.isNumeric, CMTimeGetSeconds(duration) > 0,
              let audioTrack = audioTracks.first,
              let audioDescription = audioDescriptions.first else {
            throw AudiobookVideoExportError.missingAudio(audioURL)
        }
        let renderSize = metadata.portrait ? CGSize(width: 1080, height: 1920) : CGSize(width: 1920, height: 1080)
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: metadata.portrait ? 4_000_000 : 6_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        videoInput.expectsMediaDataInRealTime = false
        let pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(renderSize.width),
            kCVPixelBufferHeightKey as String: Int(renderSize.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioDescription)
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else { throw AudiobookVideoExportError.unsupportedMP4 }
        writer.add(videoInput); writer.add(audioInput)
        writer.metadata = [
            metadataItem(.commonIdentifierTitle, metadata.chapterTitle.map { "\(metadata.title) — \($0)" } ?? metadata.title),
            metadataItem(.commonIdentifierArtist, metadata.author)
        ].compactMap { $0 }
        guard writer.startWriting() else { throw AudiobookVideoExportError.export(writer.error?.localizedDescription ?? "The MP4 writer could not start.") }
        writer.startSession(atSourceTime: .zero)

        let reader = try AVAssetReader(asset: audioAsset)
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        guard reader.canAdd(audioOutput) else { throw AudiobookVideoExportError.unsupportedMP4 }
        reader.add(audioOutput)
        guard reader.startReading() else { throw AudiobookVideoExportError.export(reader.error?.localizedDescription ?? "The AAC source could not be read.") }

        let audioQueue = DispatchQueue(label: "com.boldwriter.audiobook-video-audio", qos: .userInitiated)
        let audioTask = Task {
            await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, Error>, Never>) in
            audioInput.requestMediaDataWhenReady(on: audioQueue) {
                while audioInput.isReadyForMoreMediaData {
                    guard let sample = audioOutput.copyNextSampleBuffer() else {
                        let result: Result<Void, Error> = reader.status == .failed
                            ? .failure(reader.error ?? AudiobookVideoExportError.export("AAC decoding failed."))
                            : .success(())
                        audioInput.markAsFinished()
                        continuation.resume(returning: result)
                        return
                    }
                    if !audioInput.append(sample) {
                        let error = writer.error ?? AudiobookVideoExportError.export("AAC samples could not be muxed.")
                        reader.cancelReading(); audioInput.markAsFinished()
                        continuation.resume(returning: .failure(error))
                        return
                    }
                }
            }
            }
        }

        guard let frame = makePosterPixelBuffer(size: renderSize, metadata: metadata, pool: pixelAdaptor.pixelBufferPool) else {
            reader.cancelReading(); writer.cancelWriting()
            throw AudiobookVideoExportError.export("A video poster frame could not be rendered.")
        }
        let frameStep = CMTime(value: 1, timescale: 30)
        var presentationTime = CMTime.zero
        while CMTimeCompare(presentationTime, duration) < 0 {
            while !videoInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard pixelAdaptor.append(frame, withPresentationTime: presentationTime) else {
                reader.cancelReading(); writer.cancelWriting()
                throw AudiobookVideoExportError.export(writer.error?.localizedDescription ?? "The H.264 frame could not be written.")
            }
            presentationTime = CMTimeAdd(presentationTime, frameStep)
        }
        videoInput.markAsFinished()
        let audioResult = await audioTask.value
        if case .failure(let error) = audioResult { writer.cancelWriting(); throw error }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if writer.status == .completed { continuation.resume() }
                else { continuation.resume(throwing: writer.error ?? AudiobookVideoExportError.export("The MP4 container could not be finalized.")) }
            }
        }
        try await verify(temporary, expectedDuration: duration, expectedSize: renderSize)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private static func makePosterPixelBuffer(size: CGSize, metadata: AudiobookVideoMetadata, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        let width = Int(size.width), height = Int(size.height)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let pool,
              let imageContext = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = imageContext
        metadata.backgroundColor.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        let isLandscape = width > height
        let artWidth = CGFloat(width) * (isLandscape ? 0.34 : 0.70)
        let artHeight = min(CGFloat(height) * 0.62, artWidth * 1.5)
        let artRect = NSRect(x: (CGFloat(width) - artWidth) / 2, y: CGFloat(height) * 0.31, width: artWidth, height: artHeight)
        if let cover = metadata.coverImage {
            let source = cover.size
            let scale = min(artRect.width / max(source.width, 1), artRect.height / max(source.height, 1))
            let fitted = NSRect(x: artRect.midX - source.width * scale / 2, y: artRect.midY - source.height * scale / 2, width: source.width * scale, height: source.height * scale)
            cover.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            NSColor(calibratedWhite: 0.13, alpha: 1).setFill(); NSBezierPath(roundedRect: artRect, xRadius: 14, yRadius: 14).fill()
        }
        let titleY = artRect.minY - CGFloat(height) * 0.16
        draw(metadata.title, in: NSRect(x: CGFloat(width) * 0.06, y: titleY, width: CGFloat(width) * 0.88, height: CGFloat(height) * 0.09), size: CGFloat(height) * 0.052, color: .white)
        if let chapter = metadata.chapterTitle {
            draw(chapter, in: NSRect(x: CGFloat(width) * 0.08, y: titleY - CGFloat(height) * 0.075, width: CGFloat(width) * 0.84, height: CGFloat(height) * 0.055), size: CGFloat(height) * 0.03, color: NSColor(calibratedWhite: 0.87, alpha: 1))
        }
        draw(metadata.author, in: NSRect(x: CGFloat(width) * 0.08, y: CGFloat(height) * 0.14, width: CGFloat(width) * 0.84, height: CGFloat(height) * 0.05), size: CGFloat(height) * 0.028, color: NSColor(calibratedWhite: 0.84, alpha: 1))
        imageContext.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        guard let poster = bitmap.cgImage else { return nil }
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess, let pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.draw(poster, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    private static func draw(_ text: String, in rect: NSRect, size: CGFloat, color: NSColor) {
        guard !text.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private static func metadataItem(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem? {
        guard !value.isEmpty else { return nil }
        let item = AVMutableMetadataItem(); item.identifier = identifier; item.value = value as NSString; item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item.copy() as? AVMetadataItem
    }

    private static func verify(_ url: URL, expectedDuration: CMTime, expectedSize: CGSize) async throws {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else { throw AudiobookVideoExportError.invalidOutput("The container is not playable.") }
        let tracks = try await asset.load(.tracks)
        guard let video = tracks.first(where: { $0.mediaType == .video }), let audio = tracks.first(where: { $0.mediaType == .audio }) else {
            throw AudiobookVideoExportError.invalidOutput("The MP4 must contain video and audio tracks.")
        }
        let videoDescriptions = try await video.load(.formatDescriptions)
        let audioDescriptions = try await audio.load(.formatDescriptions)
        guard let videoDescription = videoDescriptions.first, let audioDescription = audioDescriptions.first,
              CMFormatDescriptionGetMediaSubType(videoDescription) == kCMVideoCodecType_H264,
              CMFormatDescriptionGetMediaSubType(audioDescription) == kAudioFormatMPEG4AAC else {
            throw AudiobookVideoExportError.invalidOutput("The MP4 codecs are not H.264 video and AAC audio.")
        }
        let actualDuration = try await asset.load(.duration)
        let videoRange = try await video.load(.timeRange)
        guard abs(CMTimeGetSeconds(actualDuration) - CMTimeGetSeconds(expectedDuration)) <= 0.12,
              abs(CMTimeGetSeconds(videoRange.duration) - CMTimeGetSeconds(expectedDuration)) <= 0.12 else {
            throw AudiobookVideoExportError.invalidOutput(String(format: "Audio/video duration mismatch (container %.3fs, video %.3fs, audio source %.3fs).", CMTimeGetSeconds(actualDuration), CMTimeGetSeconds(videoRange.duration), CMTimeGetSeconds(expectedDuration)))
        }
        let naturalSize = try await video.load(.naturalSize)
        guard abs(abs(naturalSize.width) - expectedSize.width) < 2, abs(abs(naturalSize.height) - expectedSize.height) < 2 else {
            throw AudiobookVideoExportError.invalidOutput("The video dimensions do not match the selected aspect ratio.")
        }
        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        let audioOutput = AVAssetReaderTrackOutput(track: audio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        guard reader.canAdd(videoOutput), reader.canAdd(audioOutput) else { throw AudiobookVideoExportError.invalidOutput("Media decoders could not be attached.") }
        reader.add(videoOutput); reader.add(audioOutput)
        guard reader.startReading(), videoOutput.copyNextSampleBuffer() != nil, audioOutput.copyNextSampleBuffer() != nil else {
            throw AudiobookVideoExportError.invalidOutput("Independent video and audio decoding did not produce samples.")
        }
        guard reader.status == .reading || reader.status == .completed else { throw AudiobookVideoExportError.invalidOutput(reader.error?.localizedDescription ?? "Media decoding failed.") }
    }
}
