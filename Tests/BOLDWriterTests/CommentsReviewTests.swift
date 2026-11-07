import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class CommentsReviewTests: XCTestCase {
    private func reopen(_ text: NSAttributedString, metadata: DocumentMetadata) throws -> BOLDWriterDocument {
        let wrapper = try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
        return try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument)
    }

    private func roundTrip(_ text: NSAttributedString, comments: [DocumentComment]) throws -> BOLDWriterDocument {
        let data = try DOCXExporter.data(from: text, title: "Comment Round Trip", comments: comments)
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "Comment Round Trip.docx"
        return try BOLDWriterDocument(fileWrapper: wrapper, contentType: .docx)
    }

    func testNativeCommentLifecycleKeepsIdentityAndFieldsAcrossReopen() throws {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "One two three four"))
        let controller = EditorController()
        let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        view.textStorage?.setAttributedString(document.text)
        controller.attach(view)
        controller.updateSelection(NSRange(location: 4, length: 3))

        var first = try controller.addComment(text: "Review & <keep>\nsecond line", author: "Reviewer A", to: document)
        first.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        document.metadata.comments[0].createdAt = first.createdAt
        controller.updateSelection(NSRange(location: 8, length: 5))
        let second = try controller.addComment(text: "Check this", author: "Reviewer B", to: document)
        let ids = document.metadata.comments.map(\.id)

        let restored = try reopen(document.text, metadata: document.metadata)
        XCTAssertEqual(restored.metadata.comments.map(\.id), ids)
        XCTAssertEqual(restored.metadata.comments.map(\.author), ["Reviewer A", "Reviewer B"])
        XCTAssertEqual(restored.metadata.comments.map(\.text), ["Review & <keep>\nsecond line", "Check this"])
        XCTAssertEqual(restored.metadata.comments.map(\.location), [4, 8])
        XCTAssertEqual(restored.metadata.comments.map(\.length), [3, 5])
        XCTAssertEqual(restored.metadata.comments[0].createdAt.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)

        try controller.editComment(id: second.id, text: "Edited body", in: document)
        XCTAssertEqual(try reopen(document.text, metadata: document.metadata).metadata.comments.last?.text, "Edited body")
        controller.deleteComment(id: first.id, in: document)
        XCTAssertEqual(try reopen(document.text, metadata: document.metadata).metadata.comments.map(\.id), [second.id])
    }

    func testCommentAnchorsRebaseAcrossEditsReplacementAndUndoRedo() throws {
        func document() -> BOLDWriterDocument {
            let result = BOLDWriterDocument()
            result.replaceText(with: NSAttributedString(string: "0123456789"))
            result.metadata.comments = [DocumentComment(text: "Note", location: 3, length: 4)]
            return result
        }

        let before = document()
        before.replaceEditedText(with: NSAttributedString(string: "XX0123456789"))
        XCTAssertEqual(before.metadata.comments[0].location, 5)
        XCTAssertEqual(before.metadata.comments[0].length, 4)

        let inside = document()
        let original = inside.text
        inside.replaceEditedText(with: NSAttributedString(string: "0123XY456789"))
        XCTAssertEqual(inside.metadata.comments[0].location, 3)
        XCTAssertEqual(inside.metadata.comments[0].length, 6)
        let edited = inside.text
        inside.replaceEditedText(with: original) // undo
        XCTAssertEqual(inside.metadata.comments[0].length, 4)
        inside.replaceEditedText(with: edited) // redo
        XCTAssertEqual(inside.metadata.comments[0].length, 6)

        let beforeDelete = document()
        beforeDelete.replaceEditedText(with: NSAttributedString(string: "23456789"))
        XCTAssertEqual(beforeDelete.metadata.comments[0].location, 1)
        XCTAssertEqual(beforeDelete.metadata.comments[0].length, 4)

        let partial = document()
        partial.replaceEditedText(with: NSAttributedString(string: "012356789"))
        XCTAssertEqual(partial.metadata.comments[0].location, 3)
        XCTAssertEqual(partial.metadata.comments[0].length, 3)

        let replaced = document()
        replaced.replaceEditedText(with: NSAttributedString(string: "012AB789"))
        XCTAssertEqual(replaced.metadata.comments[0].location, 3)
        XCTAssertEqual(replaced.metadata.comments[0].length, 2)

        let replaceAll = document()
        replaceAll.replaceEditedText(with: NSAttributedString(string: "012XX789"))
        XCTAssertEqual(replaceAll.metadata.comments[0].location, 3)
        XCTAssertEqual(replaceAll.metadata.comments[0].length, 2)

        let deleted = document()
        deleted.replaceEditedText(with: NSAttributedString(string: "012789"))
        XCTAssertEqual(deleted.metadata.comments[0].location, 3)
        XCTAssertEqual(deleted.metadata.comments[0].length, 0)
        XCTAssertNoThrow(try DocumentComments.validate(deleted.metadata.comments, textLength: deleted.text.length))
    }

    func testMalformedNativeCommentRangesAndDuplicateIDsFailSafely() throws {
        let text = NSAttributedString(string: "Short")
        var metadata = DocumentMetadata()
        metadata.comments = [DocumentComment(text: "Out of bounds", location: 4, length: 4)]
        XCTAssertThrowsError(try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata))

        metadata.comments = [
            DocumentComment(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, text: "One", location: 0, length: 1),
            DocumentComment(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, text: "Two", location: 1, length: 1)
        ]
        XCTAssertThrowsError(try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata))
    }

    func testMalformedCommentMetadataIsRejectedWhenOpeningNativePackage() throws {
        let text = NSAttributedString(string: "Short")
        let wrapper = try BOLDWriterDocument.packageWrapper(text: text, metadata: DocumentMetadata())
        let metadataFile = try XCTUnwrap(wrapper.fileWrappers?["metadata.json"])
        wrapper.removeFileWrapper(metadataFile)
        var malformed = DocumentMetadata()
        malformed.comments = [DocumentComment(text: "Outside", location: 4, length: 2)]
        let file = FileWrapper(regularFileWithContents: try JSONEncoder().encode(malformed))
        file.preferredFilename = "metadata.json"
        wrapper.addFileWrapper(file)
        XCTAssertThrowsError(try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument))
    }

    func testCommentNavigationAndSelectionUseStableCommentIdentity() throws {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "First Second Third"))
        document.metadata.comments = [
            DocumentComment(text: "Second", location: 6, length: 6),
            DocumentComment(text: "First", location: 0, length: 5),
            DocumentComment(text: "Third", location: 13, length: 5)
        ]
        let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        view.textStorage?.setAttributedString(document.text)
        let controller = EditorController()
        controller.attach(view)

        controller.navigateComment(previous: false, in: document)
        XCTAssertEqual(controller.selectedCommentID, document.metadata.comments[1].id)
        XCTAssertEqual(controller.selection, NSRange(location: 0, length: 5))
        controller.navigateComment(previous: false, in: document)
        XCTAssertEqual(controller.selectedCommentID, document.metadata.comments[0].id)
        XCTAssertEqual(controller.selection, NSRange(location: 6, length: 6))
        controller.selectComment(id: document.metadata.comments[2].id, in: document)
        XCTAssertEqual(controller.selection, NSRange(location: 13, length: 5))
    }

    func testActualReplaceAllAndUndoRedoRebaseCommentAnchor() throws {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "0123456789"))
        document.metadata.comments = [DocumentComment(text: "Replace", location: 3, length: 4)]
        let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let undo = UndoManager()
        undo.groupsByEvent = false
        view.sessionUndoManager = undo
        view.allowsUndo = true
        view.textStorage?.setAttributedString(document.text)
        let controller = EditorController()
        controller.attach(view)
        let coordinator = RichTextEditor.Coordinator(document: document, controller: controller)
        view.delegate = coordinator

        controller.replaceAll([NSRange(location: 3, length: 4)], with: "XX")
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        XCTAssertEqual(view.string, "012XX789")
        XCTAssertEqual(document.metadata.comments[0].location, 3)
        XCTAssertEqual(document.metadata.comments[0].length, 2)

        undo.undo()
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        XCTAssertEqual(view.string, "0123456789")
        XCTAssertEqual(document.metadata.comments[0].location, 3)
        XCTAssertEqual(document.metadata.comments[0].length, 4)

        undo.redo()
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        XCTAssertEqual(view.string, "012XX789")
        XCTAssertEqual(document.metadata.comments[0].location, 3)
        XCTAssertEqual(document.metadata.comments[0].length, 2)
    }

    func testAddingAndEditingCommentsDoesNotCreateTrackedTextRevisions() throws {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "tracked phrase"))
        document.metadata.trackChangesEnabled = true
        let controller = EditorController()
        let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        view.textStorage?.setAttributedString(document.text)
        controller.attach(view)
        controller.updateSelection(NSRange(location: 0, length: 7))

        let comment = try controller.addComment(text: "Review wording", to: document)
        try controller.editComment(id: comment.id, text: "Revised comment", in: document)
        XCTAssertTrue(TrackChanges.records(in: document.text).isEmpty)
        XCTAssertEqual(document.metadata.comments.first?.text, "Revised comment")

        document.replaceEditedText(with: NSAttributedString(string: "new tracked phrase"))
        // Insertion at the beginning edge joins the inclusive annotated range.
        XCTAssertEqual(document.metadata.comments.first?.location, 0)
        XCTAssertEqual(document.metadata.comments.first?.length, 11)
        XCTAssertTrue(TrackChanges.records(in: document.text).isEmpty)
    }

    func testDOCXCommentsRoundTripWithOverlapsSpecialTextFootnotesEndnotesAndRevisions() throws {
        let text = NSMutableAttributedString(string: "Alpha Beta\nGamma")
        text.addAttribute(.boldWriterTrackChange, value: TrackChanges.marker(kind: .insertion, author: "Tracked Author", date: Date(timeIntervalSince1970: 1_700_000_100)), range: NSRange(location: 6, length: 4))
        text.append(Footnotes.marker(Footnote(text: "Footnote body", location: 0, length: 0), number: 1))
        text.append(Endnotes.marker(Endnote(text: "Endnote body", location: 0, length: 0), number: 1))
        let comments = [
            DocumentComment(text: "Special & <quoted>\nsecond line", author: "Author One", location: 0, length: 10, createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
            DocumentComment(text: "Overlapping note", author: "Author Two", location: 6, length: 6, createdAt: Date(timeIntervalSince1970: 1_700_000_050)),
            DocumentComment(text: "Nearby", author: "Author Three", location: 11, length: 5)
        ]

        let imported = try roundTrip(text, comments: comments)
        XCTAssertEqual(imported.metadata.comments.map(\.text), comments.map(\.text))
        XCTAssertEqual(imported.metadata.comments.map(\.author), comments.map(\.author))
        XCTAssertEqual(imported.metadata.comments.map(\.location), comments.map(\.location))
        XCTAssertEqual(imported.metadata.comments.map(\.length), comments.map(\.length))
        XCTAssertEqual(imported.metadata.comments[0].createdAt.timeIntervalSince1970, 1_700_000_000, accuracy: 1)
        XCTAssertEqual(try Footnotes.records(in: imported.text).map(\.text), ["Footnote body"])
        XCTAssertEqual(try Endnotes.records(in: imported.text).map(\.text), ["Endnote body"])
        XCTAssertFalse(TrackChanges.records(in: imported.text).isEmpty)

        let again = try roundTrip(imported.text, comments: imported.metadata.comments)
        XCTAssertEqual(again.metadata.comments.map(\.text), comments.map(\.text))
        XCTAssertEqual(try Footnotes.records(in: again.text).count, 1)
        XCTAssertEqual(try Endnotes.records(in: again.text).count, 1)
        XCTAssertFalse(TrackChanges.records(in: again.text).isEmpty)
    }

    func testDOCXCommentsInsideTablesRoundTripWithCellText() throws {
        var table = try WriterTable(rows: 1, columns: 1)
        table.cells[0][0] = NSAttributedString(string: "Commented cell text")
        let text = NSMutableAttributedString(string: "Before\n")
        text.append(try Tables.rendered(table))
        let cellRange = (text.string as NSString).range(of: "Commented cell text")
        let comment = DocumentComment(text: "Cell review", author: "Table Reviewer", location: cellRange.location, length: cellRange.length)

        let imported = try roundTrip(text, comments: [comment])
        XCTAssertEqual(try XCTUnwrap(Tables.models(in: imported.text).first).cells[0][0].string, "Commented cell text")
        XCTAssertEqual(imported.metadata.comments.first?.text, "Cell review")
        XCTAssertEqual(imported.text.attributedSubstring(from: NSRange(location: imported.metadata.comments[0].location, length: imported.metadata.comments[0].length)).string, "Commented cell text")
    }

    func testIndependentWordCommentFixtureImportsAndExportsAgain() throws {
        let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let parts = [
            "[Content_Types].xml": "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/comments.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml\"/></Types>",
            "_rels/.rels": "<Relationships xmlns=\"\(rel)\"><Relationship Id=\"main\" Type=\"\(rel)/officeDocument\" Target=\"word/document.xml\"/></Relationships>",
            "word/_rels/document.xml.rels": "<Relationships xmlns=\"\(rel)\"><Relationship Id=\"comments\" Type=\"\(rel)/comments\" Target=\"comments.xml\"/></Relationships>",
            "word/document.xml": "<w:document xmlns:w=\"\(w)\"><w:body><w:p><w:r><w:t>Before</w:t></w:r><w:commentRangeStart w:id=\"7\"/><w:r><w:t>reviewed</w:t></w:r><w:commentRangeEnd w:id=\"7\"/><w:r><w:commentReference w:id=\"7\"/></w:r><w:r><w:t>After</w:t></w:r></w:p></w:body></w:document>",
            "word/comments.xml": "<w:comments xmlns:w=\"\(w)\"><w:comment w:id=\"7\" w:author=\"Word Author\" w:date=\"2023-11-14T22:13:20Z\"><w:p><w:r><w:t>Fix &amp; polish</w:t></w:r></w:p><w:p><w:r><w:t>Second line</w:t></w:r></w:p></w:comment></w:comments>"
        ]
        let data = ZipArchiveWriter.archive(parts.map { ZipEntry(path: $0.key, data: Data($0.value.utf8)) })
        let fixture = FileWrapper(regularFileWithContents: data)
        fixture.preferredFilename = "Word fixture.docx"
        let imported = try BOLDWriterDocument(fileWrapper: fixture, contentType: .docx)
        XCTAssertEqual(imported.text.string, "BeforereviewedAfter")
        let comment = try XCTUnwrap(imported.metadata.comments.first)
        XCTAssertEqual(comment.author, "Word Author")
        XCTAssertEqual(comment.text, "Fix & polish\nSecond line")
        XCTAssertEqual(comment.location, 6)
        XCTAssertEqual(comment.length, 8)

        let output = try DOCXExporter.data(from: imported.text, title: "Re-exported", comments: imported.metadata.comments)
        let outputParts = Dictionary(uniqueKeysWithValues: try DOCXPackage.entries(in: output).map { ($0.path, $0.data) })
        let commentsXML = try DOCXPackage.xml(XCTUnwrap(outputParts["word/comments.xml"]))
        XCTAssertEqual(try commentsXML.nodes(forXPath: "//*[local-name()='comment']").count, 1)
        XCTAssertTrue(try XCTUnwrap(commentsXML.rootElement()).stringValue?.contains("Second line") == true)
        let reparsed = try DOCXImporter.importedDocument(from: output)
        XCTAssertEqual(reparsed.comments.first?.text, "Fix & polish\nSecond line")
        XCTAssertEqual(reparsed.comments.first?.location, 6)
        XCTAssertEqual(reparsed.comments.first?.length, 8)
    }

    func testCommentsStayAnchoredWhenNearbyTrackedRevisionsAreAcceptedOrRejected() throws {
        for accept in [true, false] {
            let document = BOLDWriterDocument()
            document.replaceText(with: NSAttributedString(string: "old keep"))
            document.metadata.comments = [DocumentComment(text: "Keep this", location: 4, length: 4)]
            let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
            view.textStorage?.setAttributedString(document.text)
            view.allowsUndo = true
            let controller = EditorController()
            controller.attach(view)

            XCTAssertTrue(controller.trackTextEdit(range: NSRange(location: 0, length: 3), replacement: NSAttributedString(string: "new")))
            XCTAssertFalse(TrackChanges.records(in: view.attributedString()).isEmpty)
            document.replaceEditedText(with: view.attributedString())
            if accept { controller.acceptAllTrackedChanges() } else { controller.rejectAllTrackedChanges() }
            document.replaceEditedText(with: view.attributedString())

            XCTAssertEqual(view.string, accept ? "new keep" : "old keep")
            XCTAssertTrue(TrackChanges.records(in: view.attributedString()).isEmpty)
            XCTAssertEqual(document.metadata.comments.first?.location, 4)
            XCTAssertEqual(document.metadata.comments.first?.length, 4)
            XCTAssertNoThrow(try DocumentComments.validate(document.metadata.comments, textLength: view.string.utf16.count))
        }
    }

    func testMalformedDOCXCommentStructuresFailWithoutTextLoss() throws {
        let text = NSAttributedString(string: "Commented")
        let comment = DocumentComment(text: "Note", location: 0, length: 9)
        let base = try DOCXExporter.data(from: text, title: "Malformed", comments: [comment])

        func mutate(_ edit: (inout [ZipEntry]) throws -> Void) throws -> Data {
            var entries = try DOCXPackage.entries(in: base)
            try edit(&entries)
            return ZipArchiveWriter.archive(entries)
        }
        func xml(_ entries: inout [ZipEntry], path: String) throws -> XMLDocument {
            let index = try XCTUnwrap(entries.firstIndex { $0.path == path })
            return try DOCXPackage.xml(entries[index].data)
        }
        func save(_ document: XMLDocument, into entries: inout [ZipEntry], path: String) throws {
            let index = try XCTUnwrap(entries.firstIndex { $0.path == path })
            entries[index].data = document.xmlData
        }
        func importData(_ data: Data) throws -> BOLDWriterDocument {
            let wrapper = FileWrapper(regularFileWithContents: data)
            wrapper.preferredFilename = "Malformed.docx"
            return try BOLDWriterDocument(fileWrapper: wrapper, contentType: .docx)
        }

        let malformedBody = try mutate { entries in
            let index = try XCTUnwrap(entries.firstIndex { $0.path == "word/comments.xml" })
            entries[index].data = Data("<w:comments".utf8)
        }
        XCTAssertThrowsError(try importData(malformedBody))

        let missingPart = try mutate { entries in entries.removeAll { $0.path == "word/comments.xml" } }
        XCTAssertThrowsError(try importData(missingPart))

        let danglingReference = try mutate { entries in
            let document = try xml(&entries, path: "word/document.xml")
            let reference = try XCTUnwrap(document.nodes(forXPath: "//*[local-name()='commentReference']").first as? XMLElement)
            reference.attributes?.first { $0.localName == "id" }?.stringValue = "99"
            try save(document, into: &entries, path: "word/document.xml")
        }
        XCTAssertThrowsError(try importData(danglingReference))

        let missingStart = try mutate { entries in
            let document = try xml(&entries, path: "word/document.xml")
            let node = try XCTUnwrap(document.nodes(forXPath: "//*[local-name()='commentRangeStart']").first as? XMLElement)
            node.detach()
            try save(document, into: &entries, path: "word/document.xml")
        }
        XCTAssertThrowsError(try importData(missingStart))

        let missingEnd = try mutate { entries in
            let document = try xml(&entries, path: "word/document.xml")
            let node = try XCTUnwrap(document.nodes(forXPath: "//*[local-name()='commentRangeEnd']").first as? XMLElement)
            node.detach()
            try save(document, into: &entries, path: "word/document.xml")
        }
        XCTAssertThrowsError(try importData(missingEnd))

        let twoComments = try DOCXExporter.data(from: text, title: "Duplicate IDs", comments: [
            comment,
            DocumentComment(text: "Second", location: 1, length: 2)
        ])
        let duplicateDefinitions = try DOCXPackage.entries(in: twoComments).map { entry -> ZipEntry in
            guard entry.path == "word/comments.xml" else { return entry }
            let document = try DOCXPackage.xml(entry.data)
            let definitions = try document.nodes(forXPath: "//*[local-name()='comment']").compactMap { $0 as? XMLElement }
            for definition in definitions { definition.attributes?.first { $0.localName == "id" }?.stringValue = "0" }
            return ZipEntry(path: entry.path, data: document.xmlData)
        }
        XCTAssertThrowsError(try importData(ZipArchiveWriter.archive(duplicateDefinitions)))

        let noComments = try DOCXExporter.data(from: text, title: "No Comments")
        let noPart = try DOCXPackage.entries(in: noComments).filter { $0.path != "word/comments.xml" }
        XCTAssertTrue(try importData(ZipArchiveWriter.archive(noPart)).metadata.comments.isEmpty)
    }
}
