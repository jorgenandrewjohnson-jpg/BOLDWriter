import AppKit
import XCTest
@testable import BOLDWriter

final class CoverArtworkPackageAssetTests: XCTestCase {
    private let pixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lXcAAAAASUVORK5CYII=")!

    func testRepeatedCoverArtworkIsStoredOnceAndReopenedByteForByte() throws {
        var first = CoverProject(type: .printFullWrap, width: 4, height: 3)
        var photo = CoverLayer(kind: .image, name: "Original photo")
        photo.imageData = pixelPNG
        first.layers = [photo]
        var second = first
        second.id = UUID()
        second.name = "Paperback production copy"
        second.layers[0].id = UUID()

        let document = BOLDWriterDocument()
        document.metadata.coverProjects = [first, second]
        let sourceProjects = document.metadata.coverProjects
        let package = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let children = try XCTUnwrap(package.fileWrappers)
        let storedMetadataData = try XCTUnwrap(children["metadata.json"]?.regularFileContents)
        let storedMetadata = try JSONDecoder().decode(DocumentMetadata.self, from: storedMetadataData)
        XCTAssertNil(storedMetadata.coverProjects?[0].layers[0].imageData)
        XCTAssertNil(storedMetadata.coverProjects?[1].layers[0].imageData)

        let indexData = try XCTUnwrap(children["cover-artwork-index.json"]?.regularFileContents)
        let indexObject = try XCTUnwrap(JSONSerialization.jsonObject(with: indexData) as? [String: Any])
        let references = try XCTUnwrap(indexObject["references"] as? [[String: Any]])
        XCTAssertEqual(references.count, 2)
        let assetFiles = try XCTUnwrap(children["cover-artwork"]?.fileWrappers)
        XCTAssertEqual(assetFiles.count, 1, "Identical layer data across editable cover projects should occupy one package asset")
        XCTAssertEqual(assetFiles.values.first?.regularFileContents, pixelPNG)

        let reopened = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
        XCTAssertEqual(reopened.metadata.coverProjects, sourceProjects)
        XCTAssertEqual(reopened.metadata.coverProjects?[0].layers[0].imageData, pixelPNG)
        XCTAssertEqual(reopened.metadata.coverProjects?[1].layers[0].imageData, pixelPNG)
        XCTAssertEqual(document.metadata.coverProjects, sourceProjects, "Packaging must not mutate the live editable projects")
    }

    func testCorruptExternalArtworkAssetFailsInsteadOfSilentlyDroppingPhoto() throws {
        var project = CoverProject(type: .printFullWrap, width: 4, height: 3)
        var photo = CoverLayer(kind: .image, name: "Original photo")
        photo.imageData = pixelPNG
        project.layers = [photo]
        let document = BOLDWriterDocument()
        document.metadata.coverProjects = [project]
        let package = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let children = try XCTUnwrap(package.fileWrappers)
        let assetName = try XCTUnwrap(children["cover-artwork"]?.fileWrappers?.keys.first)
        let corruptAssets = FileWrapper(directoryWithFileWrappers: [
            assetName: FileWrapper(regularFileWithContents: Data("truncated".utf8))
        ])
        var corruptChildren = children
        corruptChildren["cover-artwork"] = corruptAssets
        let corrupted = FileWrapper(directoryWithFileWrappers: corruptChildren)
        XCTAssertThrowsError(try BOLDWriterDocument(fileWrapper: corrupted, contentType: .boldWriterDocument))
    }
}
