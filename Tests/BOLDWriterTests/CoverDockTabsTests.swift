import XCTest
@testable import BOLDWriter

final class CoverDockTabsTests: XCTestCase {
    func testCompleteCoverToolSurfaceIsAlwaysDiscoverable() {
        let workspace = CoverWorkspaceState()

        XCTAssertEqual(
            workspace.availableDockTabs,
            CoverDockTab.allCases
        )

        XCTAssertTrue(
            workspace.availableDockTabs.contains(.history)
        )
        XCTAssertTrue(
            workspace.availableDockTabs.contains(.swatches)
        )
        XCTAssertTrue(
            workspace.availableDockTabs.contains(.layers)
        )
        XCTAssertTrue(
            workspace.availableDockTabs.contains(.paths)
        )
        XCTAssertTrue(
            workspace.availableDockTabs.contains(.properties)
        )
        XCTAssertTrue(
            workspace.availableDockTabs.contains(.character)
        )
        XCTAssertTrue(
            workspace.availableDockTabs.contains(.paragraph)
        )
        XCTAssertTrue(
            workspace.availableDockTabs.contains(.adjustments)
        )
        XCTAssertTrue(
            workspace.availableDockTabs.contains(.channels)
        )
    }

    func testLegacyWorkspaceDefaultsRemainCompatible() {
        let workspace = CoverWorkspaceState()

        XCTAssertTrue(workspace.toolbar)
        XCTAssertTrue(workspace.rightDock)
        XCTAssertTrue(workspace.layers)
        XCTAssertTrue(workspace.paths)
        XCTAssertTrue(workspace.properties)
        XCTAssertTrue(workspace.adjustments)
        XCTAssertTrue(workspace.historyAndSwatches)

        XCTAssertFalse(workspace.character)
        XCTAssertFalse(workspace.paragraph)
        XCTAssertFalse(workspace.channels)
    }

    func testSelectingHiddenTabCanRevealItWithoutChangingDocumentData() {
        var workspace = CoverWorkspaceState()

        XCTAssertFalse(
            workspace.isDockTabVisible(.character)
        )

        workspace.revealDockTab(.character)

        XCTAssertTrue(workspace.rightDock)
        XCTAssertTrue(
            workspace.isDockTabVisible(.character)
        )
    }

    func testHistoryAndSwatchesKeepSharedWindowVisibility() {
        var workspace = CoverWorkspaceState()

        workspace.setDockTabVisible(.history,false)

        XCTAssertFalse(
            workspace.isDockTabVisible(.history)
        )
        XCTAssertFalse(
            workspace.isDockTabVisible(.swatches)
        )

        workspace.revealDockTab(.swatches)

        XCTAssertTrue(
            workspace.isDockTabVisible(.history)
        )
        XCTAssertTrue(
            workspace.isDockTabVisible(.swatches)
        )
    }

    func testShowAllDockPanelsEnablesEveryPanel() {
        var workspace = CoverWorkspaceState()

        workspace.rightDock=false
        workspace.layers=false
        workspace.paths=false
        workspace.properties=false
        workspace.character=false
        workspace.paragraph=false
        workspace.adjustments=false
        workspace.channels=false
        workspace.historyAndSwatches=false

        XCTAssertFalse(workspace.hasPanels)

        workspace.showAllDockPanels()

        XCTAssertTrue(workspace.rightDock)

        for tab in CoverDockTab.allCases {
            XCTAssertTrue(
                workspace.isDockTabVisible(tab),
                "\(tab.title) should be visible"
            )
        }
    }
}
