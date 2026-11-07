import AppKit
import Foundation

enum CitationStyle: String, Codable, CaseIterable, Identifiable {
    case apa = "APA"
    case mla = "MLA"
    case chicago = "Chicago"

    var id: String { rawValue }

    var bibliographyTitle: String {
        switch self {
        case .apa: return "References"
        case .mla: return "Works Cited"
        case .chicago: return "Bibliography"
        }
    }
}

enum CitationSourceType: String, Codable, CaseIterable, Identifiable {
    case book = "Book"
    case article = "Article"
    case website = "Website"
    case report = "Report"
    case archive = "Archive / Primary Document"
    case thesis = "Thesis / Dissertation"
    case other = "Other"

    var id: String { rawValue }
}

struct CitationSource: Codable, Identifiable, Equatable {
    var id = UUID()
    var type: CitationSourceType = .book
    var author = ""
    var title = ""
    var year = ""
    var publisher = ""
    var containerTitle = ""
    var url = ""
    // Evidence provenance fields are optional so existing native packages
    // and citation records continue to decode without migration.
    var publicationDate: String? = nil
    var sourceLocation: String? = nil
    var quotation: String? = nil
    var researchNotes: String? = nil
    var localFilePath: String? = nil
    var fileBookmark: Data? = nil
    var contentFingerprint: String? = nil
    var verificationStatus: EvidenceVerificationStatus? = nil
    var sourceAvailability: EvidenceSourceAvailability? = nil
    /// Prior formatter displays are retained so the review workspace can
    /// identify outdated in-text citations after metadata edits without
    /// silently rewriting manuscript text.
    var citationDisplayHistory: [CitationStyle: String]? = nil
}

enum DocumentCitations {
    static func normalized(_ sources: [CitationSource]) -> [CitationSource] {
        sources.map { source in
            var result = source
            result.author = clean(source.author)
            result.title = clean(source.title)
            result.year = clean(source.year)
            result.publisher = clean(source.publisher)
            result.containerTitle = clean(source.containerTitle)
            result.url = clean(source.url)
            return result
        }
    }

    static func validate(_ sources: [CitationSource]) throws {
        var identities = Set<UUID>()

        for source in normalized(sources) {
            guard identities.insert(source.id).inserted else {
                throw WriterError.message(
                    "The document contains duplicate citation source identifiers."
                )
            }

            guard !source.title.isEmpty else {
                throw WriterError.message(
                    "Every citation source must have a title."
                )
            }
        }
    }

    /// Bibliographic completeness hints, not an assertion that a particular
    /// citation style is fully satisfied. Authors and publications may omit
    /// fields for legitimate source types.
    static func metadataHints(for source: CitationSource) -> [String] {
        var result: [String] = []
        if clean(source.title).isEmpty { result.append("Title is missing") }
        if clean(source.author).isEmpty { result.append("Author or responsible body is missing") }
        switch source.type {
        case .book:
            if clean(source.year).isEmpty { result.append("Publication year is missing") }
            if clean(source.publisher).isEmpty { result.append("Publisher is missing") }
        case .article:
            if clean(source.containerTitle).isEmpty { result.append("Journal or container title is missing") }
            if clean(source.year).isEmpty { result.append("Publication year is missing") }
        case .website:
            if clean(source.url).isEmpty { result.append("URL is missing") }
            if clean(source.year).isEmpty { result.append("Publication or access date is missing") }
        case .report, .archive, .thesis, .other:
            if clean(source.year).isEmpty && clean(source.publicationDate ?? "").isEmpty { result.append("Date is missing") }
        }
        return result
    }

    /// Resolves plain-text inline citation displays only when the display maps
    /// to exactly one source identity. Ambiguous author/year collisions remain
    /// unresolved and are never guessed.
    static func citedSourceResolution(in manuscript: String, sources: [CitationSource], style: CitationStyle) -> CitationDisplayResolution {
        var candidates: [String: [CitationSource]] = [:]
        for source in sources {
            let display = CitationFormatter.citation(for: source, style: style)
            if !display.isEmpty, manuscript.range(of: display) != nil { candidates[display, default: []].append(source) }
            if let previous = source.citationDisplayHistory?[style], previous != display,
               manuscript.range(of: previous) != nil { candidates[previous, default: []].append(source) }
        }
        var cited = Set<UUID>()
        var outdated = Set<UUID>()
        var ambiguous: [String] = []
        for (display, matches) in candidates {
            if matches.count == 1 {
                cited.insert(matches[0].id)
                if matches[0].citationDisplayHistory?[style] == display,
                   CitationFormatter.citation(for: matches[0], style: style) != display {
                    outdated.insert(matches[0].id)
                }
            }
            else { ambiguous.append(display) }
        }
        return CitationDisplayResolution(citedSourceIDs: cited, ambiguousDisplays: ambiguous.sorted(), outdatedCitationSourceIDs: outdated)
    }

    static func canonicalBibliographyKey(for source: CitationSource) -> String {
        if let local = EvidenceVerification.resolvedLocalURL(for: source) {
            return "file:\(local.standardizedFileURL.path)"
        }
        if let url = URL(string: source.url), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return "url:\(url.standardized.absoluteString)"
        }
        return "record:\(source.id.uuidString)"
    }

    static func outdatedCitationReplacements(in manuscript: String, sources: [CitationSource], style: CitationStyle, within scope: NSRange? = nil) -> [(range: NSRange, sourceID: UUID, replacement: String)] {
        let text = manuscript as NSString
        let searchRange = scope ?? NSRange(location: 0, length: text.length)
        guard searchRange.location >= 0, searchRange.length >= 0, NSMaxRange(searchRange) <= text.length else { return [] }
        var results: [(NSRange, UUID, String)] = []
        for source in sources {
            guard let old = source.citationDisplayHistory?[style], old != CitationFormatter.citation(for: source, style: style), !old.isEmpty else { continue }
            let matchingSources = sources.filter { candidate in
                candidate.citationDisplayHistory?[style] == old || CitationFormatter.citation(for: candidate, style: style) == old
            }
            guard matchingSources.count == 1, matchingSources[0].id == source.id else { continue }
            var cursor = searchRange.location
            while cursor < NSMaxRange(searchRange) {
                let remaining = NSRange(location: cursor, length: NSMaxRange(searchRange) - cursor)
                let match = text.range(of: old, options: [], range: remaining)
                guard match.location != NSNotFound else { break }
                results.append((match, source.id, CitationFormatter.citation(for: source, style: style)))
                cursor = NSMaxRange(match)
            }
        }
        return results.sorted { $0.0.location > $1.0.location }
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CitationDisplayResolution: Equatable {
    var citedSourceIDs: Set<UUID>
    var ambiguousDisplays: [String]
    var outdatedCitationSourceIDs: Set<UUID> = []
}

enum CitationFormatter {
    static func citation(
        for source: CitationSource,
        style: CitationStyle
    ) -> String {
        let author = shortAuthor(source.author)
        let rawTitle = clean(source.title)
        let name = author.isEmpty
            ? (rawTitle.isEmpty ? "Untitled" : rawTitle)
            : author
        let year = clean(source.year)

        switch style {
        case .apa:
            return year.isEmpty
                ? "(\(name))"
                : "(\(name), \(year))"
        case .mla:
            return "(\(name))"
        case .chicago:
            return year.isEmpty
                ? "(\(name))"
                : "(\(name) \(year))"
        }
    }

    static func bibliography(
        sources: [CitationSource],
        style: CitationStyle
    ) -> String {
        let sorted = DocumentCitations
            .normalized(sources)
            .reduce(into: [CitationSource]()) { unique, source in
                if !unique.contains(where: { DocumentCitations.canonicalBibliographyKey(for: $0) == DocumentCitations.canonicalBibliographyKey(for: source) }) { unique.append(source) }
            }
            .sorted { lhs, rhs in
                let left = sortKey(lhs)
                let right = sortKey(rhs)
                let order = left.localizedCaseInsensitiveCompare(right)

                if order == .orderedSame {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                        == .orderedAscending
                }

                return order == .orderedAscending
            }

        return (
            [style.bibliographyTitle]
            + sorted.map {
                bibliographyEntry(
                    for: $0,
                    style: style
                )
            }
        )
        .joined(separator: "\n")
    }

    static func contextualInlineInsertion(
        source: CitationSource,
        style: CitationStyle,
        documentText: String,
        range: NSRange
    ) -> String {
        contextualInlineText(
            citation(
                for: source,
                style: style
            ),
            documentText: documentText,
            range: range
        )
    }

    static func insertionRangeAfterSelection(
        in documentText: String,
        selection: NSRange
    ) -> NSRange? {
        let text = documentText as NSString
        guard selection.location != NSNotFound,
              selection.location <= text.length,
              selection.length <= text.length - selection.location else {
            return nil
        }
        return NSRange(location: NSMaxRange(selection), length: 0)
    }

    static func contextualBlockInsertion(
        _ block: String,
        documentText: String,
        range: NSRange
    ) -> String {
        let source = documentText as NSString

        guard
            range.location != NSNotFound,
            range.location <= source.length,
            range.length <= source.length - range.location
        else {
            return block
        }

        var result = block

        if range.location > 0 {
            let previous = source.substring(
                with: NSRange(
                    location: range.location - 1,
                    length: 1
                )
            )

            if previous != "\n" && previous != "\r" {
                result = "\n" + result
            }
        }

        if NSMaxRange(range) < source.length {
            let next = source.substring(
                with: NSRange(
                    location: NSMaxRange(range),
                    length: 1
                )
            )

            if next != "\n" && next != "\r" {
                result += "\n"
            }
        }

        return result
    }

    static func bibliographyEntry(
        for source: CitationSource,
        style: CitationStyle
    ) -> String {
        let author = clean(source.author)
        let title = clean(source.title)
        let year = clean(source.year)
        let publisher = clean(source.publisher)
        let container = clean(source.containerTitle)
        let url = clean(source.url)

        switch style {
        case .apa:
            var parts: [String] = []

            if !author.isEmpty { parts.append(sentence(author)) }
            if !year.isEmpty { parts.append("(\(year)).") }
            if !title.isEmpty { parts.append(sentence(title)) }
            if !container.isEmpty { parts.append(sentence(container)) }
            if !publisher.isEmpty { parts.append(sentence(publisher)) }
            if !url.isEmpty { parts.append(url) }

            return parts.joined(separator: " ")

        case .mla:
            var parts: [String] = []

            if !author.isEmpty { parts.append(sentence(author)) }
            if !title.isEmpty { parts.append("\"\(title).\"") }
            if !container.isEmpty { parts.append(sentence(container)) }
            if !publisher.isEmpty { parts.append(comma(publisher)) }
            if !year.isEmpty { parts.append(comma(year)) }
            if !url.isEmpty { parts.append(sentence(url)) }

            return parts
                .joined(separator: " ")
                .replacingOccurrences(of: ", .", with: ".")

        case .chicago:
            var parts: [String] = []

            if !author.isEmpty { parts.append(sentence(author)) }
            if !year.isEmpty { parts.append(sentence(year)) }
            if !title.isEmpty { parts.append(sentence(title)) }
            if !container.isEmpty { parts.append(sentence(container)) }
            if !publisher.isEmpty { parts.append(sentence(publisher)) }
            if !url.isEmpty { parts.append(sentence(url)) }

            return parts.joined(separator: " ")
        }
    }

    private static func contextualInlineText(
        _ text: String,
        documentText: String,
        range: NSRange
    ) -> String {
        let source = documentText as NSString

        guard
            range.location != NSNotFound,
            range.location <= source.length,
            range.length <= source.length - range.location
        else {
            return text
        }

        var result = text

        if range.location > 0 {
            let previous = source.substring(
                with: NSRange(
                    location: range.location - 1,
                    length: 1
                )
            )

            if needsLeadingSpace(after: previous) {
                result = " " + result
            }
        }

        if NSMaxRange(range) < source.length {
            let next = source.substring(
                with: NSRange(
                    location: NSMaxRange(range),
                    length: 1
                )
            )

            if needsTrailingSpace(before: next) {
                result += " "
            }
        }

        return result
    }

    private static func shortAuthor(_ raw: String) -> String {
        let trimmed = clean(raw)

        guard !trimmed.isEmpty else {
            return ""
        }

        let authors = trimmed
            .split(separator: ";")
            .map { clean(String($0)) }
            .filter { !$0.isEmpty }

        guard let first = authors.first else {
            return ""
        }

        let surname: String

        if let comma = first.firstIndex(of: ",") {
            surname = String(first[first.startIndex..<comma])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            surname = first
                .split(whereSeparator: \.isWhitespace)
                .last
                .map(String.init)
                ?? first
        }

        return authors.count > 1
            ? surname + " et al."
            : surname
    }

    private static func sortKey(_ source: CitationSource) -> String {
        let author = clean(source.author)
        return author.isEmpty ? source.title : author
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sentence(_ raw: String) -> String {
        let value = clean(raw)

        guard !value.isEmpty else {
            return ""
        }

        if value.hasSuffix(".")
            || value.hasSuffix("!")
            || value.hasSuffix("?") {
            return value
        }

        return value + "."
    }

    private static func comma(_ raw: String) -> String {
        let value = clean(raw)

        guard !value.isEmpty else {
            return ""
        }

        if value.hasSuffix(",") || value.hasSuffix(".") {
            return value
        }

        return value + ","
    }

    private static func needsLeadingSpace(after value: String) -> Bool {
        guard let scalar = value.unicodeScalars.first else {
            return false
        }

        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return false
        }

        return !"([{\"'“‘—–/".unicodeScalars.contains(scalar)
    }

    private static func needsTrailingSpace(before value: String) -> Bool {
        guard let scalar = value.unicodeScalars.first else {
            return false
        }

        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return false
        }

        return !".,;:!?)]}\"'”’—–/".unicodeScalars.contains(scalar)
    }
}
