import XCTest
@testable import BOLDWriter

final class CoverPathsPanelTests: XCTestCase {
    func testPanelReturnsOnlyPathLayersTopmostFirst() {
        var project = CoverProject()

        let bottom = CoverLayer(
            kind:.path,
            name:"Bottom Path"
        )

        let artwork = CoverLayer(
            kind:.image,
            name:"Artwork"
        )

        let top = CoverLayer(
            kind:.path,
            name:"Top Path"
        )

        project.layers = [
            bottom,
            artwork,
            top
        ]

        let paths = CoverPathPanelModel.layers(
            in:project
        )

        XCTAssertEqual(
            paths.map(\.id),
            [
                top.id,
                bottom.id
            ]
        )
    }

    func testPanelReportsAnchorCountAndOpenClosedState() {
        var layer = CoverLayer(
            kind:.path,
            name:"Curve"
        )

        layer.pathPoints = [
            CoverPathPoint(
                x:0.1,
                y:0.2
            ),
            CoverPathPoint(
                x:0.5,
                y:0.8
            )
        ]

        layer.pathClosed = false

        XCTAssertEqual(
            CoverPathPanelModel.anchorCount(
                for:layer
            ),
            2
        )

        XCTAssertFalse(
            CoverPathPanelModel.isClosed(
                layer
            )
        )

        XCTAssertEqual(
            CoverPathPanelModel.status(
                for:layer
            ),
            "Open"
        )

        layer.pathClosed = true

        XCTAssertTrue(
            CoverPathPanelModel.isClosed(
                layer
            )
        )

        XCTAssertEqual(
            CoverPathPanelModel.status(
                for:layer
            ),
            "Closed"
        )
    }

    func testLegacyPathWithoutPathClosedUsesRendererCompatibleStatus() {
        var layer = CoverLayer(
            kind:.path,
            name:"Legacy"
        )

        layer.pathPoints = [
            CoverPathPoint(x:0,y:0),
            CoverPathPoint(x:1,y:0),
            CoverPathPoint(x:1,y:1)
        ]

        layer.pathClosed = nil

        XCTAssertTrue(
            CoverPathPanelModel.isClosed(
                layer
            )
        )

        XCTAssertEqual(
            CoverPathPanelModel.status(
                for:layer
            ),
            "Closed"
        )
    }

    func testNextPathNameCountsOnlyPathLayers() {
        var project = CoverProject()

        project.layers = [
            CoverLayer(
                kind:.image,
                name:"Artwork"
            ),
            CoverLayer(
                kind:.path,
                name:"Existing Path"
            ),
            CoverLayer(
                kind:.text,
                name:"Title"
            ),
            CoverLayer(
                kind:.path,
                name:"Another Path"
            )
        ]

        XCTAssertEqual(
            CoverPathPanelModel.nextPathName(
                in:project
            ),
            "Path 3"
        )
    }

    func testPathsVisibilityParticipatesInPanelAvailability() {
        var workspace = CoverWorkspaceState()

        workspace.layers = false
        workspace.properties = false
        workspace.adjustments = false
        workspace.historyAndSwatches = false
        workspace.paths = true

        XCTAssertTrue(
            workspace.hasPanels
        )

        workspace.paths = false

        XCTAssertFalse(
            workspace.hasPanels
        )
    }
}
