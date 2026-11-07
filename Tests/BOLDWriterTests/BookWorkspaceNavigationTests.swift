import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class BookWorkspaceNavigationTests: XCTestCase {
    func testDirectWorkspaceTransitionsKeepTheSameDocument() {
        let transitions: [(BookWorkspace, BookWorkspace)] = [
            (.manuscript, .coverCreator),
            (.manuscript, .bookStudio3D),
            (.manuscript, .automationStudio),
            (.coverCreator, .manuscript),
            (.coverCreator, .bookStudio3D),
            (.coverCreator, .automationStudio),
            (.bookStudio3D, .manuscript),
            (.bookStudio3D, .coverCreator),
            (.bookStudio3D, .automationStudio),
            (.automationStudio, .manuscript),
            (.automationStudio, .coverCreator),
            (.automationStudio, .bookStudio3D)
        ]
        for (source, target) in transitions {
            let document = BOLDWriterDocument()
            var navigation = BookWorkspaceNavigation(document: document)
            navigation.open(source)
            navigation.open(target)
            XCTAssertEqual(navigation.active, target)
            XCTAssertTrue(navigation.document === document)
        }
    }

    func testVisitedWorkspacesRemainAvailableAfterSwitchingAway() {
        var navigation = BookWorkspaceNavigation(document: BOLDWriterDocument())
        XCTAssertFalse(navigation.hasVisitedCover)
        XCTAssertFalse(navigation.hasVisitedStudio)
        XCTAssertFalse(navigation.hasVisitedAutomation)
        navigation.open(.coverCreator)
        navigation.open(.bookStudio3D)
        navigation.open(.manuscript)
        navigation.open(.automationStudio)
        XCTAssertTrue(navigation.hasVisitedCover)
        XCTAssertTrue(navigation.hasVisitedStudio)
        XCTAssertTrue(navigation.hasVisitedAutomation)
    }

    func testManuscriptStateIsUntouchedByWorkspaceNavigation() {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "A manuscript in progress."))
        let revision = document.revisionID
        var navigation = BookWorkspaceNavigation(document: document)
        navigation.open(.coverCreator)
        navigation.open(.bookStudio3D)
        navigation.open(.manuscript)
        XCTAssertEqual(document.text.string, "A manuscript in progress.")
        XCTAssertEqual(document.revisionID, revision)
    }

    func testCoverEditsReachTheStudioWithoutASecondProjectModel() {
        let document = BOLDWriterDocument()
        var navigation = BookWorkspaceNavigation(document: document)
        var cover = CoverProject(type: .printFullWrap, width: 12.8, height: 9)
        cover.trimWidth = 6
        cover.trimHeight = 9
        cover.backWidth = 6
        cover.spineWidth = 0.8
        navigation.open(.coverCreator)
        navigation.saveCoverProjects([cover], activeID: cover.id)
        let before = BookPreviewScene.coverTextures(project: cover, workingLayers: false, revisionID: document.revisionID)
        cover.backgroundHex = "#224466"
        navigation.saveCoverProjects([cover], activeID: cover.id)
        navigation.open(.bookStudio3D)
        let studioCover = document.metadata.coverProjects?.first
        XCTAssertEqual(studioCover, cover)
        XCTAssertEqual(document.metadata.activeCoverProjectID, cover.id)
        let after = BookPreviewScene.coverTextures(project: cover, workingLayers: false, revisionID: document.revisionID)
        XCTAssertFalse(before === after)
        XCTAssertTrue(navigation.document === document)
    }

    func testManuscriptChangeInvalidatesTheStudiosPageSourceRevision() {
        let document = BOLDWriterDocument()
        var navigation = BookWorkspaceNavigation(document: document)
        navigation.open(.bookStudio3D)
        let before = document.revisionID
        navigation.open(.manuscript)
        document.replaceText(with: NSAttributedString(string: "New chapter and more pages."))
        navigation.open(.bookStudio3D)
        XCTAssertNotEqual(document.revisionID, before)
        XCTAssertEqual(navigation.document.text.string, "New chapter and more pages.")
    }

    func testStudioPresentationPersistsWithoutChangingProductionContent() {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "Chapter One"))
        let cover = CoverProject(type: .printFullWrap, width: 12.8, height: 9)
        document.metadata.coverProjects = [cover]
        var navigation = BookWorkspaceNavigation(document: document)
        navigation.open(.bookStudio3D)
        var presentation = BookStudioPresentation()
        presentation.environment = .warm
        presentation.finish = .gloss
        presentation.spreadIndex = 3
        document.metadata.bookStudioPresentation = presentation
        navigation.open(.coverCreator)
        navigation.open(.bookStudio3D)
        XCTAssertEqual(document.metadata.bookStudioPresentation, presentation)
        XCTAssertEqual(document.text.string, "Chapter One")
        XCTAssertEqual(document.metadata.coverProjects, [cover])
    }

    func testStudioSelectsTheRequestedExistingCoverOrFallsBackToPrintWrap() {
        let document = BOLDWriterDocument()
        let ebook = CoverProject(type: .ebookFront)
        let wrap = CoverProject(type: .printFullWrap)
        document.metadata.coverProjects = [ebook, wrap]
        let navigation = BookWorkspaceNavigation(document: document)
        navigation.selectCoverProject(toEdit: ebook.id)
        XCTAssertEqual(document.metadata.activeCoverProjectID, ebook.id)
        navigation.selectCoverProject(toEdit: UUID())
        XCTAssertEqual(document.metadata.activeCoverProjectID, wrap.id)
    }
}
