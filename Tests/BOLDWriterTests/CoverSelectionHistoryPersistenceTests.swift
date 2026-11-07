import XCTest
@testable import BOLDWriter

final class CoverSelectionHistoryPersistenceTests: XCTestCase {
    func testSelectSubjectUsesExistingTransparentArtworkAlpha() throws {
        let transparent = try CoverEditorEngine.transparentImage(width: 32, height: 32)
        let subject = try CoverEditorEngine.paint(
            imageData: transparent,
            points: [CGPoint(x: 16, y: 16)],
            color: .systemGreen,
            diameter: 14
        )

        let result = try CoverEditorEngine.selectSubject(imageData: subject)

        XCTAssertEqual(result.width, 32)
        XCTAssertEqual(result.height, 32)
        XCTAssertGreaterThan(result.mask[16 * 32 + 16], 240)
        XCTAssertEqual(result.mask[0], 0)
        XCTAssertGreaterThan(result.mask.filter { $0 > 0 }.count, 0)
        XCTAssertLessThan(result.mask.filter { $0 > 0 }.count, result.mask.count)
    }

    func testActiveSelectionUndoRedoAndNativeRoundTrip() throws {
        var project = CoverProject(width: 1, height: 1)
        let layerID = UUID()
        let before = Data(repeating: 0, count: 64)
        let selected = Data((0..<64).map { $0 % 8 < 4 ? UInt8(255) : 0 })
        project.editorActiveSelectionMask = before
        project.editorActiveSelectionLayerID = layerID

        var undo = [project]
        var redo: [CoverProject] = []
        project.editorActiveSelectionMask = selected

        CoverProjectHistory.undo(project: &project, undo: &undo, redo: &redo)
        XCTAssertEqual(project.editorActiveSelectionMask, before)
        XCTAssertEqual(project.editorActiveSelectionLayerID, layerID)

        CoverProjectHistory.redo(project: &project, undo: &undo, redo: &redo)
        XCTAssertEqual(project.editorActiveSelectionMask, selected)

        let reopened = try JSONDecoder().decode(
            CoverProject.self,
            from: JSONEncoder().encode(project)
        )
        XCTAssertEqual(reopened.editorActiveSelectionMask, selected)
        XCTAssertEqual(reopened.editorActiveSelectionLayerID, layerID)
    }

    func testOlderCoverPayloadDecodesWithoutEditorSelectionFields() throws {
        let data = try JSONEncoder().encode(CoverProject(width: 1, height: 1))
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        payload.removeValue(forKey: "editorActiveSelectionMask")
        payload.removeValue(forKey: "editorActiveSelectionLayerID")
        payload.removeValue(forKey: "editorDismissedSelectionMask")
        payload.removeValue(forKey: "editorDismissedSelectionLayerID")

        let legacyData = try JSONSerialization.data(withJSONObject: payload)
        let reopened = try JSONDecoder().decode(CoverProject.self, from: legacyData)
        XCTAssertNil(reopened.editorActiveSelectionMask)
        XCTAssertNil(reopened.editorActiveSelectionLayerID)
        XCTAssertNil(reopened.editorDismissedSelectionMask)
        XCTAssertNil(reopened.editorDismissedSelectionLayerID)
    }
}
