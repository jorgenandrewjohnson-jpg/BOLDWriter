import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import CryptoKit

private struct CoverArtworkAssetIndex: Codable {
    struct Reference: Codable {
        let projectID: UUID
        let layerID: UUID
        let slot: String
        let digest: String
    }
    let version: Int
    let references: [Reference]
}

struct WriterDocumentSnapshot {
    let text: NSAttributedString
    let metadata: DocumentMetadata
}

final class BOLDWriterDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] {
        [
            .boldWriterDocument,
            .rtf,
            .rtfd,
            .plainText,
            .html,
            .docx,
            .pdf,
            .boldWriterMarkdown,
            .image
        ]
    }
    static func inferredContentType(
        for url: URL
    ) -> UTType {
        let extensionName =
            url.pathExtension
            .lowercased()

        if extensionName == "boldwriter" {
            return .boldWriterDocument
        }

        if
            extensionName == "md"
            || extensionName == "markdown"
        {
            return .boldWriterMarkdown
        }

        if
            let contentType =
                try? url
                .resourceValues(
                    forKeys:
                        [
                            .contentTypeKey
                        ]
                )
                .contentType
        {
            return contentType
        }

        return UTType(
            filenameExtension:
                extensionName
        )
        ?? .data
    }

    static func supportsOpening(
        _ contentType: UTType
    ) -> Bool {
        readableContentTypes
            .contains {
                candidate in

                contentType
                    == candidate
                || contentType
                    .conforms(
                        to:
                            candidate
                    )
            }
    }

    static var writableContentTypes: [UTType] {
        [
            .boldWriterDocument,
            .docx
        ]
    }

    typealias Snapshot = WriterDocumentSnapshot

    @Published var text: NSAttributedString
    @Published var metadata: DocumentMetadata
    @Published private(set) var revisionID = UUID()
    @Published var lastErrorMessage: String?
    var manuscriptReplacementRevisionID: UUID?


    init() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        self.text = NSAttributedString(
            string: "",
            attributes: [.font: WriterStyle.defaultFont, .paragraphStyle: paragraph]
        )
        self.metadata = DocumentMetadata()
    }

    required convenience init(configuration: ReadConfiguration) throws {
        try self.init(fileWrapper: configuration.file, contentType: configuration.contentType)
    }

    init(fileWrapper wrapper: FileWrapper, contentType: UTType) throws {
        if contentType.conforms(
            to:
                .image
        ) {
            guard
                !wrapper.isDirectory,
                let data =
                    wrapper.regularFileContents,
                let image =
                    NSImage(
                        data:
                            data
                    )
            else {
                throw WriterError.message(
                    "BOLD Writer could not decode this image file."
                )
            }

            let embeddedWrapper =
                FileWrapper(
                    regularFileWithContents:
                        data
                )

            embeddedWrapper.preferredFilename =
                wrapper.preferredFilename
                ?? wrapper.filename
                ?? "Imported Image"

            let attachment =
                NSTextAttachment(
                    fileWrapper:
                        embeddedWrapper
                )

            attachment.attachmentCell =
                NSTextAttachmentCell(
                    imageCell:
                        image
                )

            let imported =
                NSMutableAttributedString(
                    attachment:
                        attachment
                )

            imported.append(
                NSAttributedString(
                    string:
                        "\n"
                )
            )

            text =
                imported

            metadata =
                DocumentMetadata(
                    title:
                        wrapper.filename
                        ?? wrapper.preferredFilename
                        ?? "Imported Image"
                )

            return
        }

        if contentType.conforms(to: .pdf) {
            guard
                !wrapper.isDirectory,
                let data =
                    wrapper.regularFileContents,
                let pdf =
                    PDFDocument(
                        data:
                            data
                    )
            else {
                throw CocoaError(
                    .fileReadCorruptFile
                )
            }

            let imported =
                NSMutableAttributedString()

            for pageIndex
                in 0..<pdf.pageCount {

                guard
                    let page =
                        pdf.page(
                            at:
                                pageIndex
                        )
                else {
                    continue
                }

                if let attributed =
                    page.attributedString,
                   attributed.length > 0 {

                    imported.append(
                        attributed
                    )

                } else if let string =
                    page.string,
                          !string.isEmpty {

                    imported.append(
                        NSAttributedString(
                            string:
                                string
                        )
                    )
                }

                if pageIndex
                    < pdf.pageCount - 1 {

                    imported.append(
                        NSAttributedString(
                            string:
                                "\n\n"
                        )
                    )
                }
            }

            guard
                imported.length > 0
            else {
                throw CocoaError(
                    .fileReadCorruptFile
                )
            }

            text =
                imported

            metadata =
                DocumentMetadata()

            return
        }

        if wrapper.isDirectory, let children = wrapper.fileWrappers,
           let contentWrapper = children["content.rtfd"] {
            guard let decoded = NSAttributedString(rtfdFileWrapper: contentWrapper, documentAttributes: nil) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            var decodedMetadata: DocumentMetadata
            if let metadataData = children["metadata.json"]?.regularFileContents {
                decodedMetadata = try JSONDecoder().decode(DocumentMetadata.self, from: metadataData)
            } else {
                decodedMetadata = DocumentMetadata()
            }
            try Self.restoreCoverArtworkAssets(in: &decodedMetadata, from: children)
            try Self.restoreFloatingImageAssets(in: &decodedMetadata, from: children)
            try CoverProject.validate(decodedMetadata.coverProjects ?? [])
            try PublishingTOCSettings.validate(decodedMetadata.publishingTOCs ?? [])
            let namedStyles = try NamedStyles.decodeDefinitions(decodedMetadata.namedStyles)
            try NamedStyles.validate(namedStyles)
            let namedStyleRuns = decodedMetadata.namedStyleRuns ?? []
            try NamedStyles.validateRuns(namedStyleRuns, styles: namedStyles, textLength: decoded.length)
            let restoredBookmarks = DocumentBookmarks.normalized(decodedMetadata.bookmarks)
            try DocumentBookmarks.validate(restoredBookmarks, textLength: decoded.length)
            try DocumentComments.validate(decodedMetadata.comments, textLength: decoded.length)
            try DocumentCitations.validate(decodedMetadata.citationSources ?? [])
            try DocumentEvidence.validate(decodedMetadata.claimEvidence ?? [], sources: decodedMetadata.citationSources ?? [])
            let mutable = NSMutableAttributedString(attributedString: decoded)
            Self.restoreStyleRuns(decodedMetadata.styleRuns, into: mutable)
            Self.restoreNamedStyleRuns(namedStyleRuns, styles: namedStyles, into: mutable)
            try Self.restoreChecklistRuns(decodedMetadata.checklistRuns ?? [], into: mutable)
            try Self.restoreNativeFields(decodedMetadata.fields ?? [], into: mutable)
            try Self.restoreNativePictureCrops(
                decodedMetadata.pictureCrops ?? [],
                into: mutable
            )
            try Self.restoreNativePictureAltText(decodedMetadata.pictureAltText ?? [], into: mutable)
            try Self.restoreNativeVMLShapes(
                decodedMetadata.vmlShapes ?? [],
                into: mutable
            )
            try Self.restoreNativeOpaqueDrawings(decodedMetadata.opaqueDrawings ?? [], into: mutable)
            try Tables.restore(decodedMetadata.tables ?? [], into: mutable)
            try Footnotes.restore(decodedMetadata.footnotes ?? [], into: mutable)
            try Endnotes.restore(decodedMetadata.endnotes ?? [], into: mutable)
            TrackChanges.restore(
                decodedMetadata.trackedChanges ?? [],
                into: mutable
            )
            try decodedMetadata.manuscriptFormatting?.restore(into:mutable)
            text = mutable
            metadata = decodedMetadata
            metadata.bookmarks = restoredBookmarks
            metadata.namedStyles = namedStyles
            metadata.namedStyleRuns = namedStyleRuns
        } else if wrapper.isDirectory, let children = wrapper.fileWrappers,
                  let content = children["content.rtf"]?.regularFileContents {
            let decoded = try Self.decodeAttributedText(content, type: .rtf)
            var decodedMetadata = try children["metadata.json"]?.regularFileContents.map { try JSONDecoder().decode(DocumentMetadata.self, from: $0) } ?? DocumentMetadata()
            try Self.restoreCoverArtworkAssets(in: &decodedMetadata, from: children)
            try Self.restoreFloatingImageAssets(in: &decodedMetadata, from: children)
            try CoverProject.validate(decodedMetadata.coverProjects ?? [])
            try PublishingTOCSettings.validate(decodedMetadata.publishingTOCs ?? [])
            let namedStyles = try NamedStyles.decodeDefinitions(decodedMetadata.namedStyles)
            try NamedStyles.validate(namedStyles)
            let namedStyleRuns = decodedMetadata.namedStyleRuns ?? []
            try NamedStyles.validateRuns(namedStyleRuns, styles: namedStyles, textLength: decoded.length)
            let restoredBookmarks = DocumentBookmarks.normalized(decodedMetadata.bookmarks)
            try DocumentBookmarks.validate(restoredBookmarks, textLength: decoded.length)
            try DocumentComments.validate(decodedMetadata.comments, textLength: decoded.length)
            try DocumentCitations.validate(decodedMetadata.citationSources ?? [])
            try DocumentEvidence.validate(decodedMetadata.claimEvidence ?? [], sources: decodedMetadata.citationSources ?? [])
            let mutable = NSMutableAttributedString(attributedString: decoded)
            Self.restoreStyleRuns(decodedMetadata.styleRuns, into: mutable)
            Self.restoreNamedStyleRuns(namedStyleRuns, styles: namedStyles, into: mutable)
            try Self.restoreChecklistRuns(decodedMetadata.checklistRuns ?? [], into: mutable)
            try Self.restoreNativeFields(decodedMetadata.fields ?? [], into: mutable)
            try Self.restoreNativePictureCrops(
                decodedMetadata.pictureCrops ?? [],
                into: mutable
            )
            try Self.restoreNativePictureAltText(decodedMetadata.pictureAltText ?? [], into: mutable)
            try Self.restoreNativeVMLShapes(
                decodedMetadata.vmlShapes ?? [],
                into: mutable
            )
            try Self.restoreNativeOpaqueDrawings(decodedMetadata.opaqueDrawings ?? [], into: mutable)
            try Tables.restore(decodedMetadata.tables ?? [], into: mutable)
            try Footnotes.restore(decodedMetadata.footnotes ?? [], into: mutable)
            try Endnotes.restore(decodedMetadata.endnotes ?? [], into: mutable)
            TrackChanges.restore(
                decodedMetadata.trackedChanges ?? [],
                into: mutable
            )
            try decodedMetadata.manuscriptFormatting?.restore(into:mutable)
            text = mutable
            metadata = decodedMetadata
            metadata.bookmarks = restoredBookmarks
            metadata.namedStyles = namedStyles
            metadata.namedStyleRuns = namedStyleRuns
        } else if wrapper.isDirectory, contentType == .rtfd {
            guard let decoded = NSAttributedString(rtfdFileWrapper: wrapper, documentAttributes: nil) else { throw CocoaError(.fileReadCorruptFile) }
            text = decoded
            metadata = DocumentMetadata(title: wrapper.filename ?? "Imported Document")
        } else if let data = wrapper.regularFileContents {
            var importedMetadata =
                DocumentMetadata(
                    title:
                        wrapper.filename
                        ?? "Imported Document"
                )

            if contentType == .docx {
                let imported =
                    try DOCXImporter
                        .importedDocument(
                            from:
                                data
                        )

                text =
                    imported.text

                importedMetadata.page =
                    imported.page

                importedMetadata.sections =
                    imported.sections
                importedMetadata.floatingImages = imported.floatingImages.isEmpty ? nil : imported.floatingImages

                importedMetadata.comments =
                    imported.comments
                try DocumentComments.validate(importedMetadata.comments, textLength: imported.text.length)
                importedMetadata.namedStyles = NamedStyles.mergedWithBuiltIns(imported.namedStyles)
                try NamedStyles.validate(importedMetadata.namedStyles ?? [])

                importedMetadata.bookmarks =
                    imported.bookmarks
                importedMetadata.bookmarks = DocumentBookmarks.normalized(importedMetadata.bookmarks)
                try DocumentBookmarks.validate(importedMetadata.bookmarks, textLength: imported.text.length)

                importedMetadata
                    .trackChangesEnabled =
                    try DOCXImporter
                        .trackChangesEnabled(
                            from:
                                data
                        )
                lastErrorMessage = imported.floatingImageWarning
            } else {
                text =
                    try Self.decodeAttributedText(
                        data,
                        type:
                            contentType
                    )
            }

            metadata = importedMetadata
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func snapshot(contentType: UTType) throws -> WriterDocumentSnapshot {
        var current = metadata
        current.modifiedAt = Date()
        current.styleRuns = Self.captureStyleRuns(in: text)
        return WriterDocumentSnapshot(text: text.copy() as! NSAttributedString, metadata: current)
    }

    func updateFloatingImages(_ images: [FloatingImage]?) {
        metadata.floatingImages = images?.isEmpty == true ? nil : images
        revisionID = UUID()
    }

    func createFloatingImageRecoveryCheckpoint() throws {
        try FloatingImageRecovery.save(text: text, metadata: metadata)
    }

    var hasFloatingImageRecoveryCheckpoint: Bool {
        guard let url = try? FloatingImageRecovery.checkpointURL(text: text, metadata: metadata) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    @discardableResult
    func restoreFloatingImageRecoveryCheckpoint() throws -> Bool {
        var restoredText = text
        var restoredMetadata = metadata
        guard try FloatingImageRecovery.restore(text: &restoredText, metadata: &restoredMetadata) else { return false }
        text = restoredText
        metadata = restoredMetadata
        revisionID = UUID()
        return true
    }

    func fileWrapper(
        snapshot: WriterDocumentSnapshot,
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        if configuration.contentType == .docx {
            let data =
                try DOCXExporter.data(
                    from:
                        snapshot.text,
                    title:
                        snapshot.metadata.title,
                    settings:
                        snapshot.metadata.page,
                    sections:
                        snapshot.metadata.sections,
                    trackChangesEnabled:
                        snapshot.metadata
                            .trackChangesEnabled,
                    comments:
                        snapshot.metadata.comments,
                    bookmarks:
                        snapshot.metadata.bookmarks,
                    namedStyles:
                        NamedStyles.mergedWithBuiltIns(snapshot.metadata.namedStyles ?? []),
                    floatingImages: snapshot.metadata.floatingImages ?? []
                )

            return FileWrapper(
                regularFileWithContents:
                    data
            )
        }

        let wrapper = try Self.packageWrapper(
            text:
                snapshot.text,
            metadata:
                snapshot.metadata
        )
#if DEBUG
        // Controlled crash-recovery acceptance point. The complete package has
        // been serialized in memory, but SwiftUI has not yet received the
        // FileWrapper to write or replace the on-disk document. This hook is
        // unavailable in Release builds and inert unless an isolated test
        // process explicitly supplies both environment variables.
        if let markerPath = ProcessInfo.processInfo.environment["BOLD_NATIVE_SAVE_TEST_READY_FILE"],
           !markerPath.isEmpty,
           ProcessInfo.processInfo.environment["BOLD_NATIVE_SAVE_TEST_PAUSE"] == "1" {
            try Data("serialized-before-filewrapper-return".utf8).write(to: URL(fileURLWithPath: markerPath), options: .atomic)
            while true { Thread.sleep(forTimeInterval: 0.05) }
        }
#endif
        return wrapper
    }

    private static func captureChecklistRuns(
        in text: NSAttributedString
    ) throws -> [ChecklistRun] {
        guard text.length > 0 else { return [] }

        var runs: [ChecklistRun] = []
        let full = NSRange(location: 0, length: text.length)

        text.enumerateAttribute(
            .boldWriterChecklist,
            in: full
        ) { value, range, _ in
            guard (value as? Bool) == true, range.length > 0 else {
                return
            }

            let checked =
                text.attribute(
                    .boldWriterChecklistChecked,
                    at: range.location,
                    effectiveRange: nil
                ) as? Bool
                ?? false

            runs.append(
                ChecklistRun(
                    location: range.location,
                    length: range.length,
                    checked: checked
                )
            )
        }

        return runs
    }

    private static func restoreChecklistRuns(
        _ runs: [ChecklistRun],
        into text: NSMutableAttributedString
    ) throws {
        for run in runs {
            guard
                run.location >= 0,
                run.length > 0,
                run.location <= text.length,
                run.length <= text.length - run.location
            else {
                throw WriterError.message(
                    "The document contains invalid checklist metadata."
                )
            }

            let range =
                NSRange(
                    location: run.location,
                    length: run.length
                )

            text.addAttribute(
                .boldWriterChecklist,
                value: true,
                range: range
            )

            text.addAttribute(
                .boldWriterChecklistChecked,
                value: run.checked,
                range: range
            )

            var spans: [(NSRange, NSParagraphStyle?)] = []

            text.enumerateAttribute(
                .paragraphStyle,
                in: range
            ) { value, subrange, _ in
                spans.append(
                    (
                        subrange,
                        value as? NSParagraphStyle
                    )
                )
            }

            let list =
                NSTextList(
                    markerFormat:
                        run.checked
                            ? .check
                            : .box,
                    options:
                        0
                )

            for (subrange, existing) in spans {
                let paragraph =
                    existing?
                        .mutableCopy()
                        as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()

                paragraph.textLists = [list]
                paragraph.headIndent =
                    max(
                        paragraph.headIndent,
                        36
                    )
                paragraph.firstLineHeadIndent =
                    min(
                        paragraph.firstLineHeadIndent,
                        18
                    )

                text.addAttribute(
                    .paragraphStyle,
                    value: paragraph,
                    range: subrange
                )
            }
        }
    }

    static func packageWrapper(text: NSAttributedString, metadata: DocumentMetadata) throws -> FileWrapper {
        try FloatingImage.validate(metadata.floatingImages ?? [], textLength: text.length)
        try DocumentComments.validate(metadata.comments, textLength: text.length)
        try DocumentCitations.validate(metadata.citationSources ?? [])
        try DocumentEvidence.validate(metadata.claimEvidence ?? [], sources: metadata.citationSources ?? [])
        try CoverProject.validate(metadata.coverProjects ?? [])
        try PublishingTOCSettings.validate(metadata.publishingTOCs ?? [])
        let full = NSRange(location: 0, length: text.length)
        let rtfd = try NativeManuscriptFormatting.textForNativeRTFD(Tables.archivable(text))
            .fileWrapper(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        var storedMetadata = metadata
        storedMetadata.styleRuns = captureStyleRuns(in: text)
        storedMetadata.manuscriptFormatting = try NativeManuscriptFormatting.capture(text)
        try DocumentBookmarks.validate(metadata.bookmarks, textLength: text.length)
        try NamedStyles.validate(metadata.namedStyles ?? [])
        let namedStyles = captureNamedStyles(in: text, existing: metadata.namedStyles ?? [])
        try NamedStyles.validate(namedStyles)
        let namedStyleRuns = captureNamedStyleRuns(in: text)
        try NamedStyles.validateRuns(namedStyleRuns, styles: namedStyles, textLength: text.length)
        storedMetadata.namedStyles = namedStyles
        storedMetadata.namedStyleRuns = namedStyleRuns
        storedMetadata.checklistRuns = try Self.captureChecklistRuns(in: text)
        let fields = captureNativeFields(in: text)
        try Self.validateNativeFields(fields, textLength: text.length)
        storedMetadata.fields = fields
        storedMetadata.pictureCrops =
            try captureNativePictureCrops(
                in: text
            )
        storedMetadata.pictureAltText = try captureNativePictureAltText(in: text)
        storedMetadata.vmlShapes =
            captureNativeVMLShapes(
                in: text
            )
        storedMetadata.opaqueDrawings = try captureNativeOpaqueDrawings(in: text)
        storedMetadata.footnotes = try Footnotes.records(in: text)
        storedMetadata.endnotes = try Endnotes.records(in: text)
        storedMetadata.tables = try Tables.records(in: text)
        storedMetadata.trackedChanges =
            TrackChanges.records(in: text)
        let artworkAssets = try Self.externalizeCoverArtwork(in: &storedMetadata)
        let floatingImageAssets = try Self.externalizeFloatingImageAssets(in: &storedMetadata)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metadataData = try encoder.encode(storedMetadata)
        var children: [String: FileWrapper] = [
            "content.rtfd": rtfd,
            "metadata.json": FileWrapper(regularFileWithContents: metadataData)
        ]
        if !artworkAssets.files.isEmpty {
            children["cover-artwork"] = FileWrapper(directoryWithFileWrappers: artworkAssets.files)
            children["cover-artwork-index.json"] = FileWrapper(regularFileWithContents: artworkAssets.index)
        }
        if !floatingImageAssets.isEmpty {
            children["floating-images"] = FileWrapper(directoryWithFileWrappers: floatingImageAssets)
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }

    /// Native floating-image bytes are shared by content digest and metadata
    /// stores only a stable reference. Legacy metadata bytes migrate on save.
    private static func externalizeFloatingImageAssets(in metadata: inout DocumentMetadata) throws -> [String: FileWrapper] {
        guard var images = metadata.floatingImages, !images.isEmpty else { return [:] }
        var assets: [String: Data] = [:]
        for index in images.indices {
            let bytes = images[index].imageData
            guard !bytes.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            assets[digest] = bytes
            images[index].assetDigest = digest
            images[index].imageData = Data()
        }
        metadata.floatingImages = images
        return Dictionary(uniqueKeysWithValues: assets.map { digest, bytes in
            (digest, FileWrapper(regularFileWithContents: bytes))
        })
    }

    private static func restoreFloatingImageAssets(in metadata: inout DocumentMetadata, from children: [String: FileWrapper]) throws {
        guard var images = metadata.floatingImages else { return }
        let assets = children["floating-images"]?.fileWrappers ?? [:]
        var loaded: [String: Data] = [:]
        for index in images.indices where images[index].imageData.isEmpty {
            guard let digest = images[index].assetDigest, digest.count == 64,
                  let bytes = loaded[digest] ?? assets[digest]?.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let actual = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard actual == digest else { throw CocoaError(.fileReadCorruptFile) }
            loaded[digest] = bytes
            images[index].imageData = bytes
        }
        metadata.floatingImages = images
    }

    /// Store reusable cover bytes once per package. Older packages keep their
    /// inline Data representation and remain readable without a migration step.
    private static func externalizeCoverArtwork(in metadata: inout DocumentMetadata) throws -> (files: [String: FileWrapper], index: Data) {
        guard var projects = metadata.coverProjects, !projects.isEmpty else { return ([:], Data()) }
        var assets: [String: Data] = [:]
        var references: [CoverArtworkAssetIndex.Reference] = []
        func store(_ data: inout Data?, projectID: UUID, layerID: UUID, slot: String) {
            guard let bytes = data else { return }
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            assets[digest] = bytes
            references.append(.init(projectID: projectID, layerID: layerID, slot: slot, digest: digest))
            data = nil
        }
        for projectIndex in projects.indices {
            for layerIndex in projects[projectIndex].layers.indices {
                let projectID = projects[projectIndex].id
                let layerID = projects[projectIndex].layers[layerIndex].id
                store(&projects[projectIndex].layers[layerIndex].imageData, projectID: projectID, layerID: layerID, slot: "image")
                store(&projects[projectIndex].layers[layerIndex].maskData, projectID: projectID, layerID: layerID, slot: "mask")
                if var smartObject = projects[projectIndex].layers[layerIndex].smartObject {
                    var sourceData: Data? = smartObject.sourceData
                    store(&sourceData, projectID: projectID, layerID: layerID, slot: "smartObjectSource")
                    if let sourceData { smartObject.sourceData = sourceData }
                    projects[projectIndex].layers[layerIndex].smartObject = smartObject
                }
            }
        }
        metadata.coverProjects = projects
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let index = try encoder.encode(CoverArtworkAssetIndex(version: 1, references: references))
        let files = Dictionary(uniqueKeysWithValues: assets.map { digest, data in
            (digest, FileWrapper(regularFileWithContents: data))
        })
        return (files, index)
    }

    private static func restoreCoverArtworkAssets(in metadata: inout DocumentMetadata, from children: [String: FileWrapper]) throws {
        guard let indexData = children["cover-artwork-index.json"]?.regularFileContents else { return }
        let index = try JSONDecoder().decode(CoverArtworkAssetIndex.self, from: indexData)
        guard index.version == 1, var projects = metadata.coverProjects else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let assetWrappers = children["cover-artwork"]?.fileWrappers ?? [:]
        var loaded: [String: Data] = [:]
        func asset(_ digest: String) throws -> Data {
            guard digest.count == 64, digest.allSatisfy({ $0.isHexDigit }),
                  let bytes = loaded[digest] ?? assetWrappers[digest]?.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if loaded[digest] == nil {
                let actual = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                guard actual == digest else { throw CocoaError(.fileReadCorruptFile) }
                loaded[digest] = bytes
            }
            return bytes
        }
        for reference in index.references {
            guard let projectIndex = projects.firstIndex(where: { $0.id == reference.projectID }),
                  let layerIndex = projects[projectIndex].layers.firstIndex(where: { $0.id == reference.layerID }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let bytes = try asset(reference.digest)
            switch reference.slot {
            case "image": projects[projectIndex].layers[layerIndex].imageData = bytes
            case "mask": projects[projectIndex].layers[layerIndex].maskData = bytes
            case "smartObjectSource":
                guard var smartObject = projects[projectIndex].layers[layerIndex].smartObject else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                smartObject.sourceData = bytes
                projects[projectIndex].layers[layerIndex].smartObject = smartObject
            default: throw CocoaError(.fileReadCorruptFile)
            }
        }
        metadata.coverProjects = projects
    }

    /// Replace manuscript content while retaining the current book's cover and studio.
    /// The original manuscript remains available through a single undo operation.
    @MainActor
    func importManuscript(_ imported: WriterDocumentSnapshot, undoManager: UndoManager?) {
        var next = imported.metadata
        next.title = metadata.title
        next.createdAt = metadata.createdAt
        next.coverProjects = metadata.coverProjects
        next.activeCoverProjectID = metadata.activeCoverProjectID
        next.bookStudioPresentation = metadata.bookStudioPresentation
        next.notes = metadata.notes
        next.revisions = metadata.revisions
        undoManager?.removeAllActions()
        undoManager?.beginUndoGrouping()
        restoreManuscript(WriterDocumentSnapshot(text: imported.text, metadata: next), undoManager: undoManager)
        undoManager?.endUndoGrouping()
    }

    @MainActor
    private func restoreManuscript(_ snapshot: WriterDocumentSnapshot, undoManager: UndoManager?) {
        let previous = WriterDocumentSnapshot(text: text, metadata: metadata)
        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreManuscript(previous, undoManager: undoManager)
        }
        undoManager?.setActionName("Import Manuscript")
        metadata = snapshot.metadata
        replaceText(with: snapshot.text)
        manuscriptReplacementRevisionID = revisionID
    }

    func replaceText(with newText: NSAttributedString) {
        text = newText.copy() as! NSAttributedString
        metadata.modifiedAt = Date()
        revisionID = UUID()
    }

    func replaceEditedText(
        with newText: NSAttributedString
    ) {
        var updatedMetadata =
            metadata

        updatedMetadata
            .rebaseTextAnchors(
                from:
                    text.string,
                to:
                    newText.string
            )

        metadata =
            updatedMetadata

        replaceText(
            with:
                newText
        )
    }

    @discardableResult
    func createRevision(named name: String, kind: RevisionRecord.Kind = .manual) -> Bool {
        do {
            let range = NSRange(location: 0, length: text.length)
            let wrapper = try Tables.archivable(text).fileWrapper(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
            guard let serialized = wrapper.serializedRepresentation else { throw WriterError.message("The recovery point could not be created. No writing was changed.") }
            let rtf = (try? text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
            let contentMetadata = RevisionContentMetadata(
                title: metadata.title,
                page: metadata.page,
                sections: metadata.sections,
                styles: Self.captureStyleRuns(in: text),
                comments: metadata.comments,
                bookmarks: metadata.bookmarks,
                notes: metadata.notes,
                footnotes: try Footnotes.records(in: text),
                endnotes: try Endnotes.records(in: text),
                tables: try Tables.records(in: text),
                trackedChanges: TrackChanges.records(in: text),
                fields: Self.captureNativeFields(in: text),
                citationSources: metadata.citationSources,
                citationStyle: metadata.citationStyle,
                claimEvidence: metadata.claimEvidence
            )
            metadata.revisions.insert(RevisionRecord(name: name, kind: kind, rtfData: rtf, rtfdData: serialized, documentMetadata: contentMetadata), at: 0)
            if metadata.revisions.count > 20 { metadata.revisions.removeLast(metadata.revisions.count - 20) }
            return true
        } catch {
            lastErrorMessage = "Could not save a recovery point: \(error.localizedDescription)"
            return false
        }
    }

    func restore(_ revision: RevisionRecord) throws {
        let decoded: NSAttributedString
        if let data = revision.rtfdData, let wrapper = FileWrapper(serializedRepresentation: data),
           let restored = NSAttributedString(rtfdFileWrapper: wrapper, documentAttributes: nil) {
            decoded = restored
        } else {
            decoded = try Self.decodeAttributedText(revision.rtfData, type: .rtf)
        }
        guard createRevision(named: "Before restoring \(revision.name)", kind: .manual) else {
            throw WriterError.message("A safety recovery point could not be created, so this restore was cancelled.")
        }
        let mutable = NSMutableAttributedString(attributedString: decoded)
        if let previous = revision.documentMetadata {
            Self.restoreStyleRuns(previous.styles, into: mutable)
            try Self.restoreNativeFields(previous.fields ?? [], into: mutable)
            try Tables.restore(previous.tables ?? [], into: mutable)
            try Footnotes.restore(previous.footnotes ?? [], into: mutable)
            try Endnotes.restore(previous.endnotes ?? [], into: mutable)
            TrackChanges.restore(
                previous.trackedChanges ?? [],
                into: mutable
            )
            metadata.title = previous.title
            metadata.page = previous.page
            metadata.sections = previous.sections
            metadata.comments = previous.comments
            metadata.bookmarks = previous.bookmarks
            metadata.notes = previous.notes
            metadata.citationSources = previous.citationSources
            metadata.citationStyle = previous.citationStyle
            metadata.claimEvidence = previous.claimEvidence
        }
        text = mutable
        revisionID = UUID()
    }

    private static func decodeAttributedText(_ data: Data, type: UTType) throws -> NSAttributedString {
        let documentType: NSAttributedString.DocumentType
        if type == .boldWriterMarkdown {
            return NSAttributedString(
                string:
                    String(
                        decoding:
                            data,
                        as:
                            UTF8.self
                    )
            )
        }

        switch type {
        case .html: documentType = .html
        case .rtfd: documentType = .rtfd
        case .docx: return try DOCXImporter.text(from: data)
        case .plainText:
            guard let value = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            return NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: 15)])
        default: documentType = .rtf
        }
        return try NSAttributedString(data: data, options: [.documentType: documentType], documentAttributes: nil)
    }

    private static func captureStyleRuns(in text: NSAttributedString) -> [StyleRun] {
        var result: [StyleRun] = []
        text.enumerateAttribute(.boldWriterStyle, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let raw = value as? String, let style = WriterStyle(rawValue: raw) {
                result.append(StyleRun(location: range.location, length: range.length, style: style))
            }
        }
        return result
    }

    private static func restoreStyleRuns(_ runs: [StyleRun], into mutable: NSMutableAttributedString) {
        for run in runs where run.location >= 0 && run.location <= mutable.length && run.length >= 0 && run.length <= mutable.length - run.location {
            mutable.addAttribute(.boldWriterStyle, value: run.style.rawValue, range: NSRange(location: run.location, length: run.length))
        }
    }

    private static func captureNamedStyles(in text: NSAttributedString, existing: [NamedStyleDefinition]) -> [NamedStyleDefinition] {
        var byID = Dictionary(NamedStyles.mergedWithBuiltIns(existing).map { ($0.styleID, $0) }, uniquingKeysWith: { first, _ in first })
        if text.length > 0 {
            for key in [NSAttributedString.Key.boldWriterParagraphStyle, .boldWriterCharacterStyle] {
                text.enumerateAttribute(key, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                    if let paragraph = value as? WordParagraphStyle, byID[paragraph.styleID] == nil {
                        byID[paragraph.styleID] = NamedStyleDefinition(styleID: paragraph.styleID, name: paragraph.name ?? paragraph.styleID, kind: .paragraph, basedOn: paragraph.basedOn, nextStyleID: paragraph.nextStyleID, linkedStyleID: paragraph.linkedStyleID)
                    } else if let character = value as? WordCharacterStyle, byID[character.styleID] == nil {
                        byID[character.styleID] = NamedStyleDefinition(styleID: character.styleID, name: character.name ?? character.styleID, kind: .character, basedOn: character.basedOn, linkedStyleID: character.linkedStyleID)
                    }
                }
            }
        }
        return byID.values.sorted { $0.styleID < $1.styleID }
    }

    private static func captureNamedStyleRuns(in text: NSAttributedString) -> [NamedStyleRun] {
        var runs: [NamedStyleRun] = []
        for (key, kind) in [(NSAttributedString.Key.boldWriterParagraphStyle, NamedStyleKind.paragraph), (.boldWriterCharacterStyle, .character)] {
            text.enumerateAttribute(key, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                let id = (value as? WordParagraphStyle)?.styleID ?? (value as? WordCharacterStyle)?.styleID
                if let id, !id.isEmpty, range.length > 0 { runs.append(NamedStyleRun(styleID: id, kind: kind, location: range.location, length: range.length)) }
            }
        }
        return runs.sorted { $0.location == $1.location ? $0.kind.rawValue < $1.kind.rawValue : $0.location < $1.location }
    }

    private static func captureNativeFields(in text: NSAttributedString) -> [NativeFieldRun] {
        var result: [NativeFieldRun] = []
        text.enumerateAttribute(.boldWriterField, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let field = value as? WordField, range.length > 0 else { return }
            result.append(NativeFieldRun(id: field.id, kind: field.kind, instruction: field.instruction, dirtyValue: field.dirtyValue, lockedValue: field.lockedValue, location: range.location, length: range.length))
        }
        return result
    }

    private static func restoreNativeFields(_ fields: [NativeFieldRun], into text: NSMutableAttributedString) throws {
        try validateNativeFields(fields, textLength: text.length)
        for field in fields {
            text.addAttribute(.boldWriterField, value: WordField(id: field.id, kind: field.kind, instruction: field.instruction, dirtyValue: field.dirtyValue, lockedValue: field.lockedValue), range: NSRange(location: field.location, length: field.length))
        }
    }

    private static func validateNativeFields(_ fields: [NativeFieldRun], textLength: Int) throws {
        var ids = Set<UUID>()
        for field in fields {
            guard ids.insert(field.id).inserted, field.location >= 0, field.length > 0, field.location <= textLength, field.length <= textLength - field.location else {
                throw WriterError.message("The document contains malformed field metadata.")
            }
        }
    }

    private static func captureNativeVMLShapes(
        in text: NSAttributedString
    ) -> [NativeVMLShapeRun] {
        guard text.length > 0 else {
            return []
        }

        var result: [NativeVMLShapeRun] = []

        text.enumerateAttribute(
            .boldWriterWordVMLShape,
            in: NSRange(
                location: 0,
                length: text.length
            )
        ) {
            value,
            range,
            _ in

            guard
                let shape = value as? WordVMLShape,
                shape.isSupportedTextShape,
                range.length > 0
            else {
                return
            }

            result.append(
                NativeVMLShapeRun(
                    shapeKind: shape.shapeKind,
                    shapeID: shape.shapeID,
                    style: shape.style,
                    fillColor: shape.fillColor,
                    strokeColor: shape.strokeColor,
                    strokeWeight: shape.strokeWeight,
                    textBoxInset: shape.textBoxInset,
                    location: range.location,
                    length: range.length
                )
            )
        }

        return result
    }

    private static func restoreNativeVMLShapes(
        _ records: [NativeVMLShapeRun],
        into text: NSMutableAttributedString
    ) throws {
        for record in records {
            let range =
                NSRange(
                    location: record.location,
                    length: record.length
                )

            guard
                range.location >= 0,
                range.length > 0,
                NSMaxRange(range) <= text.length
            else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let shape =
                WordVMLShape(
                    shapeKind: record.shapeKind,
                    shapeID: record.shapeID,
                    style: record.style,
                    fillColor: record.fillColor,
                    strokeColor: record.strokeColor,
                    strokeWeight: record.strokeWeight,
                    textBoxInset: record.textBoxInset
                )

            guard shape.isSupportedTextShape else {
                throw CocoaError(.fileReadCorruptFile)
            }

            text.addAttribute(
                .boldWriterWordVMLShape,
                value: shape,
                range: range
            )
        }
    }

    private static func captureNativeOpaqueDrawings(in text: NSAttributedString) throws -> [NativeOpaqueDrawingRun] {
        guard text.length > 0 else { return [] }
        var records: [NativeOpaqueDrawingRun] = []
        var failure: Error?
        text.enumerateAttribute(.boldWriterWordOpaqueDrawing, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let drawing = value as? WordOpaqueDrawing else { return }
            do {
                _ = try WordOpaqueDrawing.validated(id: drawing.id, xml: drawing.xml,
                    isRunChild: drawing.isRunChild, relationships: drawing.relationships, parts: drawing.parts)
                records.append(.init(location: range.location, length: range.length,
                                     xml: drawing.xml, isRunChild: drawing.isRunChild,
                                     id: drawing.id, relationships: drawing.relationships, parts: drawing.parts))
            } catch { failure = error }
        }
        if let failure { throw failure }
        return records
    }

    private static func restoreNativeOpaqueDrawings(_ records: [NativeOpaqueDrawingRun],
                                                   into text: NSMutableAttributedString) throws {
        for record in records {
            guard record.location >= 0, record.length > 0,
                  record.location <= text.length, record.length <= text.length - record.location else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let drawing = try WordOpaqueDrawing.validated(id: record.id ?? UUID(), xml: record.xml,
                isRunChild: record.isRunChild, relationships: record.relationships ?? [], parts: record.parts ?? [])
            text.addAttribute(.boldWriterWordOpaqueDrawing, value: drawing,
                              range: NSRange(location: record.location, length: record.length))
        }
    }

    private static func captureNativePictureAltText(in text: NSAttributedString) throws -> [NativePictureAltTextRun] {
        guard text.length > 0 else { return [] }
        var records: [NativePictureAltTextRun] = []
        var invalid = false
        text.enumerateAttribute(.boldWriterWordPictureAltText, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let alt = value as? WordPictureAltText else { return }
            guard range.length == 1, range.location >= 0, range.location < text.length,
                  text.attribute(.attachment, at: range.location, effectiveRange: nil) is NSTextAttachment else {
                invalid = true
                return
            }
            records.append(.init(location: range.location, length: range.length,
                                 title: alt.title, alternativeDescription: alt.alternativeDescription))
        }
        guard !invalid else { throw WriterError.message("A Word picture description could not be saved without changing it.") }
        return records
    }

    private static func restoreNativePictureAltText(_ records: [NativePictureAltTextRun], into text: NSMutableAttributedString) throws {
        for record in records {
            guard record.location >= 0, record.length == 1, record.location < text.length,
                  text.attribute(.attachment, at: record.location, effectiveRange: nil) is NSTextAttachment else {
                throw CocoaError(.fileReadCorruptFile)
            }
            text.addAttribute(.boldWriterWordPictureAltText,
                              value: WordPictureAltText(title: record.title, alternativeDescription: record.alternativeDescription),
                              range: NSRange(location: record.location, length: record.length))
        }
    }

    private static func captureNativePictureCrops(
        in text: NSAttributedString
    ) throws -> [NativePictureCropRun] {
        guard text.length > 0 else {
            return []
        }

        var result: [NativePictureCropRun] = []
        var invalid = false

        text.enumerateAttribute(
            .boldWriterWordPictureCrop,
            in:
                NSRange(
                    location: 0,
                    length: text.length
                )
        ) {
            value,
            range,
            _ in

            guard
                let crop = value as? WordPictureCrop
            else {
                return
            }

            guard
                crop.hasValidGeometry,
                range.length > 0,
                range.location >= 0,
                range.location <= text.length,
                range.length <= text.length - range.location
            else {
                invalid = true
                return
            }

            result.append(
                NativePictureCropRun(
                    location: range.location,
                    length: range.length,
                    left: crop.left,
                    top: crop.top,
                    right: crop.right,
                    bottom: crop.bottom
                )
            )
        }

        guard !invalid else {
            throw WriterError.message(
                "A Word picture crop could not be saved without changing it."
            )
        }

        return result
    }

    private static func restoreNativePictureCrops(
        _ records: [NativePictureCropRun],
        into text: NSMutableAttributedString
    ) throws {
        for record in records {
            guard
                record.location >= 0,
                record.length > 0,
                record.location <= text.length,
                record.length <= text.length - record.location
            else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let crop =
                WordPictureCrop(
                    left: record.left,
                    top: record.top,
                    right: record.right,
                    bottom: record.bottom
                )

            guard crop.hasValidGeometry else {
                throw CocoaError(.fileReadCorruptFile)
            }

            guard
                let attachment =
                    text.attribute(
                        .attachment,
                        at:
                            record.location,
                        effectiveRange:
                            nil
                    )
                    as? NSTextAttachment
            else {
                throw CocoaError(
                    .fileReadCorruptFile
                )
            }

            try DOCXImages.applyWordPictureCrop(
                crop,
                to:
                    attachment
            )

            text.addAttribute(
                .boldWriterWordPictureCrop,
                value: crop,
                range:
                    NSRange(
                        location: record.location,
                        length: record.length
                    )
            )
        }
    }


    private static func restoreNamedStyleRuns(_ runs: [NamedStyleRun], styles: [NamedStyleDefinition], into text: NSMutableAttributedString) {
        let definitions = Dictionary(styles.map { ($0.styleID, $0) }, uniquingKeysWith: { first, _ in first })
        var restoredParagraphStyles: [String: WordParagraphStyle] = [:]
        var restoredCharacterStyles: [String: WordCharacterStyle] = [:]
        for run in runs {
            guard let definition = definitions[run.styleID], run.location >= 0, run.location <= text.length,
                  run.length > 0, run.length <= text.length - run.location else { continue }
            let range = NSRange(location: run.location, length: run.length)
            if run.kind == .paragraph {
                let value: WordParagraphStyle
                if let cached = restoredParagraphStyles[run.styleID] {
                    value = cached
                } else {
                    let dependencies = styles.filter { $0.styleID != run.styleID }.map {
                        WordStyleDependency(kind: $0.kind == .character ? .character : .paragraph, styleID: $0.styleID, name: $0.name, basedOn: $0.basedOn, linkedStyleID: $0.linkedStyleID, nextStyleID: $0.nextStyleID)
                    }
                    value = WordParagraphStyle(styleID: definition.styleID, name: definition.name, basedOn: definition.basedOn, linkedStyleID: definition.linkedStyleID, nextStyleID: definition.nextStyleID, dependencies: dependencies)
                    restoredParagraphStyles[run.styleID] = value
                }
                text.addAttribute(.boldWriterParagraphStyle, value: value, range: range)
            } else {
                let value: WordCharacterStyle
                if let cached = restoredCharacterStyles[run.styleID] {
                    value = cached
                } else {
                    let dependencies = styles.filter { $0.styleID != run.styleID }.map {
                        WordStyleDependency(kind: $0.kind == .character ? .character : .paragraph, styleID: $0.styleID, name: $0.name, basedOn: $0.basedOn, linkedStyleID: $0.linkedStyleID, nextStyleID: $0.nextStyleID)
                    }
                    value = WordCharacterStyle(styleID: definition.styleID, name: definition.name, basedOn: definition.basedOn, linkedStyleID: definition.linkedStyleID, dependencies: dependencies)
                    restoredCharacterStyles[run.styleID] = value
                }
                text.addAttribute(.boldWriterCharacterStyle, value: value, range: range)
            }
        }
    }
}
