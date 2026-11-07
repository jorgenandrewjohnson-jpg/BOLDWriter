import AppKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let boldWriterDocument = UTType(exportedAs: "com.boldwriter.document", conformingTo: .package)
    static let docx = UTType(filenameExtension: "docx")!
    static let epub = UTType(filenameExtension: "epub")!
    static let boldWriterMarkdown =
        UTType(filenameExtension: "md")
        ?? UTType(
            importedAs:
                "net.daringfireball.markdown",
            conformingTo:
                .plainText
        )
}

enum WriterStyle: String, CaseIterable, Codable, Identifiable {
    case normal = "Normal"
    case noSpacing = "No Spacing"
    case title = "Title"
    case subtitle = "Subtitle"
    case heading1 = "Heading 1"
    case heading2 = "Heading 2"
    case heading3 = "Heading 3"
    case heading4 = "Heading 4"
    case heading5 = "Heading 5"
    case heading6 = "Heading 6"
    case quote = "Quote"
    case intenseQuote = "Intense Quote"
    case blockQuote = "Block Quote"
    case caption = "Caption"

    var id: String { rawValue }
    var wordStyleID: String { rawValue.replacingOccurrences(of: " ", with: "") }
    var headingLevel: Int? {
        switch self {
        case .heading1: 1
        case .heading2: 2
        case .heading3: 3
        case .heading4: 4
        case .heading5: 5
        case .heading6: 6
        default: nil
        }
    }

    var font: NSFont {
        switch self {
        case .title: .systemFont(ofSize: 30, weight: .bold)
        case .subtitle: .systemFont(ofSize: 18, weight: .regular)
        case .heading1: .systemFont(ofSize: 24, weight: .bold)
        case .heading2: .systemFont(ofSize: 20, weight: .semibold)
        case .heading3: .systemFont(ofSize: 17, weight: .semibold)
        case .heading4: .systemFont(ofSize: 15, weight: .bold)
        case .heading5: .systemFont(ofSize: 14, weight: .bold)
        case .heading6: .systemFont(ofSize: 13, weight: .bold)
        case .quote: .systemFont(ofSize: 15).withItalicTrait()
        case .intenseQuote: NSFontManager.shared.convert(.systemFont(ofSize: 15).withItalicTrait(), toHaveTrait: .boldFontMask)
        case .blockQuote: .systemFont(ofSize: 15).withItalicTrait()
        case .caption: .systemFont(ofSize: 12)
        case .noSpacing: Self.defaultFont
        case .normal: Self.defaultFont
        }
    }

    static var defaultFont: NSFont {
        let stored = UserDefaults.standard.double(forKey: "defaultFontSize")
        let size = stored.isFinite && stored >= 8 && stored <= 96 ? stored : 15
        return NSFont(name: UserDefaults.standard.string(forKey: "defaultFont") ?? "Helvetica", size: size) ?? .systemFont(ofSize: size)
    }
}

extension NSFont {
    func withItalicTrait() -> NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
    }
}

struct PageSettings: Codable, Equatable {
    enum Paper: String, Codable, CaseIterable {
        case letter = "US Letter"
        case a4 = "A4"
        case custom = "Custom"
    }

    enum HorizontalPosition: String, Codable, CaseIterable, Identifiable {
        case left = "Left"
        case center = "Center"
        case right = "Right"

        var id: String { rawValue }
    }

    enum VerticalPageAlignment: String, Codable, CaseIterable {
        case top
        case center
        case bottom
        case both
    }

    enum PageNumberFormat: String, CaseIterable, Identifiable {
        case decimal
        case upperRoman
        case lowerRoman
        case upperLetter
        case lowerLetter

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .decimal:
                return "1, 2, 3"

            case .upperRoman:
                return "I, II, III"

            case .lowerRoman:
                return "i, ii, iii"

            case .upperLetter:
                return "A, B, C"

            case .lowerLetter:
                return "a, b, c"
            }
        }
    }

    var paper: Paper = .letter
    // Portrait dimensions in points; optional for legacy native documents.
    var customPaperSize: CGSize? = nil
    var landscape = false
    var topMargin: Double = 72
    var bottomMargin: Double = 72
    var leftMargin: Double = 72
    var rightMargin: Double = 72

    // Native Word binding gutter and mirrored facing-page margins.
    // Optional storage preserves decoding compatibility with older
    // BOLD documents that predate these page-layout settings.
    var gutter: Double? = nil
    var mirrorMargins: Bool? = nil
    var gutterAtTop: Bool? = nil

    // Word document compatibility setting w:compat/w:noColumnBalance.
    // Nil preserves legacy BOLD data and Word's normal default:
    // final multi-column section content may be balanced.
    var noColumnBalance: Bool? = nil

    // Native Word section body vertical alignment (w:vAlign).
    // Nil preserves legacy BOLD decoding and behaves as Word's top alignment.
    var verticalPageAlignment: VerticalPageAlignment? = nil

    var effectiveVerticalPageAlignment: VerticalPageAlignment {
        verticalPageAlignment ?? .top
    }

    var effectiveGutter: Double {
        gutter ?? 0
    }

    var usesMirrorMargins: Bool {
        mirrorMargins ?? false
    }

    var usesGutterAtTop: Bool {
        gutterAtTop ?? false
    }

    var disablesColumnBalancing: Bool {
        noColumnBalance ?? false
    }

    // Native Word header/footer distances from the physical page edge.
    // Optional storage preserves decoding compatibility with older
    // BOLD documents. Nil keeps the historical centered-in-margin
    // placement used before these Word-specific values were modeled.
    var headerDistance: Double? = nil
    var footerDistance: Double? = nil

    var effectiveHeaderDistance: Double {
        headerDistance
            ?? topMargin / 2
    }

    var effectiveFooterDistance: Double {
        footerDistance
            ?? bottomMargin / 2
    }

    // Native Word section-column settings.
    // Optional storage preserves legacy document decoding.
    var columnCount: Int? = nil
    var columnSpacing: Double? = nil

    var effectiveColumnCount: Int {
        min(
            12,
            max(
                1,
                columnCount
                    ?? 1
            )
        )
    }

    var effectiveColumnSpacing: Double {
        min(
            144,
            max(
                0,
                columnSpacing
                    ?? 36
            )
        )
    }

    // Legacy fields stay intact so existing documents retain their behavior.
    var showsPageNumbers = true
    var footerText = "BOLD Writer"

    // Optional additions preserve decoding compatibility with documents
    // created before header/footer positioning existed.
    var headerText: String? = nil
    var headerPosition: HorizontalPosition? = nil
    var footerPosition: HorizontalPosition? = nil
    var pageNumberPosition: HorizontalPosition? = nil

    // Native Word section page-number settings.
    // Nil start means continue numbering from the preceding page.
    // Raw format tokens are retained so unsupported Word values
    // still round-trip without data loss.
    var pageNumberStart: Int? = nil
    var pageNumberFormat: String? = nil

    var suppressFirstPageHeaderFooter: Bool? = nil

    // Optional Word-compatible odd/even page furniture. Keeping these
    // optional preserves decoding compatibility with older BOLD documents.
    var differentOddEvenHeaderFooter: Bool? = nil
    var evenPageHeaderText: String? = nil
    var evenPageFooterText: String? = nil
    var evenPageFooterPosition: HorizontalPosition? = nil
    var evenPageNumberPosition: HorizontalPosition? = nil

    func resolvingEvenFooter(_ even: Bool) -> PageSettings {
        guard even else { return self }
        var resolved = self
        resolved.footerPosition = evenPageFooterPosition ?? footerPosition
        resolved.pageNumberPosition = evenPageNumberPosition ?? pageNumberPosition
        return resolved
    }

    // Native Word first-page furniture. Optional fields preserve
    // decoding compatibility with BOLD documents created before
    // distinct first-page headers and footers were supported.
    var firstPageHeaderText: String? = nil
    var firstPageFooterText: String? = nil

    var effectiveHeaderText: String {
        headerText ?? ""
    }

    var effectiveHeaderPosition: HorizontalPosition {
        headerPosition ?? .left
    }

    var effectiveFooterPosition: HorizontalPosition {
        footerPosition ?? .left
    }

    var effectivePageNumberPosition: HorizontalPosition {
        pageNumberPosition ?? .right
    }

    var effectivePageNumberFormat: PageNumberFormat {
        PageNumberFormat(
            rawValue:
                pageNumberFormat
                ?? PageNumberFormat.decimal.rawValue
        )
        ?? .decimal
    }

    func formattedPageNumber(
        _ number: Int
    ) -> String {
        let safe =
            max(
                1,
                number
            )

        switch effectivePageNumberFormat {
        case .decimal:
            return String(
                safe
            )

        case .upperRoman:
            return romanPageNumber(
                safe
            )

        case .lowerRoman:
            return romanPageNumber(
                safe
            )
            .lowercased()

        case .upperLetter:
            return letterPageNumber(
                safe
            )

        case .lowerLetter:
            return letterPageNumber(
                safe
            )
            .lowercased()
        }
    }

    private func romanPageNumber(
        _ value: Int
    ) -> String {
        guard
            value <= 3_999
        else {
            return String(
                value
            )
        }

        let values: [(Int, String)] = [
            (1000, "M"),
            (900, "CM"),
            (500, "D"),
            (400, "CD"),
            (100, "C"),
            (90, "XC"),
            (50, "L"),
            (40, "XL"),
            (10, "X"),
            (9, "IX"),
            (5, "V"),
            (4, "IV"),
            (1, "I")
        ]

        var remaining =
            value

        var result =
            ""

        for (
            amount,
            symbol
        ) in values {

            while remaining
                >= amount {

                result +=
                    symbol

                remaining -=
                    amount
            }
        }

        return result
    }

    private func letterPageNumber(
        _ value: Int
    ) -> String {
        let alphabet =
            Array(
                "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            )

        var remaining =
            value

        var result =
            ""

        while remaining > 0 {
            remaining -= 1

            result.insert(
                alphabet[
                    remaining % 26
                ],
                at:
                    result.startIndex
            )

            remaining /=
                26
        }

        return result
    }

    var hidesHeaderFooterOnFirstPage: Bool {
        suppressFirstPageHeaderFooter ?? false
    }

    var usesDifferentOddEvenHeaderFooter: Bool {
        differentOddEvenHeaderFooter ?? false
    }

    var effectiveEvenPageHeaderText: String {
        evenPageHeaderText ?? effectiveHeaderText
    }

    var effectiveEvenPageFooterText: String {
        evenPageFooterText ?? footerText
    }

    var hasDistinctFirstPageHeaderFooter: Bool {
        firstPageHeaderText != nil
            || firstPageFooterText != nil
    }

    var effectiveFirstPageHeaderText: String {
        firstPageHeaderText ?? effectiveHeaderText
    }

    var effectiveFirstPageFooterText: String {
        firstPageFooterText ?? footerText
    }

    var usesLegacyFooterLayout: Bool {
        headerText == nil
            && headerPosition == nil
            && footerPosition == nil
            && pageNumberPosition == nil
            && headerDistance == nil
            && footerDistance == nil
            && suppressFirstPageHeaderFooter == nil
            && differentOddEvenHeaderFooter == nil
            && evenPageHeaderText == nil
            && evenPageFooterText == nil
            && firstPageHeaderText == nil
            && firstPageFooterText == nil
    }

    var pageSize: CGSize {
        let base: CGSize
        switch paper {
        case .letter: base = CGSize(width: 612, height: 792)
        case .a4: base = CGSize(width: 595.28, height: 841.89)
        case .custom: base = customPaperSize ?? CGSize(width: 612, height: 792)
        }

        return landscape
            ? CGSize(width: base.height, height: base.width)
            : base
    }
}

/// A section begins at a UTF-16 text offset and carries the page
/// configuration that applies from that point forward. The first section
/// normally begins at location zero. Keeping sections in metadata rather
/// than attributed text lets BOLD preserve native Word section structure
/// without disturbing ordinary editing or legacy documents.
struct DocumentSection: Codable, Equatable {
    enum BreakType: String, Codable, CaseIterable {
        case nextPage
        case continuous
        case nextColumn
        case evenPage
        case oddPage
    }

    var location: Int
    var page: PageSettings
    var breakType: BreakType? = nil

    var effectiveBreakType: BreakType {
        breakType ?? .nextPage
    }

    init(
        location: Int,
        page: PageSettings,
        breakType: BreakType? = nil
    ) {
        self.location = location
        self.page = page
        self.breakType = breakType
    }

    static func normalized(
        _ sections: [DocumentSection],
        textLength: Int,
        fallbackPage: PageSettings
    ) -> [DocumentSection] {
        let safeLength =
            max(
                0,
                textLength
            )

        let sorted =
            sections
                .map {
                    DocumentSection(
                        location:
                            min(
                                max(
                                    0,
                                    $0.location
                                ),
                                safeLength
                            ),
                        page:
                            $0.page,
                        breakType:
                            $0.breakType
                    )
                }
                .sorted {
                    $0.location
                        < $1.location
                }

        var result:
            [DocumentSection] = []

        for section in sorted {
            if let last =
                result.last,
               last.location
                == section.location {

                result[
                    result.count - 1
                ] =
                    section
            } else {
                result.append(
                    section
                )
            }
        }

        if result.isEmpty {
            return [
                DocumentSection(
                    location:
                        0,
                    page:
                        fallbackPage
                )
            ]
        }

        if result[0].location != 0 {
            result.insert(
                DocumentSection(
                    location:
                        0,
                    page:
                        fallbackPage
                ),
                at:
                    0
            )
        }

        return result
    }

    /// Returns normalized document sections paired with the UTF-16 text
    /// range governed by each section. A section begins at its stored
    /// location and continues up to, but not including, the next section.
    /// The final section continues through the end of the document.
    static func textRanges(
        _ sections: [DocumentSection],
        textLength: Int,
        fallbackPage: PageSettings
    ) -> [(section: DocumentSection, range: NSRange)] {
        let safeLength =
            max(
                0,
                textLength
            )

        let normalizedSections =
            normalized(
                sections,
                textLength:
                    safeLength,
                fallbackPage:
                    fallbackPage
            )

        return normalizedSections
            .enumerated()
            .map {
                index,
                section
                -> (
                    section: DocumentSection,
                    range: NSRange
                ) in

                let end =
                    index + 1
                        < normalizedSections.count
                    ? normalizedSections[index + 1]
                        .location
                    : safeLength

                return (
                    section:
                        section,
                    range:
                        NSRange(
                            location:
                                section.location,
                            length:
                                max(
                                    0,
                                    end
                                        - section.location
                                )
                        )
                )
            }
    }
}

struct StyleRun: Codable, Equatable {
    var location: Int
    var length: Int
    var style: WriterStyle
}

struct DocumentComment: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var author: String = NSFullUserName()
    var location: Int
    var length: Int
    var createdAt = Date()
}

struct DocumentBookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var location: Int
    var length: Int = 0

    init(id: UUID = UUID(), name: String, location: Int, length: Int = 0) {
        self.id = id; self.name = name; self.location = location; self.length = length
    }

    private enum CodingKeys: String, CodingKey { case id, name, location, length }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        location = try container.decode(Int.self, forKey: .location)
        length = try container.decodeIfPresent(Int.self, forKey: .length) ?? 0
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id); try container.encode(name, forKey: .name)
        try container.encode(location, forKey: .location); try container.encode(length, forKey: .length)
    }
}

enum DocumentBookmarks {
    static func normalizedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")
        var value = trimmed.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        if value.first?.isLetter != true { value = "BOLD_" + value }
        return String(value.prefix(40))
    }
    static func normalized(_ bookmarks: [DocumentBookmark]) -> [DocumentBookmark] {
        var names = Set<String>()
        return bookmarks.map { source in
            var bookmark = source
            let base = normalizedName(source.name)
            let stem = base.isEmpty ? "Bookmark" : base
            var name = stem, suffix = 2
            while !names.insert(name.lowercased()).inserted {
                let tail = "_\(suffix)"; suffix += 1
                name = String(stem.prefix(40 - tail.count)) + tail
            }
            bookmark.name = name
            return bookmark
        }
    }
    static func validate(_ bookmarks: [DocumentBookmark], textLength: Int) throws {
        var ids = Set<UUID>(), names = Set<String>()
        for bookmark in bookmarks {
            let name = bookmark.name
            guard ids.insert(bookmark.id).inserted, !name.isEmpty, name == normalizedName(name),
                  names.insert(name.lowercased()).inserted, bookmark.location >= 0, bookmark.length >= 0,
                  bookmark.location <= textLength, bookmark.length <= textLength - bookmark.location else {
                throw WriterError.message("The document contains invalid or duplicate bookmarks.")
            }
        }
    }
}

struct NativeFieldRun: Codable, Equatable {
    var id: UUID
    var kind: WordField.Kind
    var instruction: String
    var dirtyValue: String?
    var lockedValue: String?
    var location: Int
    var length: Int
}

struct RevisionRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case manual, aiSafety, autosave }
    var id = UUID()
    var date = Date()
    var name: String
    var kind: Kind
    var rtfData: Data
    var rtfdData: Data? = nil
    var documentMetadata: RevisionContentMetadata? = nil
}

struct RevisionContentMetadata: Codable, Equatable {
    var title: String
    var page: PageSettings
    var sections: [DocumentSection]? = nil
    var styles: [StyleRun]
    var comments: [DocumentComment]
    var bookmarks: [DocumentBookmark]
    var notes: String
    var footnotes: [Footnote]? = nil
    var endnotes: [Endnote]? = nil
    var tables: [TableCellRecord]? = nil
    var trackedChanges: [TrackChangeRecord]? = nil
    var fields: [NativeFieldRun]? = nil
    var citationSources: [CitationSource]? = nil
    var citationStyle: CitationStyle? = nil
    var claimEvidence: [ClaimEvidence]? = nil
}

enum WriterError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

struct NativePictureCropRun:
    Codable,
    Equatable
{
    var location: Int
    var length: Int
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int
}

struct NativePictureAltTextRun: Codable, Equatable {
    var location: Int
    var length: Int
    var title: String
    var alternativeDescription: String
}

struct NativeVMLShapeRun:
    Codable,
    Equatable
{
    let shapeKind: String
    let shapeID: String?
    let style: String?
    let fillColor: String?
    let strokeColor: String?
    let strokeWeight: String?
    let textBoxInset: String?
    let location: Int
    let length: Int
}

struct NativeOpaqueDrawingRun: Codable, Equatable {
    let location: Int
    let length: Int
    let xml: String
    let isRunChild: Bool
    let id: UUID?
    let relationships: [WordOpaqueRelationship]?
    let parts: [WordOpaquePart]?
}


struct ChecklistRun: Codable, Equatable {
    var location: Int
    var length: Int
    var checked: Bool
}

struct DocumentMetadata: Codable, Equatable {
    var checklistRuns: [ChecklistRun]? = nil
    var formatVersion = 1
    var title = "Untitled"
    var page = PageSettings()

    // Optional so metadata written before section support continues to
    // decode unchanged. A nil/empty value means the global `page`
    // configuration applies to the entire manuscript.
    var sections: [DocumentSection]? = nil

    var styleRuns: [StyleRun] = []
    var manuscriptFormatting: NativeManuscriptFormatting? = nil
    // Optional to keep older native documents readable.
    var namedStyles: [NamedStyleDefinition]? = nil
    var namedStyleRuns: [NamedStyleRun]? = nil
    var fields: [NativeFieldRun]? = nil
    var pictureCrops: [NativePictureCropRun]? = nil
    var pictureAltText: [NativePictureAltTextRun]? = nil
    var vmlShapes: [NativeVMLShapeRun]? = nil
    /// Optional for native packages saved before opaque Word drawing support.
    var opaqueDrawings: [NativeOpaqueDrawingRun]? = nil
    /// Independent artwork records are absent in legacy packages and therefore
    /// do not change their decoding or inline attachment behavior.
    var floatingImages: [FloatingImage]? = nil
    var comments: [DocumentComment] = []
    var bookmarks: [DocumentBookmark] = []
    var footnotes: [Footnote]? = nil
    var endnotes: [Endnote]? = nil
    var tables: [TableCellRecord]? = nil
    var notes = ""
    var revisions: [RevisionRecord] = []

    // Optional for backward compatibility with manuscripts
    // created before Track Changes existed.
    var trackChangesEnabled: Bool? = nil
    var trackedChanges: [TrackChangeRecord]? = nil

    // Optional citation metadata keeps older native files readable.
    var citationSources: [CitationSource]? = nil
    var citationStyle: CitationStyle? = nil
    // Optional so native documents saved before claim-level evidence remain readable.
    var claimEvidence: [ClaimEvidence]? = nil

    // Optional publishing configuration keeps older native files readable.
    var publishingTOCs: [PublishingTOCSettings]? = nil
    var coverProjects: [CoverProject]? = nil
    /// Stable workspace selection restored by Cover Editor; absent in older packages.
    var activeCoverProjectID: UUID? = nil
    /// Visualization choices only; absent in documents saved before 3D Book Studio.
    var bookStudioPresentation: BookStudioPresentation? = nil
    /// Per-project local manuscript quality rules. Optional for legacy files.
    var manuscriptConsistencyRules: [BOLDConsistencyRule]? = nil
    var manuscriptLiveAuditEnabled: Bool? = nil
    /// Stable finding IDs dismissed by the author in this document.
    var ignoredManuscriptFindings: [String]? = nil
    /// Knowledge Library document IDs selected for this project's cross-document audits.
    var manuscriptAuditLibraryDocumentIDs: [UUID]? = nil

    var createdAt = Date()
    var modifiedAt = Date()
}


extension DocumentMetadata {
    mutating func rebaseTextAnchors(
        from oldText: String,
        to newText: String
    ) {

        if var images = floatingImages, oldText != newText {
            let old = oldText as NSString
            let new = newText as NSString
            let limit = min(old.length, new.length)
            var prefix = 0
            while prefix < limit && old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
            var suffix = 0
            while suffix < old.length - prefix && suffix < new.length - prefix
                && old.character(at: old.length - suffix - 1) == new.character(at: new.length - suffix - 1) { suffix += 1 }
            let oldEnd = old.length - suffix
            let delta = new.length - old.length
            for index in images.indices where images[index].anchor == .paragraph || images[index].anchor == .character {
                let location = images[index].anchorLocation
                if location >= prefix && location < oldEnd {
                    // Deterministic deletion/replacement fallback: retain the
                    // physical position as a page anchor if the target vanished.
                    images[index].anchor = .page
                    images[index].anchorLocation = -1
                } else if location >= oldEnd {
                    images[index].anchorLocation = max(0, location + delta)
                }
            }
            floatingImages = images
        }

        // SECTION-ANCHOR-REBASING
        //
        // Word section boundaries live as UTF-16 text anchors.
        // Keep them synchronized with ordinary BOLD Writer edits
        // using the same single-replacement interpretation used
        // for the document's other text-bound metadata.
        if let currentSections =
            sections {

            let sectionOldText =
                oldText
                    as NSString

            let sectionNewText =
                newText
                    as NSString

            let sectionOldLength =
                sectionOldText.length

            let sectionNewLength =
                sectionNewText.length

            let sectionSharedLimit =
                min(
                    sectionOldLength,
                    sectionNewLength
                )

            var sectionPrefix =
                0

            while sectionPrefix
                < sectionSharedLimit,
                  sectionOldText.character(
                    at:
                        sectionPrefix
                  )
                    == sectionNewText.character(
                        at:
                            sectionPrefix
                    ) {

                sectionPrefix +=
                    1
            }

            var sectionSuffix =
                0

            while sectionSuffix
                < sectionOldLength
                    - sectionPrefix,
                  sectionSuffix
                    < sectionNewLength
                        - sectionPrefix,
                  sectionOldText.character(
                    at:
                        sectionOldLength
                        - sectionSuffix
                        - 1
                  )
                    == sectionNewText.character(
                        at:
                            sectionNewLength
                            - sectionSuffix
                            - 1
                    ) {

                sectionSuffix +=
                    1
            }

            let sectionOldChangedEnd =
                sectionOldLength
                - sectionSuffix

            let sectionNewChangedEnd =
                sectionNewLength
                - sectionSuffix

            let sectionDelta =
                sectionNewLength
                - sectionOldLength

            let rebasedSections =
                currentSections.map {
                    section
                    -> DocumentSection in

                    let oldLocation =
                        min(
                            max(
                                0,
                                section.location
                            ),
                            sectionOldLength
                        )

                    let newLocation:
                        Int

                    if oldLocation
                        <= sectionPrefix {

                        // An insertion exactly at a section boundary
                        // belongs to that following section, so the
                        // boundary itself stays in place.
                        newLocation =
                            oldLocation

                    } else if oldLocation
                        >= sectionOldChangedEnd {

                        newLocation =
                            oldLocation
                            + sectionDelta

                    } else {

                        // A boundary consumed by replacement/deletion
                        // survives at the end of the replacement.
                        newLocation =
                            sectionNewChangedEnd
                    }

                    return DocumentSection(
                        location:
                            newLocation,
                        page:
                            section.page
                    )
                }

            sections =
                DocumentSection.normalized(
                    rebasedSections,
                    textLength:
                        sectionNewLength,
                    fallbackPage:
                        page
                )
        }

        guard
            !comments.isEmpty
                || !bookmarks.isEmpty
        else {
            return
        }

        let old =
            oldText as NSString

        let new =
            newText as NSString

        let sharedLength =
            min(
                old.length,
                new.length
            )

        var prefix = 0

        while prefix < sharedLength,
              old.character(
                at:
                    prefix
              )
                == new.character(
                    at:
                        prefix
                ) {
            prefix += 1
        }

        if prefix == old.length,
           prefix == new.length {
            return
        }

        var oldEnd =
            old.length

        var newEnd =
            new.length

        while oldEnd > prefix,
              newEnd > prefix,
              old.character(
                at:
                    oldEnd - 1
              )
                == new.character(
                    at:
                        newEnd - 1
                ) {
            oldEnd -= 1
            newEnd -= 1
        }

        // Normalize stale or malformed metadata before applying
        // the edit script so an old file cannot create an
        // out-of-bounds navigation target.
        for index in bookmarks.indices {
            bookmarks[index].location =
                min(
                    max(
                        0,
                        bookmarks[index]
                            .location
                    ),
                    old.length
                )
        }

        for index in comments.indices {
            let start =
                min(
                    max(
                        0,
                        comments[index]
                            .location
                    ),
                    old.length
                )

            let available =
                old.length - start

            let length =
                min(
                    max(
                        0,
                        comments[index]
                            .length
                    ),
                    available
                )

            comments[index].location =
                start

            comments[index].length =
                length
        }

        let oldMiddle =
            old.substring(
                with:
                    NSRange(
                        location:
                            prefix,
                        length:
                            oldEnd - prefix
                    )
            )

        let newMiddle =
            new.substring(
                with:
                    NSRange(
                        location:
                            prefix,
                        length:
                            newEnd - prefix
                    )
            )

        let difference =
            Array(
                newMiddle.utf16
            )
            .difference(
                from:
                    Array(
                        oldMiddle.utf16
                    )
            )

        let removals =
            difference
                .compactMap {
                    change -> Int? in

                    guard
                        case let .remove(
                            offset,
                            _,
                            _
                        ) = change
                    else {
                        return nil
                    }

                    return offset
                }
                .sorted(
                    by: >
                )

        let insertions =
            difference
                .compactMap {
                    change -> Int? in

                    guard
                        case let .insert(
                            offset,
                            _,
                            _
                        ) = change
                    else {
                        return nil
                    }

                    return offset
                }
                .sorted()

        // CollectionDifference is applied by removing from the
        // end toward the beginning, then inserting from the
        // beginning toward the end. Rebase our anchors in the
        // same order.
        for localOffset in removals {
            let position =
                prefix
                + localOffset

            for index in bookmarks.indices {
                if bookmarks[index].length == 0 {
                    if bookmarks[index].location > position { bookmarks[index].location -= 1 }
                } else {
                    var start = bookmarks[index].location
                    var end = start + bookmarks[index].length
                    if start > position { start -= 1 }
                    if end > position { end -= 1 }
                    bookmarks[index].location = start
                    bookmarks[index].length = max(0, end - start)
                }
            }

            for index in comments.indices {
                var start =
                    comments[index]
                        .location

                var end =
                    start
                    + comments[index]
                        .length

                if start > position {
                    start -= 1
                }

                if end > position {
                    end -= 1
                }

                comments[index]
                    .location =
                    start

                comments[index]
                    .length =
                    max(
                        0,
                        end - start
                    )
            }
        }

        for localOffset in insertions {
            let position =
                prefix
                + localOffset

            // A point bookmark has right affinity: text inserted
            // at the bookmark pushes the bookmark forward so it
            // stays with the original following content.
            for index in bookmarks.indices {
                if bookmarks[index].length == 0 {
                    if bookmarks[index].location >= position { bookmarks[index].location += 1 }
                } else {
                    var start = bookmarks[index].location
                    var end = start + bookmarks[index].length
                    if start > position { start += 1 }
                    if end >= position { end += 1 }
                    bookmarks[index].location = start
                    bookmarks[index].length = max(0, end - start)
                }
            }

            // Comment boundaries are inclusive. Insertions at
            // either edge become part of the annotated span,
            // and replacement text remains commented.
            for index in comments.indices {
                var start =
                    comments[index]
                        .location

                var end =
                    start
                    + comments[index]
                        .length

                if start > position {
                    start += 1
                }

                if end >= position {
                    end += 1
                }

                comments[index]
                    .location =
                    start

                comments[index]
                    .length =
                    max(
                        0,
                        end - start
                    )
            }
        }

        for index in bookmarks.indices {
            bookmarks[index].location =
                min(
                    max(
                        0,
                        bookmarks[index]
                            .location
                    ),
                    new.length
                )
        }

        for index in comments.indices {
            let start =
                min(
                    max(
                        0,
                        comments[index]
                            .location
                    ),
                    new.length
                )

            let available =
                new.length - start

            let length =
                min(
                    max(
                        0,
                        comments[index]
                            .length
                    ),
                    available
                )

            comments[index].location =
                start

            comments[index].length =
                length
        }
    }
}

struct OutlineItem: Identifiable, Equatable {
    var id: String { "\(range.location)-\(level)-\(title)" }
    var title: String
    var level: Int
    var range: NSRange
}

struct SearchResult: Identifiable, Equatable {
    var id: String { "\(range.location)-\(range.length)" }
    var range: NSRange
    var context: String
}

struct DocumentStatistics: Equatable {
    var words = 0
    var characters = 0
    var charactersWithoutSpaces = 0
    var paragraphs = 0
    var estimatedMinutes = 0
    var headings = 0
}
