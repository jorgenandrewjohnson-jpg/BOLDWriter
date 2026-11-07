import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF"
    case docx = "Word (.docx)"
    case rtf = "Rich Text (.rtf)"
    case html = "Web Page (.html)"
    case markdown = "Markdown (.md)"
    case plainText = "Plain Text (.txt)"
    case epub = "EPUB (.epub)"
    var id: String { rawValue }
    var extensionName: String {
        switch self {
        case .pdf: "pdf"; case .docx: "docx"; case .rtf: "rtf"; case .html: "html"
        case .markdown: "md"; case .plainText: "txt"; case .epub: "epub"
        }
    }

    var contentType: UTType {
        UTType(
            filenameExtension:
                extensionName
        )
        ?? .data
    }

    func normalizedURL(
        for url: URL
    ) -> URL {
        if url
            .pathExtension
            .caseInsensitiveCompare(
                extensionName
            )
            == .orderedSame
        {
            return url
        }

        let baseURL =
            url.pathExtension.isEmpty
            ? url
            : url.deletingPathExtension()

        return baseURL
            .appendingPathExtension(
                extensionName
            )
    }
}

@MainActor
enum ExportService {
    static func data(for format: ExportFormat, document: BOLDWriterDocument) throws -> Data {
        let range = NSRange(location: 0, length: document.text.length)
        switch format {
        case .pdf:
            return try PDFExporter.data(
                from:
                    document.text,
                settings:
                    document.metadata.page,
                sections:
                    document.metadata.sections,
                floatingImages:
                    document.metadata.floatingImages ?? []
            )
        case .docx:
            return try DOCXExporter.data(
                from: document.text,
                title: document.metadata.title,
                settings: document.metadata.page,
                sections:
                    document.metadata.sections,
                trackChangesEnabled:
                    document.metadata
                        .trackChangesEnabled,
                comments:
                    document.metadata
                        .comments,
                bookmarks:
                    document.metadata
                        .bookmarks,
                namedStyles:
                    NamedStyles.mergedWithBuiltIns(document.metadata.namedStyles ?? []),
                floatingImages: document.metadata.floatingImages ?? []
            )
        case .rtf: return try document.text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        case .html: return try document.text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
        case .markdown: return Data(markdown(document.text).utf8)
        case .plainText: return Data(document.text.string.utf8)
        case .epub:
            return try EPUBExporter.data(
                from:
                    document.text,
                title:
                    document.metadata.title,
                bookmarks: document.metadata.bookmarks,
                tocSettings: document.metadata.publishingTOCs ?? []
            )
        }
    }

    @discardableResult
    static func write(
        _ format: ExportFormat,
        document: BOLDWriterDocument,
        to url: URL,
        using writer: AtomicExportFileWriter = .system
    ) throws -> URL {
        guard
            url.pathExtension
                .lowercased()
                != "boldwriter"
        else {
            throw WriterError.message(
                "Choose a different export name. Your native BOLD Writer manuscript cannot be replaced by an export."
            )
        }

        let destination =
            format.normalizedURL(
                for: url
            )

        let data =
            try data(
                for: format,
                document: document
            )

        try writer.write(data, to: destination)

        return destination
    }

    private static func markdown(_ text: NSAttributedString) -> String {
        let ns = text.string as NSString
        var result = ""
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            let value = ns.substring(with: range).trimmingCharacters(in: .newlines)
            let styleRaw = range.length > 0 ? text.attribute(.boldWriterStyle, at: range.location, effectiveRange: nil) as? String : nil
            let style = styleRaw.flatMap(WriterStyle.init(rawValue:))
            let prefix = style?.headingLevel.map { String(repeating: "#", count: $0) + " " } ?? (style == .blockQuote ? "> " : "")
            result += prefix + value + "\n\n"
        }
        return result
    }
}

/// Stages export bytes beside the destination and only publishes a complete
/// file with a same-volume replace/move. The injectable file operations are an
/// internal test seam for deterministic interruption and write-failure tests;
/// production always uses `.system`.
struct AtomicExportFileWriter {
    var writeStaged: (Data, URL) throws -> Void
    var exists: (URL) -> Bool
    var replace: (URL, URL) throws -> Void
    var move: (URL, URL) throws -> Void
    var remove: (URL) throws -> Void

    static let system = AtomicExportFileWriter(
        writeStaged: { data, url in try data.write(to: url, options: .atomic) },
        exists: { FileManager.default.fileExists(atPath: $0.path) },
        replace: { destination, staged in
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
        },
        move: { staged, destination in try FileManager.default.moveItem(at: staged, to: destination) },
        remove: { try FileManager.default.removeItem(at: $0) }
    )

    func write(_ data: Data, to destination: URL) throws {
        let prefix = ".\(destination.lastPathComponent).boldwriter-export-"
        removeAbandonedStages(in: destination.deletingLastPathComponent(), prefix: prefix)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            "\(prefix)\(getpid())-\(UUID().uuidString)"
        )
        defer { try? remove(temporary) }
        try writeStaged(data, temporary)
        if exists(destination) {
            try replace(destination, temporary)
        } else {
            try move(temporary, destination)
        }
    }

    /// `defer` handles ordinary write errors, but process termination can leave
    /// the outer staging file behind. New names include the owning PID so the
    /// next export can remove only stages whose writer has exited. Old-format
    /// UUID-only stages are collected after a day, when an active export cannot
    /// reasonably still be using them. Symlinks, directories, recent legacy
    /// stages, and stages owned by live processes are preserved.
    private func removeAbandonedStages(in directory: URL, prefix: String) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: []
        ) else { return }
        let now = Date()
        for entry in entries where entry.lastPathComponent.hasPrefix(prefix) {
            guard let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let suffix = entry.lastPathComponent.dropFirst(prefix.count)
            let firstComponent = suffix.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first
            let abandoned: Bool
            if let firstComponent, let ownerPID = Int32(firstComponent) {
                abandoned = !Self.processIsRunning(ownerPID)
            } else if let modifiedAt = values.contentModificationDate {
                abandoned = now.timeIntervalSince(modifiedAt) >= 86_400
            } else {
                abandoned = false
            }
            if abandoned { try? remove(entry) }
        }
    }

    private static func processIsRunning(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }
}
