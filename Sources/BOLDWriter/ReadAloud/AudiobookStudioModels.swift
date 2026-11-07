import AppKit
import AVFoundation
import CryptoKit
import Foundation

struct PronunciationRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var writtenTerm: String
    var spokenForm: String
    var locale = ""
    var scope: Scope = .project
    var matching: Matching = .wholeWord
    var caseSensitive = false

    enum Scope: String, Codable, CaseIterable { case global = "All books", project = "This book" }
    enum Matching: String, Codable, CaseIterable { case wholeWord = "Whole word", exactTerm = "Exact term" }
}

struct AudiobookChapter: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var text: String
    var fingerprint: String
    var voiceIdentifier: String?
    var narratorProviderIdentifier: String?
    var narratorModelIdentifier: String?
    var sourceLocation: Int?
    var passageNarratorAssignments: [AudiobookPassageNarratorAssignment]?
    /// Nil decodes older project files as included; explicit false excludes a chapter from production and exports.
    var included: Bool? = true
    var state: State
    var audioFiles: [URL]?
    var audioSegments: [AudiobookAudioSegment]?
    enum State: String, Codable { case queued, rendering, complete, failed, stale }

    init(id: String, title: String, text: String, voiceIdentifier: String? = nil, state: State = .queued) {
        self.id = id
        self.title = title
        self.text = text
        self.fingerprint = Self.digest(text + "\nvoice:\(voiceIdentifier ?? "system-default")")
        self.voiceIdentifier = voiceIdentifier
        self.state = state
        self.sourceLocation = nil
        self.passageNarratorAssignments = []
        self.audioFiles = nil
        self.audioSegments = nil
    }

    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct AudiobookPassageNarratorAssignment: Codable, Equatable, Identifiable {
    var id: String
    /// UTF-16 offsets relative to the chapter narration text.
    var location: Int
    var length: Int
    var textFingerprint: String
    var providerIdentifier: String
    var voiceIdentifier: String
    var modelIdentifier: String?

    var range: NSRange { NSRange(location: location, length: length) }
}

struct AudiobookNarrationRange: Equatable {
    var range: NSRange
    var passageAssignment: AudiobookPassageNarratorAssignment?
}

enum AudiobookSharePolicy {
    static let attachmentCautionThresholdBytes: Int64 = 25 * 1_024 * 1_024
    static func shouldWarn(fileSizeBytes: Int64) -> Bool { fileSizeBytes >= attachmentCautionThresholdBytes }
}

extension AudiobookChapter {
    func narrationRanges() -> [AudiobookNarrationRange] {
        let source = text as NSString
        guard source.length > 0 else { return [] }
        let valid = (passageNarratorAssignments ?? []).filter { assignment in
            assignment.location >= 0 && assignment.length > 0 && NSMaxRange(assignment.range) <= source.length &&
            Self.digest(source.substring(with: assignment.range)) == assignment.textFingerprint
        }.sorted { $0.location < $1.location }
        let boundaries = Array(Set([0, source.length] + valid.flatMap { [$0.location, NSMaxRange($0.range)] })).sorted()
        return zip(boundaries, boundaries.dropFirst()).compactMap { start, end in
            guard end > start else { return nil }
            let range = NSRange(location: start, length: end - start)
            guard !source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let assignment = valid.last { $0.location <= start && NSMaxRange($0.range) >= end }
            return AudiobookNarrationRange(range: range, passageAssignment: assignment)
        }
    }
}

struct AudiobookAudioSegment: Codable, Equatable, Identifiable {
    var index: Int
    var fingerprint: String
    var url: URL
    var id: Int { index }
}

struct NarrationHeading: Equatable {
    var range: NSRange
    var title: String
}

enum ChapterHeadingParser {
    static func explicitHeadings(in text: String) -> [NarrationHeading] {
        let source = text as NSString
        let pattern = #"(?im)^[\t ]*(?:chapter|part)[\t ]+(?:[0-9]+|[ivxlcdm]+|[a-z]+)(?:[\t ]*[:.\-–—][\t ]*[^\r\n]*)?[\t ]*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            NarrationHeading(range: match.range, title: source.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

struct AudiobookProjectManifest: Codable, Equatable {
    var formatVersion = 1
    var projectID = UUID()
    var sourceURL: URL?
    var sourceFingerprint: String
    var title: String
    var author: String
    var provider = "Apple"
    var voiceIdentifier = ""
    var modelIdentifier = ""
    var speed = 1.0
    var pronunciations: [PronunciationRule] = []
    var chapters: [AudiobookChapter]
    var lastExportURL: URL?
    var updatedAt = Date()

    static func chunks(_ text: String, maximumCharacters: Int = 3500) -> [String] {
        guard maximumCharacters > 0, !text.isEmpty else { return [] }
        let paragraphRanges = (text as NSString).paragraphRanges()
        var chunks: [String] = []
        var current = ""
        for range in paragraphRanges {
            let paragraph = (text as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !paragraph.isEmpty else { continue }
            if !current.isEmpty, current.utf16.count + paragraph.utf16.count + 2 > maximumCharacters { chunks.append(current); current = "" }
            let combined = current.isEmpty ? paragraph : current + "\n\n" + paragraph
            if combined.utf16.count <= maximumCharacters { current = combined; continue }
            if !current.isEmpty { chunks.append(current); current = "" }
            var piece = ""
            for word in paragraph.split(whereSeparator: \.isWhitespace).map(String.init) {
                let candidate = piece.isEmpty ? word : piece + " " + word
                if candidate.utf16.count <= maximumCharacters { piece = candidate; continue }
                if !piece.isEmpty { chunks.append(piece); piece = "" }
                if word.utf16.count <= maximumCharacters { piece = word; continue }
                var scalarPiece = ""
                for scalar in word.unicodeScalars {
                    let next = scalarPiece + String(scalar)
                    if next.utf16.count > maximumCharacters { chunks.append(scalarPiece); scalarPiece = String(scalar) }
                    else { scalarPiece = next }
                }
                piece = scalarPiece
            }
            current = piece
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

enum PronunciationProcessor {
    static func apply(_ text: String, rules: [PronunciationRule], locale: String? = nil) -> String {
        rules.filter { rule in
            rule.locale.isEmpty || locale?.localizedCaseInsensitiveCompare(rule.locale) == .orderedSame || locale?.lowercased().hasPrefix(rule.locale.lowercased() + "-") == true
        }.sorted { $0.writtenTerm.count > $1.writtenTerm.count }.reduce(text) { value, rule in
            guard !rule.writtenTerm.isEmpty else { return value }
            let compareOptions: String.CompareOptions = rule.caseSensitive ? [] : [.caseInsensitive]
            if rule.matching == .wholeWord {
                let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: rule.writtenTerm) + "(?![\\p{L}\\p{N}_])"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: rule.caseSensitive ? [] : [.caseInsensitive]) else { return value }
                return regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: NSRegularExpression.escapedTemplate(for: rule.spokenForm))
            }
            return value.replacingOccurrences(of: rule.writtenTerm, with: rule.spokenForm, options: compareOptions)
        }
    }
}

private extension NSString {
    func paragraphRanges() -> [NSRange] {
        var ranges: [NSRange] = []
        enumerateSubstrings(in: NSRange(location: 0, length: length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in ranges.append(range) }
        return ranges
    }
}

enum ElevenLabsAPIError: LocalizedError {
    case invalidResponse, http(Int, String), noModels, requestTooLarge(Int, Int)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "ElevenLabs returned an unreadable response."
        case .http(let code, let message): "ElevenLabs error \(code): \(message)"
        case .noModels: "This account returned no text to speech models."
        case .requestTooLarge(let count, let limit): "This passage has \(count) characters; the selected model allows at most \(limit)."
        }
    }
}

struct ElevenLabsModel: Decodable, Identifiable, Hashable {
    var model_id: String
    var name: String?
    var can_do_text_to_speech: Bool?
    var maximum_text_length_per_request: Int?
    var id: String { model_id }
}

struct ElevenLabsVoice: Decodable, Identifiable, Hashable {
    var voice_id: String
    var name: String
    var category: String?
    var labels: [String: String]?
    var preview_url: URL?
    var id: String { voice_id }
    var language: String { labels?["language"] ?? labels?["accent"] ?? "" }
}

struct ElevenLabsProvider {
    private let key: String
    private let session: URLSession
    init(apiKey: String, session: URLSession = .shared) { key = apiKey; self.session = session }

    func models() async throws -> [ElevenLabsModel] {
        let data = try await get("https://api.elevenlabs.io/v1/models")
        let items = try JSONDecoder().decode([ElevenLabsModel].self, from: data).filter { $0.can_do_text_to_speech == true }
        guard !items.isEmpty else { throw ElevenLabsAPIError.noModels }
        return items.sorted { ($0.name ?? $0.model_id).localizedCaseInsensitiveCompare($1.name ?? $1.model_id) == .orderedAscending }
    }

    func voices() async throws -> [ElevenLabsVoice] {
        struct Response: Decodable { var voices: [ElevenLabsVoice]; var next_page_token: String? }
        var result: [ElevenLabsVoice] = []
        var token: String?
        repeat {
            var components = URLComponents(string: "https://api.elevenlabs.io/v2/voices")!
            if let token { components.queryItems = [URLQueryItem(name: "next_page_token", value: token)] }
            let data = try await get(components.url!.absoluteString)
            let response = try JSONDecoder().decode(Response.self, from: data)
            result.append(contentsOf: response.voices)
            token = response.next_page_token
        } while token != nil
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func synthesize(text: String, voiceID: String, modelID: String, limit: Int) async throws -> Data {
        let count = text.utf16.count
        guard count <= limit else { throw ElevenLabsAPIError.requestTooLarge(count, limit) }
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)?output_format=mp3_44100_128") else { throw ElevenLabsAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "model_id": modelID])
        return try await perform(request)
    }

    private func get(_ urlString: String) async throws -> Data {
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ElevenLabsAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "The response contained no readable details."
            throw ElevenLabsAPIError.http(http.statusCode, String(body.prefix(600)))
        }
        return data
    }
}
