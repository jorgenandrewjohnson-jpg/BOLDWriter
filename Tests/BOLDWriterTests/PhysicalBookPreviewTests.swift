import XCTest
import AppKit
import PDFKit
import SceneKit
@testable import BOLDWriter

final class PhysicalBookPreviewTests: XCTestCase {
    func testPhysicalDimensionsAndAuthoritativePanelMapping() throws {
        var project = CoverProject(type: .printFullWrap, width: 13.49986, height: 9.25)
        project.name = "Acceptance"; project.trimWidth = 6; project.backWidth = 6; project.trimHeight = 9
        project.spineWidth = 1.24986; project.bleed = 0.125
        let size = try XCTUnwrap(try? CoverCalculator.fullWrap(backWidth: 6, frontWidth: 6, trimHeight: 9, spineWidth: project.spineWidth, bleed: project.bleed))
        project.canvasWidth = size.totalWidthInches; project.canvasHeight = size.totalHeightInches
        let geometry = PhysicalBookGeometry(project: project)
        XCTAssertEqual(geometry.closedBook.width, 6)
        XCTAssertEqual(geometry.closedBook.height, 9)
        XCTAssertEqual(
            geometry.pageBlock.depth,
            project.spineWidth,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            geometry.closedBook.depth,
            project.spineWidth + 2 * geometry.coverBoardThickness,
            accuracy: 0.000001
        )
        XCTAssertEqual(geometry.pageBlock.depth + 2 * geometry.coverBoardThickness, geometry.closedBook.depth, accuracy: 0.000001)
        let closed = geometry.closedFrontCoverCenter
        let hinge = geometry.frontCoverHinge
        XCTAssertEqual(closed.x, 3, accuracy: 0.000001)
        XCTAssertEqual(hinge.x, 0, accuracy: 0.000001)
        let opened = geometry.openedFrontCoverCenter(angleDegrees: 90)
        XCTAssertEqual(opened.x, 0, accuracy: 0.000001)
        XCTAssertEqual(opened.y, 3, accuracy: 0.000001)
        XCTAssertEqual(geometry.fullWrapDimensions.totalWidthInches, 13.49986, accuracy: 0.000001)
        XCTAssertEqual(geometry.fullWrapDimensions.totalHeightInches, 9.25, accuracy: 0.000001)
        XCTAssertEqual(geometry.panelMapping.back, CoverWrapGeometry(project: project).backTrim)
        XCTAssertEqual(geometry.panelMapping.spine, CoverWrapGeometry(project: project).spineTrim)
        XCTAssertEqual(geometry.panelMapping.front, CoverWrapGeometry(project: project).frontTrim)
        XCTAssertEqual(PhysicalBookGeometry.expectedSpine(pageCount: 555, caliper: 0.002252)!, 1.24986, accuracy: 0.000001)
    }

    func testCoverOverhangMatchesBindingAndPaperTrim() throws {
        var project = CoverProject(type: .printFullWrap)
        project.trimWidth = 6
        project.trimHeight = 9
        project.spineWidth = 1.2
        let dimensions = PhysicalBookGeometry(project: project)
        XCTAssertEqual(dimensions.coverOverhang(for: .softcover), 0)
        XCTAssertEqual(dimensions.coverOverhang(for: .hardcover), 2.5 / 25.4, accuracy: 0.000001)

        for binding in BookBinding.allCases {
            let scene = BookPreviewScene.make(
                project: project, workingLayers: false, open: false, angle: 0,
                leftPage: nil, rightPage: 1, pageCount: 20, spreadIndex: 0,
                leftTexture: nil, rightTexture: nil, margins: false, thumbMode: .off,
                leftPageSettings: PageSettings(), rightPageSettings: PageSettings(),
                preset: .perspective, revisionID: UUID(), binding: binding
            )
            let cover = try XCTUnwrap(scene.rootNode.childNode(withName: "book-shell.front-cover", recursively: true))
            let paper = try XCTUnwrap(scene.rootNode.childNode(withName: "book.closed-page-block", recursively: true))
            let paperWidth = try XCTUnwrap(paper.geometry as? SCNBox).width
            let coverWidth = (cover.geometry as? SCNBox)?.width
                ?? cover.boundingBox.max.x - cover.boundingBox.min.x
            XCTAssertEqual(paperWidth, CGFloat(6 * 0.7), accuracy: 0.0001)
            XCTAssertEqual(coverWidth - paperWidth,
                           CGFloat(2 * dimensions.coverOverhang(for: binding) * 0.7), accuracy: 0.0001)
            if binding == .hardcover {
                let facingPlanes = cover.childNodes.compactMap { $0.geometry as? SCNPlane }
                    .filter { $0.width > paperWidth / 2 }
                XCTAssertEqual(facingPlanes.count, 2)
                for plane in facingPlanes {
                    XCTAssertEqual(plane.width, coverWidth, accuracy: 0.0001)
                    XCTAssertEqual(plane.height,
                                   CGFloat((9 + 2 * dimensions.coverVerticalOverhang(for: binding)) * 0.7), accuracy: 0.0001)
                }
            }
        }
    }

    func testPageCountAndSpineDiagnosticsAreDeterministic() {
        XCTAssertNil(PhysicalBookDiagnostics.pageCountMessage(coverPages: 555, manuscriptPages: 555))
        XCTAssertEqual(PhysicalBookDiagnostics.pageCountMessage(coverPages: 555, manuscriptPages: 560), "Cover spine is based on 555 pages; manuscript currently has 560 pages.")
        var project = CoverProject(type: .printFullWrap)
        project.spinePageCount = 555; project.spineCaliperInches = 0.002252; project.spineWidth = 555 * 0.002252
        XCTAssertNil(PhysicalBookDiagnostics.expectedSpineMismatch(project: project, manuscriptPages: 555))
        XCTAssertEqual(PhysicalBookDiagnostics.expectedSpineMismatch(project: project, manuscriptPages: 560)!, 5 * 0.002252, accuracy: 0.000001)
    }

    func testTrimMismatchAndMatch() {
        var project = CoverProject(type: .printFullWrap)
        project.trimWidth = 6; project.trimHeight = 9
        var page = PageSettings(); page.paper = .custom; page.customPaperSize = CGSize(width: 432, height: 648)
        XCTAssertTrue(PhysicalBookDiagnostics.trimMatches(project: project, page: page))
        page.landscape = true
        XCTAssertFalse(PhysicalBookDiagnostics.trimMatches(project: project, page: page))
        project.trimWidth = 9; project.trimHeight = 6
        XCTAssertTrue(PhysicalBookDiagnostics.trimMatches(project: project, page: page))
        project.trimWidth = 6; project.trimHeight = 9
        page.landscape = false
        page.customPaperSize = CGSize(width: 612, height: 792)
        XCTAssertFalse(PhysicalBookDiagnostics.trimMatches(project: project, page: page))
    }

    func testPDFPaginationFlagsLandscapeSectionAgainstPortraitCover() throws {
        var project = CoverProject(type: .printFullWrap)
        project.trimWidth = 6
        project.trimHeight = 9

        var portrait = PageSettings()
        portrait.paper = .custom
        portrait.customPaperSize = CGSize(width: 432, height: 648)
        var landscape = portrait
        landscape.landscape = true

        let text = "Portrait section.\nLandscape section."
        let landscapeStart = (text as NSString).range(of: "Landscape").location
        let sections = [
            DocumentSection(location: 0, page: portrait),
            DocumentSection(location: landscapeStart, page: landscape)
        ]
        var layouts: [PageSettings] = []
        let data = try PDFExporter.data(
            from: NSAttributedString(string: text),
            settings: portrait,
            sections: sections,
            pageLayoutSink: { layouts = $0 }
        )
        let pdf = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertEqual(layouts.count, pdf.pageCount)
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertEqual(layouts.map(\.pageSize), [CGSize(width: 432, height: 648), CGSize(width: 648, height: 432)])
        XCTAssertEqual(PhysicalBookDiagnostics.trimMismatchPages(project: project, pages: layouts), [2])
    }

    func testPDFPaginationReportsTheExactPageLayoutsUsedForRendering() throws {
        var settings = PageSettings(); settings.paper = .custom; settings.customPaperSize = CGSize(width: 432, height: 648); settings.leftMargin = 54; settings.rightMargin = 72
        var layouts: [PageSettings] = []
        let data = try PDFExporter.data(from: NSAttributedString(string: "A rendered manuscript page."), settings: settings, pageLayoutSink: { layouts = $0 })
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(layouts.count, pdf.pageCount)
        XCTAssertEqual(layouts.first?.leftMargin, 54)
        XCTAssertEqual(layouts.first?.rightMargin, 72)
    }

    func testManuscriptPageRasterizationPreservesPDFMediaBoxContent() throws {
        let bounds = CGRect(x: 36, y: 54, width: 432, height: 648)
        let data = NSMutableData()
        var mediaBox = bounds
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: bounds.minX + 18, y: bounds.minY + 18, width: 72, height: 72))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: bounds.maxX - 90, y: bounds.maxY - 90, width: 72, height: 72))
        context.endPDFPage(); context.closePDF()

        let pdf = try XCTUnwrap(PDFDocument(data: data as Data))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let image = try XCTUnwrap(PhysicalBookPreview.renderManuscriptPage(page, maximumPixelSize: 600))
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        XCTAssertEqual(bitmap.pixelsWide, 400)
        XCTAssertEqual(bitmap.pixelsHigh, 600)
        XCTAssertEqual(image.size.width, CGFloat(bitmap.pixelsWide))
        XCTAssertEqual(image.size.height, CGFloat(bitmap.pixelsHigh))
        let upperRight = try XCTUnwrap(bitmap.colorAt(x: 355, y: 45))
        let lowerLeft = try XCTUnwrap(bitmap.colorAt(x: 45, y: 555))
        XCTAssertGreaterThan(upperRight.blueComponent, 0.8)
        XCTAssertGreaterThan(lowerLeft.redComponent, 0.8)
    }

    func testSpreadMappingCoversFirstMiddleFinalAndOddEvenPages() {
        XCTAssertEqual(PhysicalBookGeometry.spread(forPage: 1, pageCount: 5), BookSpread(index: 0, leftPage: nil, rightPage: 1))
        XCTAssertEqual(PhysicalBookGeometry.spread(at: 1, pageCount: 5), BookSpread(index: 1, leftPage: 2, rightPage: 3))
        XCTAssertEqual(PhysicalBookGeometry.spread(forPage: 4, pageCount: 5), BookSpread(index: 2, leftPage: 4, rightPage: 5))
        XCTAssertEqual(PhysicalBookGeometry.spread(at: 2, pageCount: 4), BookSpread(index: 2, leftPage: 4, rightPage: nil))
        XCTAssertEqual(PhysicalBookGeometry.spread(forPage: 560, pageCount: 560), BookSpread(index: 280, leftPage: 560, rightPage: nil))
        XCTAssertEqual(PhysicalBookGeometry.spread(at: 140, pageCount: 555), BookSpread(index: 140, leftPage: 280, rightPage: 281))
    }

    func testScenePageOriginsMatchVisualLeftAndRightSpreadSides() {
        let width = 4.2
        let left = PhysicalBookGeometry.scenePageOriginX(pageWidth: width, side: .left)
        let right = PhysicalBookGeometry.scenePageOriginX(pageWidth: width, side: .right)
        XCTAssertEqual(left, -width / 2)
        XCTAssertEqual(right, width / 2)
        XCTAssertEqual(left + width, right, accuracy: 0.000001)
    }

    func testPageStacksAndTurnDirectionsTrackSpreadProgression() throws {
        let initial = PhysicalBookGeometry.pageStacks(pageCount: 555, spreadIndex: 0, totalDepth: 1.2)
        XCTAssertEqual(initial.turnedPages, 0)
        XCTAssertEqual(initial.leftDepth, 0, accuracy: 0.000001)
        XCTAssertEqual(initial.rightDepth, 1.2, accuracy: 0.000001)
        let after = PhysicalBookGeometry.pageStacks(pageCount: 555, spreadIndex: 3, totalDepth: 1.2)
        XCTAssertEqual(after.turnedPages, 6)
        XCTAssertEqual(after.leftDepth, 1.2 * 6 / 555, accuracy: 0.000001)
        XCTAssertEqual(after.leftDepth + after.rightDepth, 1.2, accuracy: 0.000001)
        var bookProject = CoverProject(type: .printFullWrap)
        bookProject.spineWidth = 1.2
        let bookGeometry = PhysicalBookGeometry(project: bookProject)
        let initialRightTop = bookGeometry.stackCenterZ(side: .right, pageCount: 20, spreadIndex: 0, binding: .softcover) + bookGeometry.pageBlockDepth(for: .softcover) / 2
        let middleRightTop = bookGeometry.stackCenterZ(side: .right, pageCount: 20, spreadIndex: 5, binding: .softcover) + bookGeometry.pageBlockDepth(for: .softcover) / 4
        let middleLeftTop = bookGeometry.stackCenterZ(side: .left, pageCount: 20, spreadIndex: 5, binding: .softcover) + bookGeometry.pageBlockDepth(for: .softcover) / 4
        XCTAssertLessThan(middleRightTop, initialRightTop)
        XCTAssertEqual(middleLeftTop, middleRightTop, accuracy: 0.000001)
        XCTAssertEqual(PhysicalBookGeometry.pageTurnDirection(fromSpread: 2, toSpread: 3), .forward)
        XCTAssertEqual(PhysicalBookGeometry.pageTurnDirection(fromSpread: 3, toSpread: 2), .backward)
        XCTAssertNil(PhysicalBookGeometry.pageTurnDirection(fromSpread: 3, toSpread: 3))
        XCTAssertEqual(PhysicalBookGeometry.pageTurnRotation(direction: .forward), -.pi, accuracy: 0.000001)
        XCTAssertEqual(PhysicalBookGeometry.pageTurnRotation(direction: .backward), .pi, accuracy: 0.000001)
        XCTAssertEqual(PhysicalBookGeometry.pageTurnFaces(direction: .forward, fromSpread: 0, toSpread: 1, pageCount: 5),
                       BookPageTurnFaces(front: 1, reverse: 2))
        XCTAssertEqual(PhysicalBookGeometry.pageTurnFaces(direction: .backward, fromSpread: 1, toSpread: 0, pageCount: 5),
                       BookPageTurnFaces(front: 2, reverse: 1))
        XCTAssertEqual(PhysicalBookGeometry.pageStacks(pageCount: 5, spreadIndex: 99, totalDepth: 1).turnedPages, 5)

        var navigation = BookPageTurnState()
        let forward = try XCTUnwrap(navigation.begin(to: 1, maximumSpread: 20))
        XCTAssertEqual(forward.direction, .forward)
        XCTAssertEqual(navigation.spreadIndex, 1)
        XCTAssertNil(navigation.begin(to: 2, maximumSpread: 20), "navigation during an active turn is ignored")
        navigation.finish()
        let backward = try XCTUnwrap(navigation.begin(to: 0, maximumSpread: 20))
        XCTAssertEqual(backward.direction, .backward)
        XCTAssertEqual(navigation.spreadIndex, 0)
        navigation.finish()
        XCTAssertNil(navigation.activeTransition)
    }

    func testCoverTextureUVOrientationKeepsFrontArtworkUprightAfterSurfaceRotation() {
        XCTAssertEqual(BookTextureVerticalTransform.frontCover.apply(0), 0, accuracy: 0.000001)
        XCTAssertEqual(BookTextureVerticalTransform.frontCover.apply(1), 1, accuracy: 0.000001)
        XCTAssertEqual(BookTextureVerticalTransform.backCover.apply(0), 0, accuracy: 0.000001)
        XCTAssertEqual(BookTextureVerticalTransform.backCover.apply(1), 1, accuracy: 0.000001)
        XCTAssertEqual(BookTextureVerticalTransform.spine.apply(0.25), 0.25, accuracy: 0.000001)
    }

    func testFrontCoverHingeAndPageBlockRemainPhysicallyAligned() {
        var project = CoverProject(type: .printFullWrap)
        project.trimWidth = 6; project.trimHeight = 9; project.spineWidth = 1.25
        let geometry = PhysicalBookGeometry(project: project)
        let hinge = geometry.frontCoverHinge
        XCTAssertEqual(hinge.x, 0, accuracy: 0.000001)
        XCTAssertEqual(hinge.y, geometry.closedFrontCoverCenter.y, accuracy: 0.000001)
        XCTAssertEqual(geometry.pageBlock.depth + 2 * geometry.coverBoardThickness, geometry.closedBook.depth, accuracy: 0.000001)
        XCTAssertEqual(geometry.openedFrontCoverCenter(angleDegrees: 0).x, project.trimWidth / 2, accuracy: 0.000001)
        XCTAssertEqual(geometry.openedFrontCoverCenter(angleDegrees: 90).x, hinge.x, accuracy: 0.000001)
    }



    func testPhysicalCoverShellPersistsAcrossClosedAndOpenSceneStates() throws {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8

        let scenes =
            [false, true]
                .map { open in
                    BookPreviewScene.make(
                        project:
                            project,
                        workingLayers:
                            false,
                        open:
                            open,
                        angle:
                            open
                                ? 45
                                : 0,
                        leftPage:
                            2,
                        rightPage:
                            3,
                        pageCount:
                            20,
                        spreadIndex:
                            1,
                        leftTexture:
                            nil,
                        rightTexture:
                            nil,
                        margins:
                            false,
                        thumbMode:
                            .off,
                        leftPageSettings:
                            PageSettings(),
                        rightPageSettings:
                            PageSettings(),
                        preset:
                            .perspective,
                        revisionID:
                            UUID()
                    )
                }

        for scene in scenes {
            let book =
                try XCTUnwrap(
                    scene.rootNode.childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            XCTAssertNotNil(
                book.childNode(
                    withName:
                        "book-shell.front-cover",
                    recursively:
                        false
                )
            )

            XCTAssertNotNil(
                book.childNode(
                    withName:
                        "book-shell.back-cover",
                    recursively:
                        false
                )
            )

            XCTAssertNotNil(
                book.childNode(
                    withName:
                        "book-shell.spine",
                    recursively:
                        false
                )
            )
        }

        let closedBook =
            try XCTUnwrap(
                scenes[0]
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
            )

        let openBook =
            try XCTUnwrap(
                scenes[1]
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
            )

        let closedFront =
            try XCTUnwrap(
                closedBook.childNode(
                    withName:
                        "book-shell.front-cover",
                    recursively:
                        true
                )
            )

        let openFront =
            try XCTUnwrap(
                openBook.childNode(
                    withName:
                        "book-shell.front-cover",
                    recursively:
                        true
                )
            )

        XCTAssertNotEqual(
            closedFront.eulerAngles.y,
            openFront.eulerAngles.y,
            "Opening the book must rotate the physical front cover"
        )

        XCTAssertTrue(
            openFront.position.x.isFinite
                && openFront.position.y.isFinite
                && openFront.position.z.isFinite
        )

        let leftPage =
            try XCTUnwrap(
                openBook.childNode(
                    withName:
                        "book.left-active-page",
                    recursively:
                        true
                )
            )

        let rightPage =
            try XCTUnwrap(
                openBook.childNode(
                    withName:
                        "book.right-active-page",
                    recursively:
                        true
                )
            )

        let leftBlock =
            try XCTUnwrap(
                openBook.childNode(
                    withName:
                        "book.left-page-block",
                    recursively:
                        true
                )
            )

        let rightBlock =
            try XCTUnwrap(
                openBook.childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        true
                )
            )

        let leftBox =
            try XCTUnwrap(
                leftBlock.geometry
                    as? SCNBox
            )

        let rightBox =
            try XCTUnwrap(
                rightBlock.geometry
                    as? SCNBox
            )

        let leftActiveGeometry =
            try XCTUnwrap(
                leftPage.geometry
            )

        let rightActiveGeometry =
            try XCTUnwrap(
                rightPage.geometry
            )

        XCTAssertEqual(
            leftActiveGeometry.materials.count,
            2,
            "Curved active paper preserves separate front and reverse faces"
        )

        XCTAssertEqual(
            rightActiveGeometry.materials.count,
            2,
            "Curved active paper preserves separate front and reverse faces"
        )

        func verifySurface(
            page:
                SCNNode,
            block:
                SCNNode,
            box:
                SCNBox,
            side:
                String
        ) {
            let center =
                page.convertPosition(
                    SCNVector3Zero,
                    to:
                        block
                )

            let normal =
                page.convertVector(
                    SCNVector3(
                        0,
                        0,
                        1
                    ),
                    to:
                        block
                )

            XCTAssertEqual(
                center.x,
                0,
                accuracy:
                    0.001,
                "\(side) printed page center must remain centered on its own stack"
            )

            XCTAssertEqual(
                center.y,
                0,
                accuracy:
                    0.001,
                "\(side) printed page center must remain centered on its own stack"
            )

            XCTAssertGreaterThan(
                center.z,
                box.length / 2,
                "\(side) printed page must remain above its physical stack surface"
            )

            XCTAssertLessThan(
                center.z - box.length / 2,
                0.02,
                "\(side) printed page must remain in close contact with its physical stack"
            )

            XCTAssertEqual(
                normal.x,
                0,
                accuracy:
                    0.001
            )

            XCTAssertEqual(
                normal.y,
                0,
                accuracy:
                    0.001
            )

            XCTAssertGreaterThan(
                normal.z,
                0.999,
                "\(side) printed page must share the physical stack normal"
            )
        }

        verifySurface(
            page:
                leftPage,
            block:
                leftBlock,
            box:
                leftBox,
            side:
                "Left"
        )

        verifySurface(
            page:
                rightPage,
            block:
                rightBlock,
            box:
                rightBox,
            side:
                "Right"
        )

        XCTAssertTrue(
            rightBlock
                .geometry?
                .materials[1]
                .diffuse
                .contents
                is NSImage,
            "Physical page-block edge texture must remain present"
        )
    }

    func testTurningPagePivotUsesCommonGutterAndKeepsBookShellAttached() throws {
        var project = CoverProject(type: .printFullWrap)
        project.trimWidth = 6; project.trimHeight = 9; project.spineWidth = 1.25
        let scene = BookPreviewScene.make(project: project, workingLayers: false, open: true, angle: 170,
                                          leftPage: 2, rightPage: 3, pageCount: 20, spreadIndex: 1,
                                          leftTexture: nil, rightTexture: nil, margins: false, thumbMode: .off,
                                          leftPageSettings: PageSettings(), rightPageSettings: PageSettings(),
                                          preset: .perspective, revisionID: UUID())
        let transition = BookPageTurnTransition(fromSpread: 1, toSpread: 2, direction: .forward, rotation: .pi)
        BookPreviewScene.animatePageTurn(in: scene, project: project, pageCount: 20,
                                         image: NSImage(size: NSSize(width: 60, height: 90)),
                                         reverseImage: NSImage(size: NSSize(width: 60, height: 90)), transition: transition)
        let book = try XCTUnwrap(scene.rootNode.childNode(withName: "physical-book.root", recursively: false))
        let pivot = try XCTUnwrap(book.childNode(withName: "book.turning-page-pivot", recursively: false))
        XCTAssertEqual(pivot.position.x, 0, accuracy: 0.00001)
        let printed = try XCTUnwrap(book.childNode(withName: "book.right-active-page", recursively: true))
        let vertices = BookOpenGutterGeometry.vertices(try XCTUnwrap(printed.geometry?.sources(for: .vertex).first))
        let gutter = printed.convertPosition(vertices[0], to: book)
        XCTAssertEqual(pivot.position.z, gutter.z, accuracy: 0.0001)
        XCTAssertEqual(pivot.value(forKey: "bookTurnUsesPrintedSurfaces") as? Bool, true)
        XCTAssertNotNil(book.childNode(withName: "book-shell.front-cover", recursively: false))
        XCTAssertNotNil(book.childNode(withName: "book-shell.back-cover", recursively: false))
        XCTAssertNotNil(book.childNode(withName: "book-shell.spine", recursively: false))
        let turningLeaf = try XCTUnwrap(pivot.childNodes.first)
        let turningMesh = try XCTUnwrap(turningLeaf.geometry)

        XCTAssertEqual(turningLeaf.name, "book.turning-page-leaf")
        XCTAssertEqual(turningMesh.elements.count, 2)
        XCTAssertEqual(turningMesh.materials.count, 2)

        XCTAssertTrue(
            turningMesh.materials[0].diffuse.contents is NSImage,
            "Turning-page front must retain a manuscript image"
        )
        XCTAssertTrue(
            turningMesh.materials[1].diffuse.contents is NSImage,
            "Turning-page reverse must retain a manuscript image"
        )

        let morpher = try XCTUnwrap(
            turningLeaf.morpher,
            "A physical page turn must deform the sheet while it rotates"
        )

        XCTAssertEqual(
            morpher.targets.count,
            2,
            "The turning leaf should morph through peak and landing curl targets"
        )

        XCTAssertEqual(morpher.targets[0].elements.count, 2)
        XCTAssertEqual(morpher.targets[1].elements.count, 2)

        let start = BookPreviewScene.pageTurnMorphWeights(progress: 0)
        XCTAssertEqual(start.peak, 0, accuracy: 0.00001)
        XCTAssertEqual(start.landing, 0, accuracy: 0.00001)

        let quarter = BookPreviewScene.pageTurnMorphWeights(progress: 0.25)
        XCTAssertEqual(quarter.peak, 0.5, accuracy: 0.00001)
        XCTAssertEqual(quarter.landing, 0, accuracy: 0.00001)

        let middle = BookPreviewScene.pageTurnMorphWeights(progress: 0.5)
        XCTAssertEqual(middle.peak, 1, accuracy: 0.00001)
        XCTAssertEqual(middle.landing, 0, accuracy: 0.00001)

        let late = BookPreviewScene.pageTurnMorphWeights(progress: 0.75)
        XCTAssertEqual(late.peak, 0.5, accuracy: 0.00001)
        XCTAssertEqual(late.landing, 0.5, accuracy: 0.00001)

        let landed = BookPreviewScene.pageTurnMorphWeights(progress: 1)
        XCTAssertEqual(landed.peak, 0, accuracy: 0.00001)
        XCTAssertEqual(landed.landing, 1, accuracy: 0.00001)
    }

    func testCameraFocusFramingAndZoomRemainBounded() throws {
        var project = CoverProject(type: .printFullWrap)
        project.trimWidth = 6; project.trimHeight = 9; project.spineWidth = 0.75
        let front = BookPreviewCameraMath.state(project: project, open: false, preset: .perspective, focus: .front)
        let closedFit = BookPreviewCameraMath.state(project: project, open: false, preset: .perspective, focus: .automatic)
        let openFit = BookPreviewCameraMath.state(project: project, open: true, preset: .perspective, focus: .automatic)
        let spine = BookPreviewCameraMath.state(project: project, open: false, preset: .perspective, focus: .spine)
        let back = BookPreviewCameraMath.state(project: project, open: false, preset: .perspective, focus: .back)
        let spread = BookPreviewCameraMath.state(project: project, open: true, preset: .perspective, focus: .spread)
        let text = BookPreviewCameraMath.state(project: project, open: true, preset: .perspective, focus: .text)
        XCTAssertEqual(front.yaw, 0); XCTAssertEqual(spine.yaw, -.pi / 2); XCTAssertEqual(back.yaw, .pi)
        XCTAssertLessThan(spine.distance, front.distance)
        XCTAssertGreaterThan(openFit.distance, closedFit.distance)
        XCTAssertEqual(spread.target.x, 0, accuracy: 0.000001)
        XCTAssertEqual(text.target.x, project.trimWidth * 0.7 / 2, accuracy: 0.000001)
        XCTAssertLessThan(text.distance, spread.distance)
        var camera = front
        camera.orbit(deltaX: 100, deltaY: 10_000)
        XCTAssertEqual(camera.pitch, 1.52, accuracy: 0.000001)
        camera.zoom(by: 0.0001, minimum: 0.35, maximum: 12)
        XCTAssertEqual(camera.distance, 0.35, accuracy: 0.000001)
        camera.zoom(by: 1_000, minimum: 0.35, maximum: 12)
        XCTAssertEqual(camera.distance, 12, accuracy: 0.000001)
    }

    func testThumbZoneUsesOuterPageEdgesAndContentIntersection() {
        let left = PhysicalBookGeometry.thumbZone(pageWidth: 6, depth: 0.65, side: .left, mode: .standard)
        let right = PhysicalBookGeometry.thumbZone(pageWidth: 6, depth: 0.4, side: .right, mode: .conservative)
        XCTAssertEqual(left.x, 0); XCTAssertEqual(left.width, 0.65)
        XCTAssertEqual(right.x, 5.6); XCTAssertEqual(right.width, 0.4)
        XCTAssertEqual(PhysicalBookGeometry.intersects(CoverRect(x: 5.5, y: 0.3, width: 0.4, height: 0.2), zone: right), 0.3, accuracy: 0.000001)
        XCTAssertEqual(PhysicalBookGeometry.intersects(CoverRect(x: 2, y: 0.3, width: 1, height: 0.2), zone: right), 0)
        XCTAssertEqual(PhysicalBookGeometry.insideEdge(side: .left), .right)
        XCTAssertEqual(PhysicalBookGeometry.insideEdge(side: .right), .left)
        XCTAssertEqual(PhysicalBookGeometry.outsideEdge(side: .left), .left)
        XCTAssertEqual(PhysicalBookGeometry.outsideEdge(side: .right), .right)
        XCTAssertEqual(PhysicalBookGeometry.mirroredMargins(pageNumber: 2, left: 0.8, right: 0.4).left, 0.4)
        XCTAssertEqual(PhysicalBookGeometry.mirroredMargins(pageNumber: 2, left: 0.8, right: 0.4).right, 0.8)
        XCTAssertEqual(PhysicalBookGeometry.mirroredMargins(pageNumber: 3, left: 0.8, right: 0.4).left, 0.8)
        let fullHeight = PhysicalBookGeometry.thumbZone(pageWidth: 6, pageHeight: 9, depth: 0.65, side: .left, mode: .standard)
        XCTAssertEqual(fullHeight.height, 9)
        XCTAssertGreaterThan(PhysicalBookGeometry.intersects(CoverRect(x: 0.1, y: 7, width: 0.2, height: 0.3), zone: fullHeight), 0)
    }

    func testSoftcoverUsesFlexibleCoverWhileHardcoverRemainsRigid() throws {
        var project = CoverProject(type: .printFullWrap)
        project.trimWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8

        let closedProfile =
            BookPreviewScene.softcoverFlexProfile(
                open: false,
                angleDegrees: 0
            )

        let openProfile =
            BookPreviewScene.softcoverFlexProfile(
                open: true,
                angleDegrees: 180
            )

        XCTAssertGreaterThan(
            openProfile.creaseDepth,
            closedProfile.creaseDepth
        )

        XCTAssertGreaterThan(
            openProfile.bowDepth,
            closedProfile.bowDepth
        )

        let softScene =
            BookPreviewScene.make(
                project: project,
                workingLayers: false,
                open: true,
                angle: 180,
                leftPage: 2,
                rightPage: 3,
                pageCount: 20,
                spreadIndex: 1,
                leftTexture: nil,
                rightTexture: nil,
                margins: false,
                thumbMode: .off,
                leftPageSettings: PageSettings(),
                rightPageSettings: PageSettings(),
                preset: .perspective,
                revisionID: UUID(),
                binding: .softcover
            )

        let hardScene =
            BookPreviewScene.make(
                project: project,
                workingLayers: false,
                open: true,
                angle: 180,
                leftPage: 2,
                rightPage: 3,
                pageCount: 20,
                spreadIndex: 1,
                leftTexture: nil,
                rightTexture: nil,
                margins: false,
                thumbMode: .off,
                leftPageSettings: PageSettings(),
                rightPageSettings: PageSettings(),
                preset: .perspective,
                revisionID: UUID(),
                binding: .hardcover
            )

        let softBook =
            try XCTUnwrap(
                softScene.rootNode.childNode(
                    withName: "physical-book.root",
                    recursively: false
                )
            )

        let hardBook =
            try XCTUnwrap(
                hardScene.rootNode.childNode(
                    withName: "physical-book.root",
                    recursively: false
                )
            )

        let softFront =
            try XCTUnwrap(
                softBook.childNode(
                    withName: "book-shell.front-cover",
                    recursively: false
                )
            )

        let softBack =
            try XCTUnwrap(
                softBook.childNode(
                    withName: "book-shell.back-cover",
                    recursively: false
                )
            )

        let hardFront =
            try XCTUnwrap(
                hardBook.childNode(
                    withName: "book-shell.front-cover",
                    recursively: false
                )
            )

        XCTAssertFalse(
            softFront.geometry is SCNBox,
            "A paperback front cover must not be modeled as a rigid board"
        )

        XCTAssertFalse(
            softBack.geometry is SCNBox,
            "A paperback back cover must not be modeled as a rigid board"
        )

        XCTAssertTrue(
            hardFront.geometry is SCNBox,
            "A hardcover must retain rigid board geometry"
        )

        let softGeometry =
            try XCTUnwrap(
                softFront.geometry
            )

        XCTAssertEqual(
            softGeometry.elements.count,
            3,
            "Flexible cover requires exterior, interior and stock edge faces"
        )

        XCTAssertEqual(
            softGeometry.materials.count,
            3,
            "Flexible cover keeps exterior, lining and stock edge materials"
        )
    }

    func testTrimMismatchPagesFindsMixedPageSizesAcrossManuscript() {
        var project =
            CoverProject()

        project.trimWidth =
            6

        project.trimHeight =
            9

        var matching =
            PageSettings()

        matching.paper =
            .custom

        matching.customPaperSize =
            CGSize(
                width:
                    432,
                height:
                    648
            )

        var narrow =
            matching

        narrow.customPaperSize =
            CGSize(
                width:
                    360,
                height:
                    648
            )

        var tall =
            matching

        tall.customPaperSize =
            CGSize(
                width:
                    432,
                height:
                    720
            )

        let mismatches =
            PhysicalBookDiagnostics
                .trimMismatchPages(
                    project:
                        project,
                    pages:
                        [
                            matching,
                            narrow,
                            matching,
                            tall
                        ]
                )

        XCTAssertEqual(
            mismatches,
            [
                2,
                4
            ]
        )
    }

    func testTrimMismatchPagesReturnsEmptyForUniformMatchingManuscript() {
        var project =
            CoverProject()

        project.trimWidth =
            6

        project.trimHeight =
            9

        var matching =
            PageSettings()

        matching.paper =
            .custom

        matching.customPaperSize =
            CGSize(
                width:
                    432,
                height:
                    648
            )

        XCTAssertEqual(
            PhysicalBookDiagnostics
                .trimMismatchPages(
                    project:
                        project,
                    pages:
                        [
                            matching,
                            matching,
                            matching
                        ]
                ),
            []
        )
    }

    func testPrintReadinessSummaryIsReadyWithNoFindings() {
        let summary =
            PhysicalBookDiagnostics
                .preflightSummary(
                    errorCount:
                        0,
                    warningCount:
                        0
                )

        XCTAssertEqual(
            summary.status,
            .ready
        )

        XCTAssertEqual(
            summary.errorCount,
            0
        )

        XCTAssertEqual(
            summary.warningCount,
            0
        )
    }

    func testPrintReadinessSummaryRequestsReviewForWarnings() {
        let summary =
            PhysicalBookDiagnostics
                .preflightSummary(
                    errorCount:
                        0,
                    warningCount:
                        7
                )

        XCTAssertEqual(
            summary.status,
            .review
        )

        XCTAssertEqual(
            summary.errorCount,
            0
        )

        XCTAssertEqual(
            summary.warningCount,
            7
        )
    }

    func testPrintReadinessSummaryIsNotReadyForExistingErrors() {
        let summary =
            PhysicalBookDiagnostics
                .preflightSummary(
                    errorCount:
                        1,
                    warningCount:
                        9
                )

        XCTAssertEqual(
            summary.status,
            .notReady
        )

        XCTAssertEqual(
            summary.errorCount,
            1
        )

        XCTAssertEqual(
            summary.warningCount,
            9
        )
    }

    func testPublishingPreflightBlocksObsoleteMeasuredHardcoverTemplate() {
        var project = CoverProject(type: .printFullWrap, width: 19.469, height: 12.417)
        project.productionBinding = .hardcover
        project.trimWidth = 8.25
        project.backWidth = 8.25
        project.trimHeight = 11
        project.spineWidth = 1.394
        project.spinePageCount = 535
        project.kdpHardcoverLayout = KDPHardcoverLayout(
            canvasWidth: 19.469, canvasHeight: 12.417,
            trimWidth: 8.25, trimHeight: 11,
            spineWidth: 1.394, pageCount: 535
        )
        var manuscriptPage = PageSettings()
        manuscriptPage.paper = .custom
        manuscriptPage.customPaperSize = CGSize(width: 396, height: 612)

        let result = PhysicalBookDiagnostics.publishingPreflight(
            project: project,
            manuscriptPageCount: 356,
            pageSettings: [manuscriptPage]
        )

        XCTAssertEqual(result.status, .notReady)
        XCTAssertFalse(result.isReady)
        XCTAssertTrue(result.errors.contains { $0.contains("535 pages") && $0.contains("356") })
        XCTAssertTrue(result.errors.contains { $0.contains("8.250 × 11.000") && $0.contains("5.500 × 8.500") })
    }

    func testPublishingPreflightBlocksPreviewGeometryWithoutPrintProfile() {
        var project = CoverProject(type: .printFullWrap, width: 13.0, height: 9.25)
        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.54 // provisional 240-page preview width
        project.bleed = 0.125

        let page = PageSettings(customPaperSize: CGSize(width: 432, height: 648))
        let result = PhysicalBookDiagnostics.publishingPreflight(
            project: project,
            manuscriptPageCount: 240,
            pageSettings: [page]
        )

        XCTAssertEqual(result.status, .notReady)
        XCTAssertTrue(result.errors.contains { $0.localizedCaseInsensitiveContains("provisional") })
    }

    func testPrintReadinessSummaryClampsInvalidNegativeCounts() {
        let summary =
            PhysicalBookDiagnostics
                .preflightSummary(
                    errorCount:
                        -4,
                    warningCount:
                        -2
                )

        XCTAssertEqual(
            summary.status,
            .ready
        )

        XCTAssertEqual(
            summary.errorCount,
            0
        )

        XCTAssertEqual(
            summary.warningCount,
            0
        )
    }

    func testManuscriptGeometryDiagnosticsCollectMarginAndThumbPages() throws {
        var settings =
            PageSettings()

        settings.paper =
            .custom

        settings.customPaperSize =
            CGSize(
                width:
                    432,
                height:
                    648
            )

        settings.leftMargin =
            18

        settings.rightMargin =
            18

        settings.topMargin =
            36

        settings.bottomMargin =
            36

        let source =
            NSAttributedString(
                string:
                    "First page near the binding."
                    + "\u{000C}"
                    + "Second page near the outside edge.",
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    14
                            )
                    ]
            )

        var pageSettings:
            [PageSettings] = []

        let data =
            try PDFExporter.data(
                from:
                    source,
                settings:
                    settings,
                pageLayoutSink: {
                    pageSettings =
                        $0
                }
            )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        data
                )
            )

        XCTAssertGreaterThanOrEqual(
            pdf.pageCount,
            2
        )

        let diagnostics =
            PhysicalBookPreview
                .manuscriptGeometryDiagnostics(
                    pdf:
                        pdf,
                    pageSettings:
                        pageSettings,
                    spineWidth:
                        0.8
                )

        XCTAssertTrue(
            diagnostics
                .marginWarningsByPage
                .keys
                .contains(
                    1
                ),
            "A 0.25-inch inside margin on the first recto page should be reported as insufficient gutter clearance for this spine."
        )

        XCTAssertTrue(
            diagnostics
                .marginWarningsByPage[
                    1
                ]?
                .contains {
                    $0.contains(
                        "gutter"
                    )
                }
                == true
        )

        XCTAssertTrue(
            diagnostics
                .standardThumbWarningsByPage
                .keys
                .contains(
                    2
                ),
            "The second verso page begins close enough to the left outside edge to enter the standard thumb zone."
        )

        XCTAssertTrue(
            diagnostics
                .compactThumbWarningsByPage
                .keys
                .contains(
                    2
                ),
            "The same 0.25-inch outside placement should also enter the compact 0.40-inch thumb zone."
        )
    }

    func testNextIssuePageAdvancesAndWraps() {
        let pages =
            [
                8,
                3,
                8,
                14,
                5
            ]

        XCTAssertEqual(
            PhysicalBookDiagnostics
                .nextIssuePage(
                    after:
                        3,
                    issuePages:
                        pages
                ),
            5
        )

        XCTAssertEqual(
            PhysicalBookDiagnostics
                .nextIssuePage(
                    after:
                        5,
                    issuePages:
                        pages
                ),
            8
        )

        XCTAssertEqual(
            PhysicalBookDiagnostics
                .nextIssuePage(
                    after:
                        14,
                    issuePages:
                        pages
                ),
            3,
            "Navigation should wrap to the first affected page after the final issue."
        )

        XCTAssertEqual(
            PhysicalBookDiagnostics
                .nextIssuePage(
                    after:
                        1,
                    issuePages:
                        pages
                ),
            3
        )
    }

    func testNextIssuePageHandlesSingleAndEmptyIssueSets() {
        XCTAssertEqual(
            PhysicalBookDiagnostics
                .nextIssuePage(
                    after:
                        9,
                    issuePages:
                        [
                            9
                        ]
                ),
            9,
            "A single affected page should wrap back to itself."
        )

        XCTAssertNil(
            PhysicalBookDiagnostics
                .nextIssuePage(
                    after:
                        1,
                    issuePages:
                        []
                )
        )

        XCTAssertNil(
            PhysicalBookDiagnostics
                .nextIssuePage(
                    after:
                        1,
                    issuePages:
                        [
                            -4,
                            0
                        ]
                )
        )
    }

    func testPDFExporterReturnsPhysicalPageCharacterRanges() throws {
        var settings =
            PageSettings()

        settings.paper =
            .custom

        settings.customPaperSize =
            CGSize(
                width:
                    432,
                height:
                    648
            )

        let source =
            NSAttributedString(
                string:
                    "First physical page."
                    + "\u{000C}"
                    + "Second physical page.",
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    14
                            )
                    ]
            )

        var layouts:
            [PageSettings] = []

        var ranges:
            [NSRange] = []

        let data =
            try PDFExporter.data(
                from:
                    source,
                settings:
                    settings,
                pageLayoutSink: {
                    layouts =
                        $0
                },
                pageRangeSink: {
                    ranges =
                        $0
                }
            )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        data
                )
            )

        XCTAssertEqual(
            ranges.count,
            pdf.pageCount
        )

        XCTAssertEqual(
            layouts.count,
            pdf.pageCount
        )

        XCTAssertGreaterThanOrEqual(
            pdf.pageCount,
            2
        )

        let sourceString =
            source.string
                as NSString

        XCTAssertTrue(
            sourceString
                .substring(
                    with:
                        ranges[0]
                )
                .contains(
                    "First physical page"
                )
        )

        XCTAssertTrue(
            sourceString
                .substring(
                    with:
                        ranges[1]
                )
                .contains(
                    "Second physical page"
                )
        )
    }

    func testInteriorImageResolutionUsesSourcePixelsAndPrintedAttachmentSize() throws {
        func png(
            width: Int,
            height: Int
        ) throws -> Data {
            let bitmap =
                try XCTUnwrap(
                    NSBitmapImageRep(
                        bitmapDataPlanes:
                            nil,
                        pixelsWide:
                            width,
                        pixelsHigh:
                            height,
                        bitsPerSample:
                            8,
                        samplesPerPixel:
                            4,
                        hasAlpha:
                            true,
                        isPlanar:
                            false,
                        colorSpaceName:
                            .deviceRGB,
                        bytesPerRow:
                            0,
                        bitsPerPixel:
                            0
                    )
                )

            return try XCTUnwrap(
                bitmap.representation(
                    using:
                        .png,
                    properties:
                        [:]
                )
            )
        }

        func attachment(
            name: String,
            pixels: Int,
            points: CGFloat
        ) throws -> NSTextAttachment {
            let data =
                try png(
                    width:
                        pixels,
                    height:
                        pixels
                )

            let image =
                try XCTUnwrap(
                    NSImage(
                        data:
                            data
                    )
                )

            image.size =
                NSSize(
                    width:
                        points,
                    height:
                        points
                )

            let wrapper =
                FileWrapper(
                    regularFileWithContents:
                        data
                )

            wrapper.preferredFilename =
                name

            let attachment =
                NSTextAttachment(
                    fileWrapper:
                        wrapper
                )

            attachment.attachmentCell =
                NSTextAttachmentCell(
                    imageCell:
                        image
                )

            attachment.bounds =
                NSRect(
                    origin:
                        .zero,
                    size:
                        image.size
                )

            return attachment
        }

        let text =
            NSMutableAttributedString()

        let lowStart =
            text.length

        text.append(
            NSAttributedString(
                attachment:
                    try attachment(
                        name:
                            "Low.png",
                        pixels:
                            150,
                        points:
                            72
                    )
            )
        )

        let firstRange =
            NSRange(
                location:
                    lowStart,
                length:
                    text.length
                        - lowStart
            )

        text.append(
            NSAttributedString(
                string:
                    "\n"
            )
        )

        let marginalStart =
            text.length

        text.append(
            NSAttributedString(
                attachment:
                    try attachment(
                        name:
                            "Marginal.png",
                        pixels:
                            240,
                        points:
                            72
                    )
            )
        )

        let secondRange =
            NSRange(
                location:
                    marginalStart,
                length:
                    text.length
                        - marginalStart
            )

        let issues =
            PhysicalBookDiagnostics
                .interiorImageResolutionIssues(
                    text:
                        text,
                    pageRanges:
                        [
                            firstRange,
                            secondRange
                        ]
                )

        XCTAssertEqual(
            issues.count,
            2
        )

        let low =
            try XCTUnwrap(
                issues.first {
                    $0.imageName
                        == "Low.png"
                }
            )

        XCTAssertEqual(
            low.pageNumber,
            1
        )

        XCTAssertEqual(
            low.severity,
            .low
        )

        XCTAssertEqual(
            low.effectiveDPI,
            150,
            accuracy:
                0.001
        )

        XCTAssertTrue(
            low.message
                .contains(
                    "page 1"
                )
        )

        XCTAssertTrue(
            low.message
                .contains(
                    "150"
                )
        )

        let marginal =
            try XCTUnwrap(
                issues.first {
                    $0.imageName
                        == "Marginal.png"
                }
            )

        XCTAssertEqual(
            marginal.pageNumber,
            2
        )

        XCTAssertEqual(
            marginal.severity,
            .marginal
        )

        XCTAssertEqual(
            marginal.effectiveDPI,
            240,
            accuracy:
                0.001
        )
    }

    func testInteriorImageResolutionIgnoresPrintQualityRaster() throws {
        let bitmap =
            try XCTUnwrap(
                NSBitmapImageRep(
                    bitmapDataPlanes:
                        nil,
                    pixelsWide:
                        300,
                    pixelsHigh:
                        300,
                    bitsPerSample:
                        8,
                    samplesPerPixel:
                        4,
                    hasAlpha:
                        true,
                    isPlanar:
                        false,
                    colorSpaceName:
                        .deviceRGB,
                    bytesPerRow:
                        0,
                    bitsPerPixel:
                        0
                )
            )

        let data =
            try XCTUnwrap(
                bitmap.representation(
                    using:
                        .png,
                    properties:
                        [:]
                )
            )

        let image =
            try XCTUnwrap(
                NSImage(
                    data:
                        data
                )
            )

        image.size =
            NSSize(
                width:
                    72,
                height:
                    72
            )

        let wrapper =
            FileWrapper(
                regularFileWithContents:
                    data
            )

        wrapper.preferredFilename =
            "Good.png"

        let attachment =
            NSTextAttachment(
                fileWrapper:
                    wrapper
            )

        attachment.attachmentCell =
            NSTextAttachmentCell(
                imageCell:
                    image
            )

        attachment.bounds =
            NSRect(
                origin:
                    .zero,
                size:
                    image.size
            )

        let text =
            NSAttributedString(
                attachment:
                    attachment
            )

        XCTAssertTrue(
            PhysicalBookDiagnostics
                .interiorImageResolutionIssues(
                    text:
                        text,
                    pageRanges:
                        [
                            NSRange(
                                location:
                                    0,
                                length:
                                    text.length
                            )
                        ]
                )
                .isEmpty
        )
    }

    func testInteriorResolutionMarkerChangesOnlyAffectedPageTexture() throws {
        let bitmap =
            try XCTUnwrap(
                NSBitmapImageRep(
                    bitmapDataPlanes:
                        nil,
                    pixelsWide:
                        120,
                    pixelsHigh:
                        160,
                    bitsPerSample:
                        8,
                    samplesPerPixel:
                        4,
                    hasAlpha:
                        true,
                    isPlanar:
                        false,
                    colorSpaceName:
                        .deviceRGB,
                    bytesPerRow:
                        0,
                    bitsPerPixel:
                        0
                )
            )

        let base =
            NSImage(
                size:
                    NSSize(
                        width:
                            120,
                        height:
                            160
                    )
            )

        base.addRepresentation(
            bitmap
        )

        let clean =
            PhysicalBookPreview
                .interiorResolutionTexture(
                    base,
                    hasIssue:
                        false
                )

        XCTAssertTrue(
            clean === base,
            "A clean manuscript page must not be copied or visually altered."
        )

        let marked =
            PhysicalBookPreview
                .interiorResolutionTexture(
                    base,
                    hasIssue:
                        true
                )

        XCTAssertFalse(
            marked === base
        )

        XCTAssertEqual(
            marked.size,
            base.size
        )

        XCTAssertNotEqual(
            marked.tiffRepresentation,
            base.tiffRepresentation,
            "An affected page should receive a visible diagnostic marker in the physical preview texture."
        )
    }

    func testCoverEffectiveDPIAccountsForSourceCropAndFillCrop() throws {
        func imageData(
            width: Int,
            height: Int
        ) throws -> Data {
            let bitmap =
                try XCTUnwrap(
                    NSBitmapImageRep(
                        bitmapDataPlanes:
                            nil,
                        pixelsWide:
                            width,
                        pixelsHigh:
                            height,
                        bitsPerSample:
                            8,
                        samplesPerPixel:
                            4,
                        hasAlpha:
                            true,
                        isPlanar:
                            false,
                        colorSpaceName:
                            .deviceRGB,
                        bytesPerRow:
                            0,
                        bitsPerPixel:
                            0
                    )
                )

            return try XCTUnwrap(
                bitmap.representation(
                    using:
                        .png,
                    properties:
                        [:]
                )
            )
        }

        var project =
            CoverProject(
                type: .printFullWrap
            )

        project.canvasWidth = 10
        project.canvasHeight = 10
        project.dpi = 300

        var layer =
            CoverLayer(
                kind: .image,
                name: "DPI Test",
                frame:
                    CoverRect(
                        x: 0,
                        y: 0,
                        width: 0.1,
                        height: 0.1
                    )
            )

        layer.imageData =
            try imageData(
                width: 300,
                height: 300
            )

        layer.cropMode = .fit

        XCTAssertEqual(
            try XCTUnwrap(
                CoverEditorEngine
                    .effectiveDPI(
                        layer,
                        project: project
                    )
            ),
            300,
            accuracy:
                0.001
        )

        layer.sourceCrop =
            CoverRect(
                x: 0.25,
                y: 0.25,
                width: 0.5,
                height: 0.5
            )

        XCTAssertEqual(
            try XCTUnwrap(
                CoverEditorEngine
                    .effectiveDPI(
                        layer,
                        project: project
                    )
            ),
            150,
            accuracy:
                0.001
        )

        layer.sourceCrop = nil
        layer.cropMode = .fill
        layer.imageData =
            try imageData(
                width: 600,
                height: 300
            )

        XCTAssertEqual(
            try XCTUnwrap(
                CoverEditorEngine
                    .effectiveDPI(
                        layer,
                        project: project
                    )
            ),
            300,
            accuracy:
                0.001,
            "Filling a square with a 2:1 source must discard half the source width before effective DPI is calculated"
        )
    }

    func testCoverImageResolutionDiagnosticsClassifyMarginalAndLowLayers() throws {
        func imageData(
            width: Int,
            height: Int
        ) throws -> Data {
            let bitmap =
                try XCTUnwrap(
                    NSBitmapImageRep(
                        bitmapDataPlanes:
                            nil,
                        pixelsWide:
                            width,
                        pixelsHigh:
                            height,
                        bitsPerSample:
                            8,
                        samplesPerPixel:
                            4,
                        hasAlpha:
                            true,
                        isPlanar:
                            false,
                        colorSpaceName:
                            .deviceRGB,
                        bytesPerRow:
                            0,
                        bitsPerPixel:
                            0
                    )
                )

            return try XCTUnwrap(
                bitmap.representation(
                    using:
                        .png,
                    properties:
                        [:]
                )
            )
        }

        var project =
            CoverProject(
                type: .printFullWrap
            )

        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8
        project.bleed = 0.125
        project.canvasWidth = 13.05
        project.canvasHeight = 9.25
        project.dpi = 300

        let geometry =
            CoverWrapGeometry(
                project: project
            )

        let oneInchWidth =
            1
            / project.canvasWidth

        let oneInchHeight =
            1
            / project.canvasHeight

        var marginal =
            CoverLayer(
                kind: .image,
                name: "Marginal Portrait",
                frame:
                    CoverRect(
                        x:
                            geometry.frontTrim.x
                            + geometry.frontTrim.width * 0.30,
                        y:
                            geometry.frontTrim.y
                            + geometry.frontTrim.height * 0.30,
                        width:
                            oneInchWidth,
                        height:
                            oneInchHeight
                    )
            )

        marginal.imageData =
            try imageData(
                width: 220,
                height: 220
            )

        marginal.cropMode = .fit

        var low =
            marginal

        low.id = UUID()
        low.name =
            "Low Portrait"

        low.frame.x =
            geometry.backTrim.x
            + geometry.backTrim.width * 0.30

        low.imageData =
            try imageData(
                width: 150,
                height: 150
            )

        project.layers = [
            marginal,
            low
        ]

        let issues =
            PhysicalBookDiagnostics
                .coverImageResolutionIssues(
                    project: project
                )

        XCTAssertEqual(
            issues.count,
            2
        )

        let marginalIssue =
            try XCTUnwrap(
                issues.first {
                    $0.layerName
                        == "Marginal Portrait"
                }
            )

        XCTAssertEqual(
            marginalIssue.severity,
            .marginal
        )

        XCTAssertEqual(
            marginalIssue.effectiveDPI,
            220,
            accuracy:
                0.001
        )

        XCTAssertTrue(
            marginalIssue.regions
                .contains(
                    .front
                )
        )

        let lowIssue =
            try XCTUnwrap(
                issues.first {
                    $0.layerName
                        == "Low Portrait"
                }
            )

        XCTAssertEqual(
            lowIssue.severity,
            .low
        )

        XCTAssertEqual(
            lowIssue.effectiveDPI,
            150,
            accuracy:
                0.001
        )

        XCTAssertTrue(
            lowIssue.regions
                .contains(
                    .back
                )
        )

        XCTAssertTrue(
            marginalIssue.message
                .contains(
                    "220"
                )
        )
    }

    func testReferenceOnlyTemplateImagesAreNotReportedAsProductionResolutionDefects() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 150,
            pixelsHigh: 150,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        var project = CoverProject(type: .printFullWrap)
        project.canvasWidth = 10
        project.canvasHeight = 10
        project.dpi = 300
        var reference = CoverLayer(kind: .image, name: "Reference photo", frame: CoverRect(x: 0, y: 0, width: 0.5, height: 0.5))
        reference.imageData = data
        reference.referenceOnly = true
        var production = reference
        production.id = UUID()
        production.name = "Production photo"
        production.referenceOnly = false
        project.layers = [reference]

        XCTAssertTrue(PhysicalBookDiagnostics.coverImageResolutionIssues(project: project).isEmpty)

        project.layers.append(production)
        let issues = PhysicalBookDiagnostics.coverImageResolutionIssues(project: project)
        XCTAssertEqual(issues.map(\.layerName), ["Production photo"])
        XCTAssertEqual(try XCTUnwrap(issues.first).effectiveDPI, 30, accuracy: 0.001)
    }

    func testLowResolutionCoverImageCreatesPhysicalPanelBadge() throws {
        let bitmap =
            try XCTUnwrap(
                NSBitmapImageRep(
                    bitmapDataPlanes:
                        nil,
                    pixelsWide:
                        120,
                    pixelsHigh:
                        120,
                    bitsPerSample:
                        8,
                    samplesPerPixel:
                        4,
                    hasAlpha:
                        true,
                    isPlanar:
                        false,
                    colorSpaceName:
                        .deviceRGB,
                    bytesPerRow:
                        0,
                    bitsPerPixel:
                        0
                )
            )

        let data =
            try XCTUnwrap(
                bitmap.representation(
                    using:
                        .png,
                    properties:
                        [:]
                )
            )

        var project =
            CoverProject(
                type: .printFullWrap
            )

        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8
        project.bleed = 0.125
        project.canvasWidth = 13.05
        project.canvasHeight = 9.25
        project.dpi = 300

        let geometry =
            CoverWrapGeometry(
                project: project
            )

        var image =
            CoverLayer(
                kind: .image,
                name: "Low Front Photo",
                frame:
                    CoverRect(
                        x:
                            geometry.frontTrim.x
                            + geometry.frontTrim.width * 0.30,
                        y:
                            geometry.frontTrim.y
                            + geometry.frontTrim.height * 0.30,
                        width:
                            1
                            / project.canvasWidth,
                        height:
                            1
                            / project.canvasHeight
                    )
            )

        image.imageData =
            data

        image.cropMode =
            .fit

        project.layers = [
            image
        ]

        let scene =
            BookPreviewScene.make(
                project: project,
                workingLayers: false,
                open: false,
                angle: 0,
                leftPage: nil,
                rightPage: 1,
                pageCount: 40,
                spreadIndex: 0,
                leftTexture: nil,
                rightTexture: nil,
                margins: false,
                thumbMode: .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset: .front,
                revisionID: UUID(),
                binding: .softcover
            )

        let front =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "book-shell.front-cover",
                        recursively: true
                    )
            )

        XCTAssertNotNil(
            front.childNode(
                withName:
                    "diagnostic.cover.front.resolution",
                recursively: false
            )
        )

        let workingScene =
            BookPreviewScene.make(
                project: project,
                workingLayers: true,
                open: false,
                angle: 0,
                leftPage: nil,
                rightPage: 1,
                pageCount: 40,
                spreadIndex: 0,
                leftTexture: nil,
                rightTexture: nil,
                margins: false,
                thumbMode: .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset: .front,
                revisionID: UUID(),
                binding: .softcover
            )

        let workingFront =
            try XCTUnwrap(
                workingScene.rootNode
                    .childNode(
                        withName:
                            "book-shell.front-cover",
                        recursively: true
                    )
            )

        XCTAssertNil(
            workingFront.childNode(
                withName:
                    "diagnostic.cover.front.resolution",
                recursively: false
            )
        )
    }

    func testFrontBackCoverContentSafeZonesDetectRiskWithoutFlaggingBleedBackgrounds() throws {
        var project =
            CoverProject(
                type: .printFullWrap
            )

        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8
        project.bleed = 0.125
        project.canvasWidth = 13.05
        project.canvasHeight = 9.25

        let geometry =
            CoverWrapGeometry(
                project: project
            )

        var safeTitle =
            CoverLayer(
                kind: .text,
                name: "Safe Front Title",
                frame:
                    CoverRect(
                        x:
                            geometry.frontSafeArea.x
                            + geometry.frontSafeArea.width * 0.20,
                        y:
                            geometry.frontSafeArea.y
                            + geometry.frontSafeArea.height * 0.20,
                        width:
                            geometry.frontSafeArea.width * 0.60,
                        height:
                            geometry.frontSafeArea.height * 0.20
                    )
            )

        safeTitle.text =
            "SAFE TITLE"

        project.layers = [
            safeTitle
        ]

        XCTAssertTrue(
            PhysicalBookDiagnostics
                .coverContentSafeIssues(
                    project: project
                )
                .isEmpty
        )

        var frontFoldText =
            safeTitle

        frontFoldText.name =
            "Front Fold Title"

        frontFoldText.frame.x =
            geometry.frontTrim.x
            + geometry.frontTrim.width * 0.01

        project.layers = [
            frontFoldText
        ]

        let frontIssues =
            PhysicalBookDiagnostics
                .coverContentSafeIssues(
                    project: project
                )

        XCTAssertTrue(
            frontIssues.contains {
                $0.panel == .front
                    && $0.edge
                        == .spineSide
            }
        )

        var backLogo =
            CoverLayer(
                kind: .shape,
                name: "Back Logo",
                frame:
                    CoverRect(
                        x:
                            geometry.backSafeArea.x
                            + geometry.backSafeArea.width * 0.15,
                        y:
                            geometry.backSafeArea.y
                            + geometry.backSafeArea.height * 0.20,
                        width:
                            geometry.backSafeArea.width * 0.30,
                        height:
                            geometry.backSafeArea.height * 0.20
                    )
            )

        backLogo.fillOpacity =
            1

        backLogo.frame.x =
            geometry.backTrim.x
            + geometry.backTrim.width * 0.01

        project.layers = [
            backLogo
        ]

        let backIssues =
            PhysicalBookDiagnostics
                .coverContentSafeIssues(
                    project: project
                )

        XCTAssertTrue(
            backIssues.contains {
                $0.panel == .back
                    && $0.edge
                        == .outer
            }
        )

        var background =
            CoverLayer(
                kind: .shape,
                name: "Full Bleed Background",
                frame:
                    geometry.frontTrim
            )

        background.fillOpacity =
            1

        project.layers = [
            background
        ]

        XCTAssertTrue(
            PhysicalBookDiagnostics
                .coverContentSafeIssues(
                    project: project
                )
                .isEmpty,
            "Intentional full-panel non-text artwork must not be treated as unsafe foreground content"
        )
    }

    func testCoverSafeZonesUseRotatedBounds() throws {
        var project =
            CoverProject(
                type: .printFullWrap
            )

        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8
        project.bleed = 0.125
        project.canvasWidth = 13.05
        project.canvasHeight = 9.25

        let geometry =
            CoverWrapGeometry(
                project: project
            )

        var layer =
            CoverLayer(
                kind: .text,
                name: "Rotated Front Title",
                frame:
                    CoverRect(
                        x:
                            geometry.frontSafeArea.x
                            + geometry.frontSafeArea.width * 0.36,
                        y:
                            geometry.frontTrim.y
                            + geometry.frontTrim.height * 0.01,
                        width:
                            geometry.frontSafeArea.width * 0.28,
                        height:
                            geometry.frontSafeArea.height * 0.10
                    )
            )

        layer.text =
            "ROTATED"

        layer.rotation =
            35

        project.layers = [
            layer
        ]

        let issues =
            PhysicalBookDiagnostics
                .coverContentSafeIssues(
                    project: project
                )

        XCTAssertTrue(
            issues.contains {
                $0.panel == .front
                    && $0.edge
                        == .top
            }
        )
    }

    func testUnsafeFrontCoverContentCreatesVisibleSafeEdgeWarning() throws {
        var project =
            CoverProject(
                type: .printFullWrap
            )

        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8
        project.bleed = 0.125
        project.canvasWidth = 13.05
        project.canvasHeight = 9.25

        let geometry =
            CoverWrapGeometry(
                project: project
            )

        var title =
            CoverLayer(
                kind: .text,
                name: "Fold Risk",
                frame:
                    CoverRect(
                        x:
                            geometry.frontTrim.x
                            + geometry.frontTrim.width * 0.01,
                        y:
                            geometry.frontSafeArea.y
                            + geometry.frontSafeArea.height * 0.20,
                        width:
                            geometry.frontSafeArea.width * 0.50,
                        height:
                            geometry.frontSafeArea.height * 0.20
                    )
            )

        title.text =
            "FOLD RISK"

        project.layers = [
            title
        ]

        let scene =
            BookPreviewScene.make(
                project: project,
                workingLayers: false,
                open: false,
                angle: 0,
                leftPage: nil,
                rightPage: 1,
                pageCount: 40,
                spreadIndex: 0,
                leftTexture: nil,
                rightTexture: nil,
                margins: false,
                thumbMode: .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset: .front,
                revisionID: UUID(),
                binding: .softcover
            )

        let front =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "book-shell.front-cover",
                        recursively: true
                    )
            )

        XCTAssertNotNil(
            front.childNode(
                withName:
                    "diagnostic.cover.front.safe.spineSide",
                recursively: false
            )
        )

        let workingScene =
            BookPreviewScene.make(
                project: project,
                workingLayers: true,
                open: false,
                angle: 0,
                leftPage: nil,
                rightPage: 1,
                pageCount: 40,
                spreadIndex: 0,
                leftTexture: nil,
                rightTexture: nil,
                margins: false,
                thumbMode: .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset: .front,
                revisionID: UUID(),
                binding: .softcover
            )

        let workingFront =
            try XCTUnwrap(
                workingScene.rootNode
                    .childNode(
                        withName:
                            "book-shell.front-cover",
                        recursively: true
                    )
            )

        XCTAssertNil(
            workingFront.childNode(
                withName:
                    "diagnostic.cover.front.safe.spineSide",
                recursively: false
            )
        )
    }

    func testSpineTextDiagnosticsCatchFoldAndWidthProblems() throws {
        var project =
            CoverProject(
                type: .printFullWrap
            )

        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8
        project.bleed = 0.125
        project.canvasWidth = 13.05
        project.canvasHeight = 9.25

        let spine =
            CoverWrapGeometry(
                project: project
            )
            .spineTrim

        var safe =
            CoverLayer(
                kind: .text,
                name: "Safe Spine",
                frame:
                    CoverRect(
                        x:
                            spine.x
                            + spine.width * 0.25,
                        y:
                            spine.y
                            + spine.height * 0.20,
                        width:
                            spine.width * 0.50,
                        height:
                            spine.height * 0.60
                    )
            )

        safe.text = "SAFE"

        project.layers = [
            safe
        ]

        XCTAssertTrue(
            PhysicalBookDiagnostics
                .spineTextIssues(
                    project: project
                )
                .isEmpty
        )

        var crossing = safe
        crossing.name = "Crossing Spine"
        crossing.frame.x =
            spine.x
            - spine.width * 0.10

        project.layers = [
            crossing
        ]

        XCTAssertTrue(
            PhysicalBookDiagnostics
                .spineTextIssues(
                    project: project
                )
                .contains {
                    $0.kind
                        == .outsideSpineTrim
                }
        )

        var nearFold = safe
        nearFold.name = "Near Fold"
        nearFold.frame.x =
            spine.x
            + spine.width * 0.02

        project.layers = [
            nearFold
        ]

        XCTAssertTrue(
            PhysicalBookDiagnostics
                .spineTextIssues(
                    project: project
                )
                .contains {
                    $0.kind
                        == .insufficientFoldClearance
                }
        )

        var tooWide = safe
        tooWide.name = "Too Wide"
        tooWide.frame =
            CoverRect(
                x:
                    spine.x
                    + spine.width * 0.03,
                y:
                    spine.y
                    + spine.height * 0.20,
                width:
                    spine.width * 0.94,
                height:
                    spine.height * 0.60
            )

        project.layers = [
            tooWide
        ]

        XCTAssertTrue(
            PhysicalBookDiagnostics
                .spineTextIssues(
                    project: project
                )
                .contains {
                    $0.kind
                        == .widerThanSafeSpine
                }
        )
    }

    func testSpineTextDiagnosticsAccountForRotationAndNarrowSpines() throws {
        var project =
            CoverProject(
                type: .printFullWrap
            )

        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.20
        project.bleed = 0.125
        project.canvasWidth = 12.45
        project.canvasHeight = 9.25

        let spine =
            CoverWrapGeometry(
                project: project
            )
            .spineTrim

        var layer =
            CoverLayer(
                kind: .text,
                name: "Rotated Spine",
                frame:
                    CoverRect(
                        x:
                            spine.x
                            + spine.width * 0.20,
                        y:
                            spine.y
                            + spine.height * 0.46,
                        width:
                            spine.width * 0.60,
                        height:
                            spine.height * 0.08
                    )
            )

        layer.text = "ROTATED"
        layer.rotation = 90

        project.layers = [
            layer
        ]

        let issues =
            PhysicalBookDiagnostics
                .spineTextIssues(
                    project: project
                )

        XCTAssertTrue(
            issues.contains {
                $0.kind
                    == .spineTooNarrow
            }
        )

        XCTAssertTrue(
            issues.contains {
                $0.kind
                    == .outsideSpineTrim
                    || $0.kind
                        == .widerThanSafeSpine
                    || $0.kind
                        == .insufficientFoldClearance
            }
        )
    }

    func testUnsafeSpineTextCreatesVisibleFoldWarnings() throws {
        var project =
            CoverProject(
                type: .printFullWrap
            )

        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8
        project.bleed = 0.125
        project.canvasWidth = 13.05
        project.canvasHeight = 9.25

        let spine =
            CoverWrapGeometry(
                project: project
            )
            .spineTrim

        var layer =
            CoverLayer(
                kind: .text,
                name: "Unsafe Spine",
                frame:
                    CoverRect(
                        x:
                            spine.x
                            - spine.width * 0.05,
                        y:
                            spine.y
                            + spine.height * 0.20,
                        width:
                            spine.width * 0.80,
                        height:
                            spine.height * 0.60
                    )
            )

        layer.text = "UNSAFE"

        project.layers = [
            layer
        ]

        let scene =
            BookPreviewScene.make(
                project: project,
                workingLayers: false,
                open: false,
                angle: 0,
                leftPage: nil,
                rightPage: 1,
                pageCount: 40,
                spreadIndex: 0,
                leftTexture: nil,
                rightTexture: nil,
                margins: false,
                thumbMode: .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset: .spine,
                revisionID: UUID(),
                binding: .softcover
            )

        let artwork =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "book-shell.spine-artwork",
                        recursively: true
                    )
            )

        XCTAssertNotNil(
            artwork.childNode(
                withName:
                    "diagnostic.spine.left-fold",
                recursively: false
            )
        )

        XCTAssertNotNil(
            artwork.childNode(
                withName:
                    "diagnostic.spine.right-fold",
                recursively: false
            )
        )

        let workingScene =
            BookPreviewScene.make(
                project: project,
                workingLayers: true,
                open: false,
                angle: 0,
                leftPage: nil,
                rightPage: 1,
                pageCount: 40,
                spreadIndex: 0,
                leftTexture: nil,
                rightTexture: nil,
                margins: false,
                thumbMode: .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset: .spine,
                revisionID: UUID(),
                binding: .softcover
            )

        let workingArtwork =
            try XCTUnwrap(
                workingScene.rootNode
                    .childNode(
                        withName:
                            "book-shell.spine-artwork",
                        recursively: true
                    )
            )

        XCTAssertNil(
            workingArtwork.childNode(
                withName:
                    "diagnostic.spine.left-fold",
                recursively: false
            )
        )
    }

    func testCoverEdgeIssuesCreateVisiblePhysicalWarningStrips() throws {
        let front =
            SCNNode(
                geometry:
                    SCNBox(
                        width: 4.2,
                        height: 6.3,
                        length: 0.02,
                        chamferRadius: 0
                    )
            )

        let issues = [
            PhysicalBookCoverEdgeIssue(
                panel: .front,
                edge: .outer,
                message: "Outer"
            ),
            PhysicalBookCoverEdgeIssue(
                panel: .front,
                edge: .top,
                message: "Top"
            ),
            PhysicalBookCoverEdgeIssue(
                panel: .back,
                edge: .bottom,
                message: "Back"
            )
        ]

        BookPreviewScene
            .addCoverEdgeIssueOverlays(
                to: front,
                panel: .front,
                exteriorFacesPositiveZ: true,
                issues: issues
            )

        let outer =
            try XCTUnwrap(
                front.childNode(
                    withName:
                        "diagnostic.cover.front.outer",
                    recursively: false
                )
            )

        let top =
            try XCTUnwrap(
                front.childNode(
                    withName:
                        "diagnostic.cover.front.top",
                    recursively: false
                )
            )

        XCTAssertNil(
            front.childNode(
                withName:
                    "diagnostic.cover.back.bottom",
                recursively: false
            )
        )

        XCTAssertTrue(
            outer.geometry is SCNPlane
        )

        XCTAssertTrue(
            top.geometry is SCNPlane
        )

        XCTAssertGreaterThan(
            outer.position.x,
            0
        )

        XCTAssertGreaterThan(
            top.position.y,
            0
        )

        XCTAssertGreaterThan(
            outer.position.z,
            0
        )

        XCTAssertEqual(
            outer.renderingOrder,
            100
        )
    }

    func testPhysicalBookSceneUsesStudioLightingAndContactGround() throws {
        var project =
            CoverProject(
                type: .printFullWrap
            )

        project.trimWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8

        let scene =
            BookPreviewScene.make(
                project: project,
                workingLayers: false,
                open: true,
                angle: 120,
                leftPage: 10,
                rightPage: 11,
                pageCount: 40,
                spreadIndex: 5,
                leftTexture: nil,
                rightTexture: nil,
                margins: false,
                thumbMode: .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset: .perspective,
                revisionID: UUID(),
                binding: .hardcover
            )

        let ambientNode =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "studio-light.ambient",
                        recursively: true
                    )
            )

        let keyNode =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "studio-light.key",
                        recursively: true
                    )
            )

        let fillNode =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "studio-light.fill",
                        recursively: true
                    )
            )

        let rimNode =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "studio-light.rim",
                        recursively: true
                    )
            )

        let groundNode =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "studio-ground",
                        recursively: true
                    )
            )

        XCTAssertEqual(
            ambientNode.light?.type,
            .ambient
        )

        XCTAssertEqual(
            keyNode.light?.type,
            .directional
        )

        XCTAssertEqual(
            fillNode.light?.type,
            .directional
        )

        XCTAssertEqual(
            rimNode.light?.type,
            .directional
        )

        XCTAssertEqual(
            keyNode.light?.castsShadow,
            true
        )

        XCTAssertEqual(
            fillNode.light?.castsShadow,
            false
        )

        XCTAssertEqual(
            rimNode.light?.castsShadow,
            false
        )

        XCTAssertGreaterThan(
            keyNode.light?
                .shadowSampleCount
                ?? 0,
            1
        )

        XCTAssertGreaterThan(
            keyNode.light?
                .shadowRadius
                ?? 0,
            0
        )

        let ground =
            try XCTUnwrap(
                groundNode.geometry
                    as? SCNPlane
            )

        XCTAssertGreaterThan(
            ground.width,
            0
        )

        XCTAssertGreaterThan(
            ground.height,
            0
        )

        XCTAssertEqual(
            groundNode.eulerAngles.x,
            -.pi / 2,
            accuracy: 0.0001
        )

        XCTAssertLessThan(
            groundNode.position.y,
            0
        )

        let groundMaterial =
            try XCTUnwrap(
                ground.materials.first
            )

        XCTAssertEqual(
            groundMaterial.lightingModel,
            .physicallyBased
        )

        let book =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively: false
                    )
            )

        let rightBlock =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book.right-page-block",
                    recursively: false
                )
            )

        let block =
            try XCTUnwrap(
                rightBlock.geometry
                    as? SCNBox
            )

        XCTAssertGreaterThanOrEqual(
            block.materials.count,
            2
        )

        XCTAssertEqual(
            block.materials[0]
                .lightingModel,
            .physicallyBased
        )

        XCTAssertEqual(
            block.materials[1]
                .lightingModel,
            .physicallyBased
        )

        let cameraNode =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "preview-camera",
                        recursively: true
                    )
            )

        let camera =
            try XCTUnwrap(
                cameraNode.camera
            )

        XCTAssertEqual(
            camera.fieldOfView,
            34,
            accuracy: 0.000001
        )
    }



    func testOpenPageBlocksAddBoundStackSwellWithoutChangingStackDepth() throws {
        let gutter =
            BookPreviewScene
                .pageStackSwellOffset(
                    distanceFromGutter:
                        0
                )

        let shoulder =
            BookPreviewScene
                .pageStackSwellOffset(
                    distanceFromGutter:
                        0.35
                )

        let foreEdge =
            BookPreviewScene
                .pageStackSwellOffset(
                    distanceFromGutter:
                        1
                )

        XCTAssertLessThan(
            gutter,
            0
        )

        XCTAssertGreaterThan(
            shoulder,
            gutter
        )

        XCTAssertGreaterThan(
            shoulder,
            foreEdge
        )

        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth = 6
        project.trimHeight = 9
        project.spineWidth = 1.2

        let physicalGeometry =
            PhysicalBookGeometry(
                project:
                    project
            )

        let stacks =
            PhysicalBookGeometry
                .pageStacks(
                    pageCount:
                        40,
                    spreadIndex:
                        5,
                    totalDepth:
                        physicalGeometry
                            .pageBlockDepth(
                                for:
                                    .softcover
                            )
                )

        let scene =
            BookPreviewScene.make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    180,
                leftPage:
                    10,
                rightPage:
                    11,
                pageCount:
                    40,
                spreadIndex:
                    5,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID(),
                binding:
                    .softcover
            )

        let book =
            try XCTUnwrap(
                scene.rootNode.childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let leftBlock =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book.left-page-block",
                    recursively:
                        true
                )
            )

        let rightBlock =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        true
                )
            )

        let leftBox =
            try XCTUnwrap(
                leftBlock.geometry
                    as? SCNBox
            )

        let rightBox =
            try XCTUnwrap(
                rightBlock.geometry
                    as? SCNBox
            )

        XCTAssertEqual(
            leftBox.length,
            CGFloat(
                stacks.leftDepth
                * 0.7
            ),
            accuracy:
                0.00001,
            "Visible swell must not alter authoritative left stack thickness"
        )

        XCTAssertEqual(
            rightBox.length,
            CGFloat(
                stacks.rightDepth
                * 0.7
            ),
            accuracy:
                0.00001,
            "Visible swell must not alter authoritative right stack thickness"
        )

        let leftSwell =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book.left-page-stack-swell",
                    recursively:
                        true
                )
            )

        let rightSwell =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book.right-page-stack-swell",
                    recursively:
                        true
                )
            )

        func vertexZRange(
            _ node:
                SCNNode
        ) throws -> CGFloat {
            let geometry =
                try XCTUnwrap(
                    node.geometry
                )

            let source =
                try XCTUnwrap(
                    geometry
                        .sources(
                            for:
                                .vertex
                        )
                        .first
                )

            XCTAssertGreaterThan(
                source.vectorCount,
                4
            )

            XCTAssertGreaterThanOrEqual(
                source.componentsPerVector,
                3
            )

            XCTAssertEqual(
                source.bytesPerComponent,
                4,
                "Physical paper swell vertices are expected to be Float32"
            )

            var minimum =
                CGFloat.greatestFiniteMagnitude

            var maximum =
                -CGFloat.greatestFiniteMagnitude

            source.data.withUnsafeBytes {
                rawBuffer in

                for index in 0..<source.vectorCount {
                    let offset =
                        source.dataOffset
                        + index
                        * source.dataStride
                        + 2
                        * source.bytesPerComponent

                    let value =
                        rawBuffer.loadUnaligned(
                            fromByteOffset:
                                offset,
                            as:
                                Float.self
                        )

                    let z =
                        CGFloat(
                            value
                        )

                    minimum =
                        min(
                            minimum,
                            z
                        )

                    maximum =
                        max(
                            maximum,
                            z
                        )
                }
            }

            return maximum - minimum
        }

        let leftRange =
            try vertexZRange(
                leftSwell
            )

        let rightRange =
            try vertexZRange(
                rightSwell
            )

        XCTAssertGreaterThan(
            leftRange,
            0.001,
            "Actual left swell mesh vertices must contain visible depth curvature"
        )

        XCTAssertGreaterThan(
            rightRange,
            0.001,
            "Actual right swell mesh vertices must contain visible depth curvature"
        )
    }

    func testPageBlocksKeepAggregateGeometryAndShowExposedEdgeStrata() throws {
        var project =
            CoverProject(
                type: .printFullWrap
            )

        project.trimWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8

        let openScene =
            BookPreviewScene.make(
                project: project,
                workingLayers: false,
                open: true,
                angle: 120,
                leftPage: 10,
                rightPage: 11,
                pageCount: 40,
                spreadIndex: 5,
                leftTexture: nil,
                rightTexture: nil,
                margins: false,
                thumbMode: .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset: .perspective,
                revisionID: UUID(),
                binding: .softcover
            )

        let openBook =
            try XCTUnwrap(
                openScene.rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively: false
                    )
            )

        let leftBlock =
            try XCTUnwrap(
                openBook.childNode(
                    withName:
                        "book.left-page-block",
                    recursively: true
                )
            )

        let rightBlock =
            try XCTUnwrap(
                openBook.childNode(
                    withName:
                        "book.right-page-block",
                    recursively: false
                )
            )

        XCTAssertTrue(
            leftBlock.geometry is SCNBox
        )

        XCTAssertTrue(
            rightBlock.geometry is SCNBox
        )

        let leftStrata =
            try XCTUnwrap(
                leftBlock.childNode(
                    withName:
                        "book.left-page-edge-strata",
                    recursively: false
                )
            )

        let rightStrata =
            try XCTUnwrap(
                rightBlock.childNode(
                    withName:
                        "book.right-page-edge-strata",
                    recursively: false
                )
            )

        XCTAssertTrue(
            leftStrata.geometry is SCNPlane
        )

        XCTAssertTrue(
            rightStrata.geometry is SCNPlane
        )

        XCTAssertLessThan(
            leftStrata.position.x,
            0
        )

        XCTAssertGreaterThan(
            rightStrata.position.x,
            0
        )

        XCTAssertTrue(
            leftStrata.parent === leftBlock
        )

        XCTAssertTrue(
            rightStrata.parent === rightBlock
        )

        for (block, prefix) in [
            (leftBlock, "book.left-page-edge-strata"),
            (rightBlock, "book.right-page-edge-strata")
        ] {
            let head = try XCTUnwrap(block.childNode(withName: prefix + ".head", recursively: false))
            let tail = try XCTUnwrap(block.childNode(withName: prefix + ".tail", recursively: false))
            XCTAssertGreaterThan(head.position.y, 0)
            XCTAssertLessThan(tail.position.y, 0)
            XCTAssertTrue(head.geometry?.firstMaterial?.diffuse.contents is NSImage)
            XCTAssertTrue(tail.geometry?.firstMaterial?.diffuse.contents is NSImage)
        }

        let closedScene =
            BookPreviewScene.make(
                project: project,
                workingLayers: false,
                open: false,
                angle: 0,
                leftPage: nil,
                rightPage: 1,
                pageCount: 40,
                spreadIndex: 0,
                leftTexture: nil,
                rightTexture: nil,
                margins: false,
                thumbMode: .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset: .perspective,
                revisionID: UUID(),
                binding: .hardcover
            )

        let closedBlock =
            try XCTUnwrap(
                closedScene.rootNode
                    .childNode(
                        withName:
                            "book.closed-page-block",
                        recursively: true
                    )
            )

        XCTAssertTrue(
            closedBlock.geometry is SCNBox
        )

        let closedStrata =
            try XCTUnwrap(
                closedBlock.childNode(
                    withName:
                        "book.closed-page-edge-strata",
                    recursively: false
                )
            )

        XCTAssertTrue(
            closedStrata.geometry is SCNPlane
        )

        XCTAssertGreaterThan(
            closedStrata.position.x,
            0
        )
        XCTAssertNotNil(closedBlock.childNode(withName: "book.closed-page-edge-strata.head", recursively: false))
        XCTAssertNotNil(closedBlock.childNode(withName: "book.closed-page-edge-strata.tail", recursively: false))
    }

    func testHardcoverHasRigidBoardJointAndHingeGrooveOnlyForCaseBinding() throws {
        var project =
            CoverProject(
                type: .printFullWrap
            )

        project.trimWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8

        func scene(
            binding: BookBinding
        ) -> SCNScene {
            BookPreviewScene.make(
                project: project,
                workingLayers: false,
                open: true,
                angle: 120,
                leftPage: 2,
                rightPage: 3,
                pageCount: 20,
                spreadIndex: 1,
                leftTexture: nil,
                rightTexture: nil,
                margins: false,
                thumbMode: .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset: .perspective,
                revisionID: UUID(),
                binding: binding
            )
        }

        let hardBook =
            try XCTUnwrap(
                scene(binding: .hardcover)
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively: false
                    )
            )

        let softBook =
            try XCTUnwrap(
                scene(binding: .softcover)
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively: false
                    )
            )

        let hardFront =
            try XCTUnwrap(
                hardBook.childNode(
                    withName:
                        "book-shell.front-cover",
                    recursively: false
                )
            )

        let hardBack =
            try XCTUnwrap(
                hardBook.childNode(
                    withName:
                        "book-shell.back-cover",
                    recursively: false
                )
            )

        XCTAssertTrue(
            hardFront.geometry is SCNBox
        )

        XCTAssertTrue(
            hardBack.geometry is SCNBox
        )

        let frontJoint =
            try XCTUnwrap(
                hardFront.childNode(
                    withName:
                        "book-shell.front-joint",
                    recursively: false
                )
            )

        let backJoint =
            try XCTUnwrap(
                hardBack.childNode(
                    withName:
                        "book-shell.back-joint",
                    recursively: false
                )
            )

        let frontGroove =
            try XCTUnwrap(
                hardFront.childNode(
                    withName:
                        "book-shell.front-hinge-groove",
                    recursively: false
                )
            )

        let backGroove =
            try XCTUnwrap(
                hardBack.childNode(
                    withName:
                        "book-shell.back-hinge-groove",
                    recursively: false
                )
            )

        XCTAssertTrue(
            frontJoint.geometry is SCNPlane
        )

        XCTAssertTrue(
            backJoint.geometry is SCNPlane
        )

        XCTAssertTrue(
            frontGroove.geometry is SCNPlane
        )

        XCTAssertTrue(
            backGroove.geometry is SCNPlane
        )

        XCTAssertTrue(
            frontJoint.parent === hardFront
        )

        XCTAssertTrue(
            frontGroove.parent === hardFront
        )

        XCTAssertLessThan(
            frontJoint.position.x,
            0
        )

        XCTAssertNotEqual(
            hardFront.eulerAngles.y,
            0,
            "Hardcover board should rotate rigidly while its joint follows it"
        )

        XCTAssertNil(
            softBook.childNode(
                withName:
                    "book-shell.front-joint",
                recursively: true
            )
        )

        XCTAssertNil(
            softBook.childNode(
                withName:
                    "book-shell.back-joint",
                recursively: true
            )
        )

        XCTAssertNil(
            softBook.childNode(
                withName:
                    "book-shell.front-hinge-groove",
                recursively: true
            )
        )
    }

    func testBindingChangesBoardThicknessAndOpenCoverSupportsTurnedStack() throws {
        var project = CoverProject(type: .printFullWrap)
        project.trimWidth = 6; project.trimHeight = 9; project.spineWidth = 1.25
        let geometry = PhysicalBookGeometry(project: project)
        XCTAssertGreaterThan(geometry.coverThickness(for: .hardcover), geometry.coverThickness(for: .softcover))
        XCTAssertEqual(
            geometry.pageBlockDepth(for: .softcover),
            geometry.pageBlockDepth(for: .hardcover),
            accuracy: 0.000001,
            "Paper-stack depth is determined by page count and paper caliper, not cover binding."
        )
        let scenes = BookBinding.allCases.map { binding in
            BookPreviewScene.make(project: project, workingLayers: false, open: true, angle: 180,
                                  leftPage: 2, rightPage: 3, pageCount: 20, spreadIndex: 1,
                                  leftTexture: nil, rightTexture: nil, margins: false, thumbMode: .off,
                                  leftPageSettings: PageSettings(), rightPageSettings: PageSettings(),
                                  preset: .perspective, revisionID: UUID(), binding: binding)
        }
        let soft = try XCTUnwrap(scenes[0].rootNode.childNode(withName: "book-shell.front-cover", recursively: true))
        let hard = try XCTUnwrap(scenes[1].rootNode.childNode(withName: "book-shell.front-cover", recursively: true))
        XCTAssertLessThan(soft.position.x, 0)
        XCTAssertLessThan(hard.position.x, 0)
        let leftBlock = try XCTUnwrap(scenes[0].rootNode.childNode(withName: "book.left-page-block", recursively: true))
        let root = try XCTUnwrap(scenes[0].rootNode.childNode(withName: "physical-book.root", recursively: true))
        let blockCenter = leftBlock.convertPosition(SCNVector3Zero, to: root)
        XCTAssertLessThan(soft.position.z, blockCenter.z, "The front cover supports the turned paper block.")
    }

    func testDetectsUnequalMarginsRepeatedAcrossFacingPages() {
        var odd = PageSettings(); odd.leftMargin = 72; odd.rightMargin = 36
        var even = odd
        XCTAssertTrue(PhysicalBookDiagnostics.hasUnmirroredMargins(pages: [odd, even]))
        even.leftMargin = 36; even.rightMargin = 72
        XCTAssertFalse(PhysicalBookDiagnostics.hasUnmirroredMargins(pages: [odd, even]))
    }

    func testMarginIntrusionsReportEachEdgeAndSafeContentRemainsClear() {
        let safe = PhysicalBookGeometry.marginIntrusions(content: CoverRect(x: 0.75, y: 0.75, width: 4.5, height: 7.5), pageWidth: 6, pageHeight: 9, left: 0.5, right: 0.5, top: 0.5, bottom: 0.5)
        XCTAssertTrue(safe.isEmpty)
        let unsafe = PhysicalBookGeometry.marginIntrusions(content: CoverRect(x: 0.3, y: 0.2, width: 5.6, height: 8.6), pageWidth: 6, pageHeight: 9, left: 0.5, right: 0.5, top: 0.5, bottom: 0.5)
        XCTAssertEqual(unsafe.left, 0.2, accuracy: 0.000001)
        XCTAssertEqual(unsafe.right, 0.4, accuracy: 0.000001)
        XCTAssertEqual(unsafe.top, 0.3, accuracy: 0.000001)
        XCTAssertEqual(unsafe.bottom, 0.3, accuracy: 0.000001)
    }

    func testProductionCoverArtworkOmitsTemplateWhileWorkingLayersIncludesIt() throws {
        let project = CoverProject(type: .printFullWrap, width: 4, height: 2)
        var base = CoverLayer(kind: .shape, name: "Artwork", frame: CoverRect(x: 0, y: 0, width: 1, height: 1)); base.fillHex = "#FF0000"
        var template = CoverLayer(kind: .template, name: "KDP guide", frame: CoverRect(x: 0, y: 0, width: 1, height: 1)); template.fillHex = "#0000FF"; template.opacity = 0.5
        var source = project; source.layers = [base, template]
        let print = try CoverArtwork.render(source, includeGuides: false, includeTemplate: false, scale: 20)
        let working = try CoverArtwork.render(source, includeGuides: true, includeTemplate: true, scale: 20)
        XCTAssertNotEqual(try XCTUnwrap(print.tiffRepresentation), try XCTUnwrap(working.tiffRepresentation))
    }

    func testProductionTextureCropsSelectBackSpineAndFrontRectangles() throws {
        var project = CoverProject(type: .printFullWrap, width: 3.2, height: 1.2)
        project.trimWidth = 1; project.backWidth = 1; project.trimHeight = 1; project.spineWidth = 1; project.bleed = 0.1
        let regions = CoverWrapGeometry(project: project)
        for (name, region, color) in [("back", regions.backTrim, "#FF0000"), ("spine", regions.spineTrim, "#00FF00"), ("front", regions.frontTrim, "#0000FF")] {
            var layer = CoverLayer(kind: .shape, name: name, frame: region); layer.fillHex = color; project.layers.append(layer)
        }
        let textures = PhysicalBookCoverTextures(project: project, workingLayers: false, previewDPI: 24)
        let back = try XCTUnwrap(textures.back), spine = try XCTUnwrap(textures.spine), front = try XCTUnwrap(textures.front)
        XCTAssertGreaterThan(back.size.width, 1); XCTAssertGreaterThan(spine.size.width, 1); XCTAssertGreaterThan(front.size.width, 1)
        XCTAssertGreaterThan(try centerColor(back).redComponent, 0.8)
        XCTAssertGreaterThan(try centerColor(spine).greenComponent, 0.8)
        XCTAssertGreaterThan(try centerColor(front).blueComponent, 0.8)
        XCTAssertFalse(
            textures.edgeWarnings.isEmpty,
            "Artwork stopping at the trim must raise a possible bleed sliver warning"
        )

        XCTAssertFalse(
            textures.edgeIssues.isEmpty,
            "Bleed inspection must retain the physical panel and edge location"
        )

        XCTAssertEqual(
            textures.edgeIssues.map(\.message),
            textures.edgeWarnings
        )
    }


    private func centerColor(_ image: NSImage) throws -> NSColor {
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        return try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
    }
}


final class CompatibilityPreservingPhysicalPoseTests:
    XCTestCase
{
    private func project() -> CoverProject {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        return project
    }

    func testPhysicalPoseConservesPageBlockDepth() {
        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        let pose =
            geometry.physicalPose(
                open:
                    true,
                angleDegrees:
                    180,
                pageCount:
                    300,
                spreadIndex:
                    75,
                binding:
                    .hardcover
            )

        XCTAssertEqual(
            pose.stacks.leftDepth
                + pose.stacks.rightDepth,
            geometry
                .pageBlockDepth(
                    for:
                        .hardcover
                ),
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            pose.stacks.leftDepth,
            pose.stacks.rightDepth,
            accuracy:
                0.000_001
        )
    }

    func testPhysicalPoseRedistributesMassAcrossSpread() {
        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        let early =
            geometry.physicalPose(
                open:
                    true,
                angleDegrees:
                    180,
                pageCount:
                    300,
                spreadIndex:
                    20,
                binding:
                    .softcover
            )

        let late =
            geometry.physicalPose(
                open:
                    true,
                angleDegrees:
                    180,
                pageCount:
                    300,
                spreadIndex:
                    125,
                binding:
                    .softcover
            )

        XCTAssertLessThan(
            early.stacks.leftDepth,
            early.stacks.rightDepth
        )

        XCTAssertGreaterThan(
            late.stacks.leftDepth,
            late.stacks.rightDepth
        )

        XCTAssertLessThan(
            early.pageBalanceDegrees,
            0
        )

        XCTAssertGreaterThan(
            late.pageBalanceDegrees,
            0
        )
    }

    func testPaperbackFlexesMoreThanHardcover() {
        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        let hard =
            geometry.physicalPose(
                open:
                    true,
                angleDegrees:
                    180,
                pageCount:
                    300,
                spreadIndex:
                    75,
                binding:
                    .hardcover
            )

        let soft =
            geometry.physicalPose(
                open:
                    true,
                angleDegrees:
                    180,
                pageCount:
                    300,
                spreadIndex:
                    75,
                binding:
                    .softcover
            )

        XCTAssertGreaterThan(
            soft.pageStackLiftDegrees,
            hard.pageStackLiftDegrees
        )

        XCTAssertGreaterThan(
            soft.backCoverLiftDegrees,
            hard.backCoverLiftDegrees
        )

        XCTAssertGreaterThan(
            soft.gutterDrop,
            hard.gutterDrop
        )

        XCTAssertGreaterThan(
            soft.foreEdgeLift,
            hard.foreEdgeLift
        )
    }

    func testClosedPoseHasNoRestingLift() {
        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        let pose =
            geometry.physicalPose(
                open:
                    false,
                angleDegrees:
                    180,
                pageCount:
                    300,
                spreadIndex:
                    75,
                binding:
                    .hardcover
            )

        XCTAssertEqual(
            pose.openProgress,
            0,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            pose.pageStackLiftDegrees,
            0,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            pose.backCoverLiftDegrees,
            0,
            accuracy:
                0.000_001
        )
    }

    func testLegacySceneHierarchyRemainsIntact() throws {
        let project =
            project()

        let scene =
            BookPreviewScene.make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    180,
                leftPage:
                    150,
                rightPage:
                    151,
                pageCount:
                    300,
                spreadIndex:
                    75,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID(),
                binding:
                    .hardcover
            )

        let book =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
            )

        let front =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book-shell.front-cover",
                    recursively:
                        false
                )
            )

        let back =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book-shell.back-cover",
                    recursively:
                        false
                )
            )

        let spine =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book-shell.spine",
                    recursively:
                        false
                )
            )

        let leaves =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book.left-leaves",
                    recursively:
                        false
                )
            )

        let leftBlock =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book.left-page-block",
                    recursively:
                        true
                )
            )

        let rightBlock =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        false
                )
            )

        let rightActive =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book.right-active-page",
                    recursively:
                        false
                )
            )

        XCTAssertTrue(
            front.parent === book
        )

        XCTAssertTrue(
            back.parent === book
        )

        XCTAssertTrue(
            spine.parent === book
        )

        XCTAssertTrue(
            leaves.parent === book
        )

        XCTAssertTrue(
            leftBlock.parent === leaves
        )

        XCTAssertTrue(
            rightBlock.parent === book
        )

        XCTAssertTrue(
            rightActive.parent === book
        )

        XCTAssertGreaterThan(
            abs(
                Double(
                    leftBlock.pivot.m41
                )
            ),
            0
        )

        XCTAssertGreaterThan(
            abs(
                Double(
                    rightBlock.pivot.m41
                )
            ),
            0
        )

        XCTAssertGreaterThan(
            leftBlock.eulerAngles.y,
            0
        )

        XCTAssertLessThan(
            rightBlock.eulerAngles.y,
            0
        )

        XCTAssertLessThan(
            rightActive.eulerAngles.y,
            0
        )

        XCTAssertLessThan(
            back.eulerAngles.y,
            0
        )
    }

    func testOpenCoversAndLeavesShareContinuousOpeningHinges() throws {
        let project =
            project()

        let geometry =
            PhysicalBookGeometry(
                project:
                    project
            )

        let scene =
            BookPreviewScene.make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    45,
                leftPage:
                    2,
                rightPage:
                    3,
                pageCount:
                    20,
                spreadIndex:
                    1,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID()
            )

        let book =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
            )

        let front =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book-shell.front-cover",
                    recursively:
                        false
                )
            )

        let leaves =
            try XCTUnwrap(
                book.childNode(
                    withName:
                        "book.left-leaves",
                    recursively:
                        false
                )
            )

        XCTAssertLessThan(abs(front.position.x), CGFloat(geometry.trimWidth * 0.7 / 2))

        XCTAssertEqual(
            leaves.eulerAngles.y,
            CGFloat(
                135
                * Double.pi
                / 180
            ),
            accuracy:
                0.000_001
        )
    }
}


final class ContinuousPageMassTransferTests:
    XCTestCase
{
    private func project() -> CoverProject {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        return project
    }

    func testForwardTurnConservesPaperMassAtQuarterSteps() {
        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        let total =
            geometry
            .pageBlockDepth(
                for:
                    .softcover
            )

        for progress in [
            0.0,
            0.25,
            0.5,
            0.75,
            1.0
        ] {
            let transfer =
                geometry
                .pageTurnMassTransfer(
                    pageCount:
                        300,
                    fromSpread:
                        40,
                    toSpread:
                        41,
                    progress:
                        progress,
                    binding:
                        .softcover
                )

            XCTAssertEqual(
                transfer.conservedDepth,
                total,
                accuracy:
                    0.000_001
            )
        }
    }

    func testForwardTurnMatchesStaticSourceAndDestinationEndpoints() {
        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        let total =
            geometry
            .pageBlockDepth(
                for:
                    .hardcover
            )

        let source =
            PhysicalBookGeometry
            .pageStacks(
                pageCount:
                    300,
                spreadIndex:
                    40,
                totalDepth:
                    total
            )

        let destination =
            PhysicalBookGeometry
            .pageStacks(
                pageCount:
                    300,
                spreadIndex:
                    41,
                totalDepth:
                    total
            )

        let start =
            geometry
            .pageTurnMassTransfer(
                pageCount:
                    300,
                fromSpread:
                    40,
                toSpread:
                    41,
                progress:
                    0,
                binding:
                    .hardcover
            )

        let finish =
            geometry
            .pageTurnMassTransfer(
                pageCount:
                    300,
                fromSpread:
                    40,
                toSpread:
                    41,
                progress:
                    1,
                binding:
                    .hardcover
            )

        XCTAssertEqual(
            start.leftDepth,
            source.leftDepth,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            start.rightDepth,
            source.rightDepth,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            start.movingSheetDepth,
            0,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            finish.leftDepth,
            destination.leftDepth,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            finish.rightDepth,
            destination.rightDepth,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            finish.movingSheetDepth,
            0,
            accuracy:
                0.000_001
        )
    }

    func testEntireTransferredLeafIsInFlightAtMidpoint() {
        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        let middle =
            geometry
            .pageTurnMassTransfer(
                pageCount:
                    300,
                fromSpread:
                    40,
                toSpread:
                    41,
                progress:
                    0.5,
                binding:
                    .softcover
            )

        XCTAssertGreaterThan(
            middle.transferDepth,
            0
        )

        XCTAssertEqual(
            middle.movingSheetDepth,
            middle.transferDepth,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            middle.sourceSide,
            .right
        )

        XCTAssertEqual(
            middle.destinationSide,
            .left
        )
    }

    func testBackwardTurnConservesMassAndReversesSides() {
        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        let total =
            geometry
            .pageBlockDepth(
                for:
                    .softcover
            )

        for progress in [
            0.0,
            0.25,
            0.5,
            0.75,
            1.0
        ] {
            let transfer =
                geometry
                .pageTurnMassTransfer(
                    pageCount:
                        300,
                    fromSpread:
                        41,
                    toSpread:
                        40,
                    progress:
                        progress,
                    binding:
                        .softcover
                )

            XCTAssertEqual(
                transfer.conservedDepth,
                total,
                accuracy:
                    0.000_001
            )

            XCTAssertEqual(
                transfer.sourceSide,
                .left
            )

            XCTAssertEqual(
                transfer.destinationSide,
                .right
            )
        }
    }

    func testScenePageBlocksChangeThicknessDuringForwardTurn() throws {
        let project =
            project()

        let scene =
            BookPreviewScene.make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    180,
                leftPage:
                    80,
                rightPage:
                    81,
                pageCount:
                    300,
                spreadIndex:
                    40,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID(),
                binding:
                    .softcover
            )

        let root =
            try XCTUnwrap(
                scene.rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let leaves =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.left-leaves",
                    recursively:
                        false
                )
            )

        let left =
            try XCTUnwrap(
                leaves.childNode(
                    withName:
                        "book.left-page-block",
                    recursively:
                        false
                )
            )

        let right =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        false
                )
            )

        let leftBox =
            try XCTUnwrap(
                left.geometry
                as? SCNBox
            )

        let rightBox =
            try XCTUnwrap(
                right.geometry
                as? SCNBox
            )

        let sourceLeft =
            leftBox.length

        let sourceRight =
            rightBox.length

        var navigation =
            BookPageTurnState()

        navigation.jump(
            to:
                40,
            maximumSpread:
                150
        )

        let transition =
            try XCTUnwrap(
                navigation.begin(
                    to:
                        41,
                    maximumSpread:
                        150
                )
            )

        BookPreviewScene
        .applyPageTurnMassTransfer(
            in:
                scene,
            project:
                project,
            pageCount:
                300,
            binding:
                .softcover,
            transition:
                transition,
            progress:
                0.25
        )

        XCTAssertEqual(
            leftBox.length,
            sourceLeft,
            accuracy:
                0.000_001
        )

        XCTAssertLessThan(
            rightBox.length,
            sourceRight
        )

        let quarterRight =
            rightBox.length

        BookPreviewScene
        .applyPageTurnMassTransfer(
            in:
                scene,
            project:
                project,
            pageCount:
                300,
            binding:
                .softcover,
            transition:
                transition,
            progress:
                0.75
        )

        XCTAssertLessThanOrEqual(
            rightBox.length,
            quarterRight
        )

        XCTAssertGreaterThan(
            leftBox.length,
            sourceLeft
        )
    }

    func testMassTransferDoesNotReparentExistingStacks() throws {
        let project =
            project()

        let scene =
            BookPreviewScene.make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    180,
                leftPage:
                    80,
                rightPage:
                    81,
                pageCount:
                    300,
                spreadIndex:
                    40,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID(),
                binding:
                    .hardcover
            )

        let root =
            try XCTUnwrap(
                scene.rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let leaves =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.left-leaves",
                    recursively:
                        false
                )
            )

        let right =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        false
                )
            )

        let left =
            try XCTUnwrap(
                leaves.childNode(
                    withName:
                        "book.left-page-block",
                    recursively:
                        false
                )
            )

        var navigation =
            BookPageTurnState()

        navigation.jump(
            to:
                40,
            maximumSpread:
                150
        )

        let transition =
            try XCTUnwrap(
                navigation.begin(
                    to:
                        41,
                    maximumSpread:
                        150
                )
            )

        BookPreviewScene
        .applyPageTurnMassTransfer(
            in:
                scene,
            project:
                project,
            pageCount:
                300,
            binding:
                .hardcover,
            transition:
                transition,
            progress:
                0.5
        )

        XCTAssertTrue(
            right.parent
            === root
        )

        XCTAssertTrue(
            left.parent
            === leaves
        )
    }
}


final class PhysicalPageFanTests:
    XCTestCase
{
    private func project() -> CoverProject {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        return project
    }

    private func openScene(
        binding:
            BookBinding = .softcover,
        spreadIndex:
            Int = 75
    ) -> SCNScene {
        BookPreviewScene.make(
            project:
                project(),
            workingLayers:
                false,
            open:
                true,
            angle:
                180,
            leftPage:
                150,
            rightPage:
                151,
            pageCount:
                300,
            spreadIndex:
                spreadIndex,
            leftTexture:
                nil,
            rightTexture:
                nil,
            margins:
                false,
            thumbMode:
                .off,
            leftPageSettings:
                PageSettings(),
            rightPageSettings:
                PageSettings(),
            preset:
                .perspective,
            revisionID:
                UUID(),
            binding:
                binding
        )
    }

    private func blocks(
        in scene:
            SCNScene
    ) throws -> (
        left: SCNNode,
        right: SCNNode
    ) {
        let root =
            try XCTUnwrap(
                scene.rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let leaves =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.left-leaves",
                    recursively:
                        false
                )
            )

        let left =
            try XCTUnwrap(
                leaves.childNode(
                    withName:
                        "book.left-page-block",
                    recursively:
                        false
                )
            )

        let right =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        false
                )
            )

        return (
            left,
            right
        )
    }

    func testOpenStacksReceiveTwelveFanRibbons() throws {
        let pair =
            try blocks(
                in:
                    openScene()
            )

        let leftFan =
            try XCTUnwrap(
                pair.left
                .childNode(
                    withName:
                        "book.left-page-fan",
                    recursively:
                        false
                )
            )

        let rightFan =
            try XCTUnwrap(
                pair.right
                .childNode(
                    withName:
                        "book.right-page-fan",
                    recursively:
                        false
                )
            )

        XCTAssertEqual(
            leftFan.childNodes.count,
            12
        )

        XCTAssertEqual(
            rightFan.childNodes.count,
            12
        )

        XCTAssertTrue(
            leftFan.parent
            === pair.left
        )

        XCTAssertTrue(
            rightFan.parent
            === pair.right
        )
    }

    func testPaperbackFanEnvelopeIsLargerThanHardcover() {
        let hardcover =
            BookPreviewScene
            .pageFanEnvelope(
                binding:
                    .hardcover,
                fullness:
                    1,
                blockWidth:
                    4.2,
                totalDepth:
                    0.8
            )

        let paperback =
            BookPreviewScene
            .pageFanEnvelope(
                binding:
                    .softcover,
                fullness:
                    1,
                blockWidth:
                    4.2,
                totalDepth:
                    0.8
            )

        XCTAssertGreaterThan(
            paperback.x,
            hardcover.x
        )

        XCTAssertGreaterThan(
            paperback.z,
            hardcover.z
        )

        XCTAssertGreaterThan(
            paperback.tilt,
            hardcover.tilt
        )
    }

    func testFullerStackFansMoreThanThinStack() {
        let thin =
            BookPreviewScene
            .pageFanEnvelope(
                binding:
                    .softcover,
                fullness:
                    0.15,
                blockWidth:
                    4.2,
                totalDepth:
                    0.8
            )

        let full =
            BookPreviewScene
            .pageFanEnvelope(
                binding:
                    .softcover,
                fullness:
                    0.90,
                blockWidth:
                    4.2,
                totalDepth:
                    0.8
            )

        XCTAssertGreaterThan(
            full.x,
            thin.x
        )

        XCTAssertGreaterThan(
            full.z,
            thin.z
        )

        XCTAssertGreaterThan(
            full.tilt,
            thin.tilt
        )
    }

    func testNearEmptyStackHidesFanWithoutRemovingRibbons() throws {
        let pair =
            try blocks(
                in:
                    openScene()
            )

        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        BookPreviewScene
        .updatePageEdgeFan(
            blockNode:
                pair.left,
            side:
                .left,
            depth:
                0.000_001,
            totalDepth:
                CGFloat(
                    geometry
                    .pageBlockDepth(
                        for:
                            .softcover
                    )
                    * 0.7
                ),
            binding:
                .softcover
        )

        let fan =
            try XCTUnwrap(
                pair.left
                .childNode(
                    withName:
                        "book.left-page-fan",
                    recursively:
                        false
                )
            )

        XCTAssertTrue(
            fan.isHidden
        )

        XCTAssertEqual(
            fan.childNodes.count,
            12
        )
    }

    func testRepeatedUpdatesReuseTheSameTwelveRibbonNodes() throws {
        let pair =
            try blocks(
                in:
                    openScene()
            )

        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        let total =
            CGFloat(
                geometry
                .pageBlockDepth(
                    for:
                        .softcover
                )
                * 0.7
            )

        for step in 1...50 {
            BookPreviewScene
            .updatePageEdgeFan(
                blockNode:
                    pair.right,
                side:
                    .right,
                depth:
                    total
                    * CGFloat(
                        step
                    )
                    / 50,
                totalDepth:
                    total,
                binding:
                    .softcover
            )
        }

        let fan =
            try XCTUnwrap(
                pair.right
                .childNode(
                    withName:
                        "book.right-page-fan",
                    recursively:
                        false
                )
            )

        XCTAssertEqual(
            fan.childNodes.count,
            12
        )

        XCTAssertEqual(
            pair.right
            .childNodes
            .filter {
                $0.name
                == "book.right-page-fan"
            }
            .count,
            1
        )
    }

    func testIdenticalScenesProduceIdenticalRibbonTransforms() throws {
        let first =
            try blocks(
                in:
                    openScene(
                        binding:
                            .hardcover
                    )
            )

        let second =
            try blocks(
                in:
                    openScene(
                        binding:
                            .hardcover
                    )
            )

        let firstFan =
            try XCTUnwrap(
                first.right
                .childNode(
                    withName:
                        "book.right-page-fan",
                    recursively:
                        false
                )
            )

        let secondFan =
            try XCTUnwrap(
                second.right
                .childNode(
                    withName:
                        "book.right-page-fan",
                    recursively:
                        false
                )
            )

        XCTAssertEqual(
            firstFan.childNodes.count,
            secondFan.childNodes.count
        )

        for index in
            0..<firstFan.childNodes.count
        {
            let a =
                firstFan.childNodes[
                    index
                ]

            let b =
                secondFan.childNodes[
                    index
                ]

            XCTAssertEqual(
                a.position.x,
                b.position.x,
                accuracy:
                    0.000_001
            )

            XCTAssertEqual(
                a.position.z,
                b.position.z,
                accuracy:
                    0.000_001
            )

            XCTAssertEqual(
                a.eulerAngles.y,
                b.eulerAngles.y,
                accuracy:
                    0.000_001
            )

            XCTAssertEqual(
                a.opacity,
                b.opacity,
                accuracy:
                    0.000_001
            )
        }
    }

    func testPageTurnTransferUpdatesFanWithoutReparentingBlock() throws {
        let project =
            project()

        let scene =
            BookPreviewScene.make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    180,
                leftPage:
                    80,
                rightPage:
                    81,
                pageCount:
                    300,
                spreadIndex:
                    40,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID(),
                binding:
                    .softcover
            )

        let root =
            try XCTUnwrap(
                scene.rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let right =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        false
                )
            )

        let fan =
            try XCTUnwrap(
                right.childNode(
                    withName:
                        "book.right-page-fan",
                    recursively:
                        false
                )
            )

        let initialRibbon =
            try XCTUnwrap(
                fan.childNodes.last
            )

        let initialX =
            initialRibbon.position.x

        let initialZ =
            initialRibbon.position.z

        var navigation =
            BookPageTurnState()

        navigation.jump(
            to:
                40,
            maximumSpread:
                150
        )

        let transition =
            try XCTUnwrap(
                navigation.begin(
                    to:
                        41,
                    maximumSpread:
                        150
                )
            )

        BookPreviewScene
        .applyPageTurnMassTransfer(
            in:
                scene,
            project:
                project,
            pageCount:
                300,
            binding:
                .softcover,
            transition:
                transition,
            progress:
                0.5
        )

        let updatedFan =
            try XCTUnwrap(
                right.childNode(
                    withName:
                        "book.right-page-fan",
                    recursively:
                        false
                )
            )

        let updatedRibbon =
            try XCTUnwrap(
                updatedFan.childNodes.last
            )

        XCTAssertTrue(
            right.parent
            === root
        )

        XCTAssertEqual(
            updatedFan.childNodes.count,
            12
        )

        XCTAssertTrue(
            initialX
            != updatedRibbon.position.x
            || initialZ
            != updatedRibbon.position.z
        )
    }

    func testFanDoesNotAlterAuthoritativeAggregateThickness() throws {
        let pair =
            try blocks(
                in:
                    openScene()
            )

        let box =
            try XCTUnwrap(
                pair.left.geometry
                as? SCNBox
            )

        let originalLength =
            box.length

        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        BookPreviewScene
        .updatePageEdgeFan(
            blockNode:
                pair.left,
            side:
                .left,
            depth:
                originalLength,
            totalDepth:
                CGFloat(
                    geometry
                    .pageBlockDepth(
                        for:
                            .softcover
                    )
                    * 0.7
                ),
            binding:
                .softcover
        )

        XCTAssertEqual(
            box.length,
            originalLength,
            accuracy:
                0.000_001
        )
    }


    func testReadingFanEnvelopeIsVisibleButRestrained() {
        let blockWidth:
            CGFloat =
                4.2

        let totalDepth:
            CGFloat =
                0.7

        let fullness:
            CGFloat =
                0.5666667

        let hardcover =
            BookPreviewScene
            .pageFanEnvelope(
                binding:
                    .hardcover,
                fullness:
                    fullness,
                blockWidth:
                    blockWidth,
                totalDepth:
                    totalDepth
            )

        let softcover =
            BookPreviewScene
            .pageFanEnvelope(
                binding:
                    .softcover,
                fullness:
                    fullness,
                blockWidth:
                    blockWidth,
                totalDepth:
                    totalDepth
            )

        print(
            "REAL_PAPER_FAN "
            + "hardcover="
            + "\(hardcover) "
            + "softcover="
            + "\(softcover)"
        )

        XCTAssertGreaterThan(
            hardcover.x,
            0.008
        )

        XCTAssertLessThan(
            hardcover.x,
            0.020
        )

        XCTAssertGreaterThan(
            hardcover.z,
            0.010
        )

        XCTAssertLessThan(
            hardcover.z,
            0.030
        )

        XCTAssertGreaterThan(
            hardcover.tilt,
            0.002
        )

        XCTAssertLessThan(
            hardcover.tilt,
            0.010
        )

        XCTAssertGreaterThan(
            softcover.x,
            hardcover.x
        )

        XCTAssertGreaterThan(
            softcover.z,
            hardcover.z
        )

        XCTAssertGreaterThan(
            softcover.tilt,
            hardcover.tilt
        )

        XCTAssertLessThan(
            softcover.x,
            0.040
        )

        XCTAssertLessThan(
            softcover.z,
            0.050
        )

        XCTAssertLessThan(
            softcover.tilt,
            0.020
        )
    }


    func testOpenPageMassAddsCurvedForeEdgeWithoutReplacingAggregateBlock() throws {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        let pageCount =
            300

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        func inspect(
            binding:
                BookBinding
        ) throws -> (
            thickness: CGFloat,
            bow: CGFloat
        ) {
            let presentation =
                BookStudioPresentation
                .restingOpenPreviewDefault

            let scene =
                BookPreviewScene
                .make(
                    project:
                        project,
                    workingLayers:
                        false,
                    open:
                        true,
                    angle:
                        presentation
                        .openAngle,
                    leftPage:
                        spread * 2,
                    rightPage:
                        spread * 2 + 1,
                    pageCount:
                        pageCount,
                    spreadIndex:
                        spread,
                    leftTexture:
                        nil,
                    rightTexture:
                        nil,
                    margins:
                        false,
                    thumbMode:
                        .off,
                    leftPageSettings:
                        PageSettings(),
                    rightPageSettings:
                        PageSettings(),
                    preset:
                        .reading,
                    revisionID:
                        UUID(),
                    binding:
                        binding,
                    presentation:
                        presentation
                )

            let root =
                try XCTUnwrap(
                    scene
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            let block =
                try XCTUnwrap(
                    root
                    .childNode(
                        withName:
                            "book.right-page-block",
                        recursively:
                            true
                    )
                )

            let box =
                try XCTUnwrap(
                    block.geometry
                    as? SCNBox
                )

            let strata =
                try XCTUnwrap(
                    block
                    .childNode(
                        withName:
                            "book.right-page-edge-strata",
                        recursively:
                            false
                    )
                )

            XCTAssertTrue(
                strata.geometry
                is SCNPlane
            )

            let profile =
                try XCTUnwrap(
                    strata
                    .childNode(
                        withName:
                            "book.right-page-edge-strata.profile",
                        recursively:
                            false
                    )
                )

            XCTAssertTrue(
                profile.parent
                === strata
            )

            XCTAssertFalse(
                profile.geometry
                is SCNPlane
            )

            let geometry =
                try XCTUnwrap(
                    profile.geometry
                )

            let bounds =
                geometry
                .boundingBox

            XCTAssertGreaterThan(
                bounds.max.z
                - bounds.min.z,
                0.80
            )

            XCTAssertEqual(
                CGFloat(
                    profile.scale.x
                ),
                box.length,
                accuracy:
                    0.000_5
            )

            XCTAssertGreaterThan(
                CGFloat(
                    profile.scale.z
                ),
                0.000_8
            )

            return (
                box.length,
                CGFloat(
                    profile.scale.z
                )
            )
        }

        let hardcover =
            try inspect(
                binding:
                    .hardcover
            )

        let softcover =
            try inspect(
                binding:
                    .softcover
            )

        print(
            "CURVED_FORE_EDGE_STATIC "
            + "hardcover="
            + "\(hardcover) "
            + "softcover="
            + "\(softcover)"
        )

        XCTAssertGreaterThan(
            hardcover.thickness,
            0
        )

        XCTAssertGreaterThan(
            softcover.thickness,
            0
        )

        XCTAssertGreaterThan(
            softcover.bow,
            hardcover.bow
        )
    }


    func testCurvedForeEdgeTracksLiveFanDepthUpdates() throws {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        let pageCount =
            300

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        let presentation =
            BookStudioPresentation
            .restingOpenPreviewDefault

        let scene =
            BookPreviewScene
            .make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    presentation
                    .openAngle,
                leftPage:
                    spread * 2,
                rightPage:
                    spread * 2 + 1,
                pageCount:
                    pageCount,
                spreadIndex:
                    spread,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .reading,
                revisionID:
                    UUID(),
                binding:
                    .softcover,
                presentation:
                    presentation
            )

        let root =
            try XCTUnwrap(
                scene
                .rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let block =
            try XCTUnwrap(
                root
                .childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        true
                )
            )

        let box =
            try XCTUnwrap(
                block.geometry
                as? SCNBox
            )

        let profile =
            try XCTUnwrap(
                block
                .childNode(
                    withName:
                        "book.right-page-edge-strata.profile",
                    recursively:
                        true
                )
            )

        let unitStacks =
            PhysicalBookGeometry
            .pageStacks(
                pageCount:
                    pageCount,
                spreadIndex:
                    spread,
                totalDepth:
                    1
            )

        let rightFraction =
            CGFloat(
                unitStacks
                .rightDepth
            )

        XCTAssertGreaterThan(
            rightFraction,
            0
        )

        let totalDepth =
            box.length
            / rightFraction

        let shallowDepth =
            totalDepth
            * 0.22

        let deepDepth =
            totalDepth
            * 0.78

        BookPreviewScene
            .updatePageEdgeFan(
                blockNode:
                    block,
                side:
                    .right,
                depth:
                    shallowDepth,
                totalDepth:
                    totalDepth,
                binding:
                    .softcover
            )

        let shallowWidth =
            CGFloat(
                profile.scale.x
            )

        let shallowBow =
            CGFloat(
                profile.scale.z
            )

        BookPreviewScene
            .updatePageEdgeFan(
                blockNode:
                    block,
                side:
                    .right,
                depth:
                    deepDepth,
                totalDepth:
                    totalDepth,
                binding:
                    .softcover
            )

        let deepWidth =
            CGFloat(
                profile.scale.x
            )

        let deepBow =
            CGFloat(
                profile.scale.z
            )

        print(
            "CURVED_FORE_EDGE_LIVE "
            + "shallow=(\(shallowWidth), \(shallowBow)) "
            + "deep=(\(deepWidth), \(deepBow))"
        )

        XCTAssertEqual(
            shallowWidth,
            shallowDepth,
            accuracy:
                0.000_5
        )

        XCTAssertEqual(
            deepWidth,
            deepDepth,
            accuracy:
                0.000_5
        )

        XCTAssertGreaterThan(
            deepWidth,
            shallowWidth
        )

        XCTAssertGreaterThan(
            deepBow,
            shallowBow
        )

        XCTAssertFalse(
            profile.isHidden
        )
    }
}


final class OpenBookSilhouetteTests:
    XCTestCase
{
    private func project() -> CoverProject {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        return project
    }

    private func silhouette(
        spread:
            Int,
        binding:
            BookBinding
    ) -> BookOpenSilhouette {
        PhysicalBookGeometry(
            project:
                project()
        )
        .openSilhouette(
            open:
                true,
            angleDegrees:
                180,
            pageCount:
                300,
            spreadIndex:
                spread,
            binding:
                binding
        )
    }

    func testSilhouetteIsDeterministic() {
        XCTAssertEqual(
            silhouette(
                spread:
                    75,
                binding:
                    .softcover
            ),
            silhouette(
                spread:
                    75,
                binding:
                    .softcover
            )
        )
    }

    func testEarlyMiddleLateHardcoverRelationships() {
        let early =
            silhouette(
                spread:
                    15,
                binding:
                    .hardcover
            )

        let middle =
            silhouette(
                spread:
                    75,
                binding:
                    .hardcover
            )

        let late =
            silhouette(
                spread:
                    135,
                binding:
                    .hardcover
            )

        XCTAssertLessThan(
            early.stacks.leftDepth,
            early.stacks.rightDepth
        )

        XCTAssertGreaterThan(
            early.leftStackLiftDegrees,
            early.rightStackLiftDegrees
        )

        XCTAssertEqual(
            middle.stacks.leftDepth,
            middle.stacks.rightDepth,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            middle.leftStackLiftDegrees,
            middle.rightStackLiftDegrees,
            accuracy:
                0.000_001
        )

        XCTAssertGreaterThan(
            late.stacks.leftDepth,
            late.stacks.rightDepth
        )

        XCTAssertLessThan(
            late.leftStackLiftDegrees,
            late.rightStackLiftDegrees
        )
    }

    func testEarlyLateHardcoverMirror() {
        let early =
            silhouette(
                spread:
                    15,
                binding:
                    .hardcover
            )

        let late =
            silhouette(
                spread:
                    135,
                binding:
                    .hardcover
            )

        XCTAssertEqual(
            early.leftStackLiftDegrees,
            late.rightStackLiftDegrees,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            early.rightStackLiftDegrees,
            late.leftStackLiftDegrees,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            early.leftShoulderDepth,
            late.rightShoulderDepth,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            early.rightShoulderDepth,
            late.leftShoulderDepth,
            accuracy:
                0.000_001
        )
    }

    func testEarlyLatePaperbackMirror() {
        let early =
            silhouette(
                spread:
                    15,
                binding:
                    .softcover
            )

        let late =
            silhouette(
                spread:
                    135,
                binding:
                    .softcover
            )

        XCTAssertEqual(
            early.leftStackLiftDegrees,
            late.rightStackLiftDegrees,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            early.rightStackLiftDegrees,
            late.leftStackLiftDegrees,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            early.leftForeEdgeLift,
            late.rightForeEdgeLift,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            early.rightForeEdgeLift,
            late.leftForeEdgeLift,
            accuracy:
                0.000_001
        )
    }

    func testPaperbackFlexesMoreThanHardcover() {
        let hard =
            silhouette(
                spread:
                    75,
                binding:
                    .hardcover
            )

        let soft =
            silhouette(
                spread:
                    75,
                binding:
                    .softcover
            )

        XCTAssertGreaterThan(
            soft.leftStackLiftDegrees,
            hard.leftStackLiftDegrees
        )

        XCTAssertGreaterThan(
            soft.rightStackLiftDegrees,
            hard.rightStackLiftDegrees
        )

        XCTAssertGreaterThan(
            soft.gutterDrop,
            hard.gutterDrop
        )

        XCTAssertGreaterThan(
            soft.pageValleyDepth,
            hard.pageValleyDepth
        )

        XCTAssertGreaterThan(
            soft.leftShoulderDepth,
            hard.leftShoulderDepth
        )

        XCTAssertGreaterThan(
            soft.leftForeEdgeLift,
            hard.leftForeEdgeLift
        )
    }

    func testGutterIsBelowBothOuterEdges() {
        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            for spread in [
                15,
                75,
                135
            ] {
                let shape =
                    silhouette(
                        spread:
                            spread,
                        binding:
                            binding
                    )

                XCTAssertGreaterThan(
                    shape.pageValleyDepth,
                    0
                )

                XCTAssertGreaterThanOrEqual(
                    shape.leftOuterRiseFromGutter,
                    shape.pageValleyDepth,
                    "A fully-open spread may be coplanar at the outer edge while retaining the curved paper gutter."
                )

                XCTAssertGreaterThanOrEqual(
                    shape.rightOuterRiseFromGutter,
                    shape.pageValleyDepth,
                    "A fully-open spread may be coplanar at the outer edge while retaining the curved paper gutter."
                )
            }
        }
    }

    func testClosedSilhouetteCollapses() {
        let shape =
            PhysicalBookGeometry(
                project:
                    project()
            )
            .openSilhouette(
                open:
                    false,
                angleDegrees:
                    180,
                pageCount:
                    300,
                spreadIndex:
                    75,
                binding:
                    .softcover
            )

        XCTAssertEqual(
            shape.openProgress,
            0,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            shape.leftStackLiftDegrees,
            0,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            shape.rightStackLiftDegrees,
            0,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            shape.pageValleyDepth,
            0,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            shape.leftShoulderDepth,
            0,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            shape.rightShoulderDepth,
            0,
            accuracy:
                0.000_001
        )
    }

    func testCurvedPaperContainsValleyAndPositiveShoulderOrForeEdge() {
        let paper =
            BookPreviewScene
            .curvedPaperGeometry(
                width:
                    4.2,
                height:
                    6.3,
                insideEdge:
                    .left,
                valleyDepth:
                    0.018,
                foreEdgeCurl:
                    0.012,
                shoulderLift:
                    0.008
            )

        XCTAssertLessThan(
            paper.boundingBox.min.z,
            0
        )

        XCTAssertGreaterThan(
            paper.boundingBox.max.z,
            0
        )

        XCTAssertEqual(
            paper.elements.count,
            2
        )
    }

    func testScenePreservesHierarchyAndPageFans() throws {
        let scene =
            BookPreviewScene.make(
                project:
                    project(),
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    180,
                leftPage:
                    150,
                rightPage:
                    151,
                pageCount:
                    300,
                spreadIndex:
                    75,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID(),
                binding:
                    .softcover
            )

        let root =
            try XCTUnwrap(
                scene.rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let leaves =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.left-leaves",
                    recursively:
                        false
                )
            )

        let left =
            try XCTUnwrap(
                leaves.childNode(
                    withName:
                        "book.left-page-block",
                    recursively:
                        false
                )
            )

        let right =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        false
                )
            )

        XCTAssertTrue(
            left.parent
            === leaves
        )

        XCTAssertTrue(
            right.parent
            === root
        )

        XCTAssertNotNil(
            left.childNode(
                withName:
                    "book.left-page-fan",
                recursively:
                    false
            )
        )

        XCTAssertNotNil(
            right.childNode(
                withName:
                    "book.right-page-fan",
                recursively:
                    false
            )
        )

        XCTAssertNotNil(
            root.childNode(
                withName:
                    "book-shell.front-cover",
                recursively:
                    false
            )
        )

        XCTAssertNotNil(
            root.childNode(
                withName:
                    "book-shell.back-cover",
                recursively:
                    false
            )
        )

        XCTAssertNotNil(
            root.childNode(
                withName:
                    "book-shell.spine",
                recursively:
                    false
            )
        )
    }

    func testTurningPageKeepsCommonGutterPivot() throws {
        let project =
            project()

        let scene =
            BookPreviewScene.make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    180,
                leftPage:
                    2,
                rightPage:
                    3,
                pageCount:
                    20,
                spreadIndex:
                    1,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID(),
                binding:
                    .softcover
            )

        let transition =
            BookPageTurnTransition(
                fromSpread:
                    1,
                toSpread:
                    2,
                direction:
                    .forward,
                rotation:
                    .pi
            )

        BookPreviewScene.animatePageTurn(
            in:
                scene,
            project:
                project,
            pageCount:
                20,
            binding:
                .softcover,
            image:
                NSImage(
                    size:
                        NSSize(
                            width:
                                60,
                            height:
                                90
                        )
                ),
            reverseImage:
                NSImage(
                    size:
                        NSSize(
                            width:
                                60,
                            height:
                                90
                        )
                ),
            transition:
                transition
        )

        let root =
            try XCTUnwrap(
                scene.rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let pivot =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.turning-page-pivot",
                    recursively:
                        false
                )
            )

        let printed = try XCTUnwrap(root.childNode(withName: "book.right-active-page", recursively: true))
        let points = BookOpenGutterGeometry.vertices(try XCTUnwrap(printed.geometry?.sources(for: .vertex).first))
        let expected = printed.convertPosition(points[0], to: root).z
        XCTAssertEqual(pivot.value(forKey: "bookTurnUsesPrintedSurfaces") as? Bool, true)

        XCTAssertEqual(
            pivot.position.x,
            0,
            accuracy:
                0.000_01
        )

        XCTAssertEqual(
            pivot.position.z,
            expected,
            accuracy:
                0.000_1
        )

        let leaf =
            try XCTUnwrap(
                pivot.childNode(
                    withName:
                        "book.turning-page-leaf",
                    recursively:
                        false
                )
            )

        XCTAssertEqual(
            try XCTUnwrap(
                leaf.geometry
            )
            .elements
            .count,
            2
        )
    }
}


final class PhysicalBookCommonGutterRegressionTests:
    XCTestCase
{
    private struct WorldRange {
        let minX: CGFloat
        let maxX: CGFloat

        var innerX: CGFloat {
            abs(minX) <= abs(maxX)
            ? minX
            : maxX
        }
    }

    private func project() -> CoverProject {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        return project
    }

    private func worldRange(
        _ node:
            SCNNode,
        root:
            SCNNode
    ) -> WorldRange {
        let bounds =
            node.geometry?.boundingBox ?? node.boundingBox

        let ys:
            [CGFloat] =
            [
                bounds.min.y,
                (
                    bounds.min.y
                    + bounds.max.y
                )
                / 2,
                bounds.max.y
            ]

        let zs:
            [CGFloat] =
            [
                bounds.min.z,
                (
                    bounds.min.z
                    + bounds.max.z
                )
                / 2,
                bounds.max.z
            ]

        var xs:
            [CGFloat] =
            []

        for x in [
            bounds.min.x,
            bounds.max.x
        ] {
            for y in ys {
                for z in zs {
                    xs.append(
                        node.convertPosition(
                            SCNVector3(
                                x,
                                y,
                                z
                            ),
                            to:
                                root
                        )
                        .x
                    )
                }
            }
        }

        return WorldRange(
            minX:
                xs.min()
                ?? 0,
            maxX:
                xs.max()
                ?? 0
        )
    }

    private func hingeWorldX(
        _ node:
            SCNNode,
        root:
            SCNNode
    ) -> CGFloat {
        node.convertPosition(
            SCNVector3(
                node.pivot.m41,
                0,
                0
            ),
            to:
                root
        )
        .x
    }



    func testCanonicalOpenBooksKeepBlocksAndActivePagesOnCommonGutter() throws {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.spineWidth = 1.2

        let width =
            CGFloat(
                project.trimWidth
                * 0.7
            )

        let angles: [Double] =
            [
                15,
                54,
                90,
                160,
                180
            ]

        let spreads =
            [
                15,
                75,
                135
            ]

        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            for angle in angles {
                for spread in spreads {
                    let scene =
                        BookPreviewScene.make(
                            project:
                                project,
                            workingLayers:
                                false,
                            open:
                                true,
                            angle:
                                angle,
                            leftPage:
                                spread * 2,
                            rightPage:
                                spread * 2 + 1,
                            pageCount:
                                300,
                            spreadIndex:
                                spread,
                            leftTexture:
                                nil,
                            rightTexture:
                                nil,
                            margins:
                                false,
                            thumbMode:
                                .off,
                            leftPageSettings:
                                PageSettings(),
                            rightPageSettings:
                                PageSettings(),
                            preset:
                                .perspective,
                            revisionID:
                                UUID(),
                            binding:
                                binding
                        )

                    let root =
                        try XCTUnwrap(
                            scene.rootNode.childNode(
                                withName:
                                    "physical-book.root",
                                recursively:
                                    false
                            )
                        )

                    let leftBlock =
                        try XCTUnwrap(
                            root.childNode(
                                withName:
                                    "book.left-page-block",
                                recursively:
                                    true
                            )
                        )

                    let rightBlock =
                        try XCTUnwrap(
                            root.childNode(
                                withName:
                                    "book.right-page-block",
                                recursively:
                                    true
                            )
                        )

                    let leftPage =
                        try XCTUnwrap(
                            root.childNode(
                                withName:
                                    "book.left-active-page",
                                recursively:
                                    true
                            )
                        )

                    let rightPage =
                        try XCTUnwrap(
                            root.childNode(
                                withName:
                                    "book.right-active-page",
                                recursively:
                                    true
                            )
                        )

                    let leftBox =
                        try XCTUnwrap(
                            leftBlock.geometry
                                as? SCNBox
                        )

                    let rightBox =
                        try XCTUnwrap(
                            rightBlock.geometry
                                as? SCNBox
                        )

                    func verify(
                        page:
                            SCNNode,
                        block:
                            SCNNode,
                        box:
                            SCNBox,
                        insideX:
                            CGFloat,
                        side:
                            String
                    ) {
                        let pageCenter =
                            page.convertPosition(
                                SCNVector3Zero,
                                to:
                                    block
                            )

                        let pageInsideEdge =
                            page.convertPosition(
                                SCNVector3(
                                    insideX,
                                    0,
                                    0
                                ),
                                to:
                                    block
                            )

                        let pageNormal =
                            page.convertVector(
                                SCNVector3(
                                    0,
                                    0,
                                    1
                                ),
                                to:
                                    block
                            )

                        XCTAssertEqual(
                            pageCenter.x,
                            0,
                            accuracy:
                                0.001,
                            "\(side) page center detached laterally from its page block for \(binding), angle \(angle), spread \(spread)"
                        )

                        XCTAssertEqual(
                            pageCenter.y,
                            0,
                            accuracy:
                                0.001,
                            "\(side) page center detached vertically from its page block for \(binding), angle \(angle), spread \(spread)"
                        )

                        XCTAssertGreaterThan(
                            pageCenter.z,
                            box.length / 2,
                            "\(side) printed surface must remain above its own stack"
                        )

                        XCTAssertLessThan(
                            pageCenter.z - box.length / 2,
                            0.02,
                            "\(side) printed surface must remain in physical contact with its own stack"
                        )

                        XCTAssertEqual(
                            pageInsideEdge.x,
                            insideX,
                            accuracy:
                                0.001,
                            "\(side) printed inside edge must remain registered to its physical page mass"
                        )

                        XCTAssertEqual(
                            pageInsideEdge.y,
                            0,
                            accuracy:
                                0.001
                        )

                        XCTAssertEqual(
                            pageInsideEdge.z,
                            pageCenter.z,
                            accuracy:
                                0.001,
                            "\(side) inside edge must lie on the same rotated printed surface"
                        )

                        XCTAssertEqual(
                            pageNormal.x,
                            0,
                            accuracy:
                                0.001
                        )

                        XCTAssertEqual(
                            pageNormal.y,
                            0,
                            accuracy:
                                0.001
                        )

                        XCTAssertGreaterThan(
                            pageNormal.z,
                            0.999,
                            "\(side) printed surface must follow the rotated stack normal"
                        )
                    }

                    verify(
                        page:
                            leftPage,
                        block:
                            leftBlock,
                        box:
                            leftBox,
                        insideX:
                            width / 2,
                        side:
                            "Left"
                    )

                    verify(
                        page:
                            rightPage,
                        block:
                            rightBlock,
                        box:
                            rightBox,
                        insideX:
                            -width / 2,
                        side:
                            "Right"
                    )

                    if angle == 180 {
                        let leftInsideRoot =
                            leftBlock.convertPosition(
                                SCNVector3(
                                    width / 2,
                                    0,
                                    -leftBox.length / 2
                                ),
                                to:
                                    root
                            )

                        let rightInsideRoot =
                            rightBlock.convertPosition(
                                SCNVector3(
                                    -width / 2,
                                    0,
                                    -rightBox.length / 2
                                ),
                                to:
                                    root
                            )

                        XCTAssertEqual(
                            leftInsideRoot.x,
                            -PhysicalBookGeometry(project:project).openSpineHingeOffset(angleDegrees:180,binding:binding)*0.7,
                            accuracy:
                                0.00001,
                            "Left support must leave room for the real spine"
                        )

                        XCTAssertEqual(
                            rightInsideRoot.x,
                            PhysicalBookGeometry(project:project).openSpineHingeOffset(angleDegrees:180,binding:binding)*0.7,
                            accuracy:
                                0.00001,
                            "Right support must leave room for the real spine"
                        )
                        for (page,index) in [(leftPage,72),(rightPage,0)] {
                            let points=BookOpenGutterGeometry.vertices(try XCTUnwrap(page.geometry?.sources(for:.vertex).first))
                            XCTAssertEqual(page.convertPosition(points[index],to:root).x,0,accuracy:0.00001,
                                "Printed leaves must still meet at the common gutter above the opened case")
                        }
                    }
                }
            }
        }
    }

    func testBoundaryMassTransferCreatesDestinationStackAtCommonGutter() throws {
        let project =
            project()

        let scene =
            BookPreviewScene.make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    180,
                leftPage:
                    0,
                rightPage:
                    1,
                pageCount:
                    20,
                spreadIndex:
                    0,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID(),
                binding:
                    .softcover
            )

        let transition =
            BookPageTurnTransition(
                fromSpread:
                    0,
                toSpread:
                    1,
                direction:
                    .forward,
                rotation:
                    .pi
            )

        BookPreviewScene
        .applyPageTurnMassTransfer(
            in:
                scene,
            project:
                project,
            pageCount:
                20,
            binding:
                .softcover,
            transition:
                transition,
            progress:
                0.75
        )

        let root =
            try XCTUnwrap(
                scene.rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let leaves =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.left-leaves",
                    recursively:
                        false
                )
            )

        let leftBlock =
            try XCTUnwrap(
                leaves.childNode(
                    withName:
                        "book.left-page-block",
                    recursively:
                        false
                )
            )

        let box = try XCTUnwrap(leftBlock.geometry as? SCNBox)
        let boundBottom = leftBlock.convertPosition(SCNVector3(box.width/2,0,-box.length/2),to:root)
        XCTAssertEqual(boundBottom.x,-PhysicalBookGeometry(project:project).openSpineHingeOffset(angleDegrees:180,binding:.softcover)*0.7,accuracy:0.000_001)

        XCTAssertLessThan(
            abs(
                hingeWorldX(
                    leftBlock,
                    root:
                        scene.rootNode
                ) + CGFloat(PhysicalBookGeometry(project:project).openSpineHingeOffset(angleDegrees:180,binding:.softcover)*0.7)
            ),
            0.04
        )
    }
}

final class PhysicalBookSupportContactTests: XCTestCase {
    private let fractions: [CGFloat] =
        [
            0,
            0.25,
            0.5,
            0.75,
            1
        ]

    private func project() -> CoverProject {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        return project
    }

    private func flexibleCoverZ(
        _ source:
            SCNGeometrySource,
        at index:
            Int
    ) -> CGFloat {
        let offset =
            source.dataOffset
            + index
            * source.dataStride
            + 2
            * source.bytesPerComponent

        return CGFloat(
            source.data
            .withUnsafeBytes {
                $0.loadUnaligned(
                    fromByteOffset:
                        offset,
                    as:
                        Float.self
                )
            }
        )
    }

    private func contactSamples(
        binding:
            BookBinding,
        spread:
            Int
    ) throws -> (
        left:
            [CGFloat],
        right:
            [CGFloat]
    ) {
        let project =
            project()

        let scene =
            BookPreviewScene
            .make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    180,
                leftPage:
                    spread * 2,
                rightPage:
                    spread * 2 + 1,
                pageCount:
                    300,
                spreadIndex:
                    spread,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID(),
                binding:
                    binding
            )

        let root =
            try XCTUnwrap(
                scene
                .rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let front =
            try XCTUnwrap(
                root
                .childNode(
                    withName:
                        "book-shell.front-cover",
                    recursively:
                        false
                )
            )

        let back =
            try XCTUnwrap(
                root
                .childNode(
                    withName:
                        "book-shell.back-cover",
                    recursively:
                        false
                )
            )

        let left =
            try XCTUnwrap(
                root
                .childNode(
                    withName:
                        "book.left-page-block",
                    recursively:
                        true
                )
            )

        let right =
            try XCTUnwrap(
                root
                .childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        false
                )
            )

        let leftBox =
            try XCTUnwrap(
                left.geometry
                    as? SCNBox
            )

        let rightBox =
            try XCTUnwrap(
                right.geometry
                    as? SCNBox
            )

        let width =
            CGFloat(
                project.trimWidth
                * 0.7
            )

        let thickness =
            CGFloat(
                PhysicalBookGeometry(
                    project:
                        project
                )
                .coverThickness(
                    for:
                        binding
                )
                * 0.7
            )

        let frontVertices =
            binding == .softcover
            ? try XCTUnwrap(
                front.geometry?
                    .sources(
                        for:
                            .vertex
                    )
                    .first
            )
            : nil

        let backVertices =
            binding == .softcover
            ? try XCTUnwrap(
                back.geometry?
                    .sources(
                        for:
                            .vertex
                    )
                    .first
            )
            : nil

        func samples(
            block:
                SCNNode,
            box:
                SCNBox,
            cover:
                SCNNode,
            vertices:
                SCNGeometrySource?,
            isLeft:
                Bool
        ) -> [CGFloat] {
            fractions
            .map {
                fraction in

                let pageX =
                    isLeft
                    ? width
                    * (
                        0.5
                        - fraction
                    )
                    : width
                    * (
                        fraction
                        - 0.5
                    )

                let coverX =
                    width
                    * (
                        fraction
                        - 0.5
                    )

                let coverZ:
                    CGFloat

                if let vertices {
                    coverZ =
                        flexibleCoverZ(
                            vertices,
                            at:
                                Int(
                                    fraction
                                    * 24
                                )
                                * 2 + (isLeft ? vertices.vectorCount / 2 : 0)
                        )
                } else {
                    coverZ =
                        isLeft
                        ? -thickness / 2
                        : thickness / 2
                }

                let pagePoint =
                    block
                    .convertPosition(
                        SCNVector3(
                            pageX,
                            0,
                            -box.length / 2
                        ),
                        to:
                            root
                    )

                let coverPoint =
                    cover
                    .convertPosition(
                        SCNVector3(
                            coverX,
                            0,
                            coverZ
                        ),
                        to:
                            root
                    )

                return
                    pagePoint.z
                    - coverPoint.z
            }
        }

        return (
            samples(
                block:
                    left,
                box:
                    leftBox,
                cover:
                    front,
                vertices:
                    frontVertices,
                isLeft:
                    true
            ),
            samples(
                block:
                    right,
                box:
                    rightBox,
                cover:
                    back,
                vertices:
                    backVertices,
                isLeft:
                    false
            )
        )
    }

    func testCanonicalTransformedSupportContact() throws {
        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            let early =
                try contactSamples(
                    binding:
                        binding,
                    spread:
                        15
                )

            let middle =
                try contactSamples(
                    binding:
                        binding,
                    spread:
                        75
                )

            let late =
                try contactSamples(
                    binding:
                        binding,
                    spread:
                        135
                )

            let minimumGap:
                CGFloat =
                    -0.010

            let maximumGap:
                CGFloat =
                    binding
                    == .hardcover
                    ? 0.010
                    : 0.025

            for (
                name,
                pose
            ) in [
                (
                    "early",
                    early
                ),
                (
                    "middle",
                    middle
                ),
                (
                    "late",
                    late
                )
            ] {
                print(
                    "CONTACT \(binding) \(name) "
                    + "left=\(pose.left) "
                    + "right=\(pose.right)"
                )

                XCTAssertEqual(
                    pose.left.count,
                    5
                )

                XCTAssertEqual(
                    pose.right.count,
                    5
                )

                for gap in
                    pose.left
                    + pose.right
                {
                    XCTAssertTrue(
                        gap.isFinite
                    )

                    XCTAssertGreaterThan(
                        gap,
                        minimumGap
                    )

                    XCTAssertLessThan(
                        gap,
                        maximumGap
                    )
                }
            }

            for index in
                fractions.indices
            {
                XCTAssertEqual(
                    abs(
                        early.left[
                            index
                        ]
                    ),
                    abs(
                        late.right[
                            index
                        ]
                    ),
                    accuracy:
                        0.002
                )

                XCTAssertEqual(
                    abs(
                        early.right[
                            index
                        ]
                    ),
                    abs(
                        late.left[
                            index
                        ]
                    ),
                    accuracy:
                        0.002
                )

                XCTAssertEqual(
                    abs(
                        middle.left[
                            index
                        ]
                    ),
                    abs(
                        middle.right[
                            index
                        ]
                    ),
                    accuracy:
                        0.002
                )
            }
        }
    }
}

final class NaturalRestingOpenBookTests: XCTestCase {
    func testNaturalReadingSpreadFallsInsideTheBook() {
        XCTAssertEqual(
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    0
            ),
            0
        )

        XCTAssertEqual(
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    4
            ),
            1
        )

        XCTAssertEqual(
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    12
            ),
            3
        )

        XCTAssertEqual(
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    300
            ),
            65
        )
    }

    func testNaturalReadingSpreadLeavesPageMassOnBothSides() {
        let pageCount =
            300

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        let stacks =
            PhysicalBookGeometry
            .pageStacks(
                pageCount:
                    pageCount,
                spreadIndex:
                    spread,
                totalDepth:
                    1
            )

        XCTAssertGreaterThan(
            spread,
            0
        )

        XCTAssertLessThan(
            spread,
            pageCount / 2
        )

        XCTAssertGreaterThan(
            stacks.leftDepth,
            0.35
        )

        XCTAssertGreaterThan(
            stacks.rightDepth,
            0.35
        )

        XCTAssertGreaterThan(
            abs(
                stacks.leftDepth
                - stacks.rightDepth
            ),
            0.05
        )
    }

    func testReadingPresetIsNotRulerFlat() {
        let result =
            BookStudioPreset
            .reading
            .apply(
                to:
                    BookStudioPresentation()
            )

        XCTAssertTrue(
            result.open
        )

        XCTAssertEqual(
            result.openAngle,
            160,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            result.cameraPreset,
            .reading
        )
    }

    func testNaturalReadingPoseRetainsPhysicalPageShape() {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        let geometry =
            PhysicalBookGeometry(
                project:
                    project
            )

        let pageCount =
            300

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            let silhouette =
                geometry
                .openSilhouette(
                    open:
                        true,
                    angleDegrees:
                        160,
                    pageCount:
                        pageCount,
                    spreadIndex:
                        spread,
                    binding:
                        binding
                )

            XCTAssertGreaterThan(
                silhouette.openProgress,
                0.80
            )

            XCTAssertLessThan(
                silhouette.openProgress,
                1
            )

            XCTAssertGreaterThan(
                silhouette.pageValleyDepth,
                0
            )

            XCTAssertGreaterThan(
                silhouette.leftShoulderDepth,
                0
            )

            XCTAssertGreaterThan(
                silhouette.rightShoulderDepth,
                0
            )

            XCTAssertGreaterThan(
                silhouette.leftOuterRiseFromGutter,
                0
            )

            XCTAssertGreaterThan(
                silhouette.rightOuterRiseFromGutter,
                0
            )

            XCTAssertGreaterThan(
                silhouette.stacks.leftDepth,
                0
            )

            XCTAssertGreaterThan(
                silhouette.stacks.rightDepth,
                0
            )
        }
    }


    func testReadingCameraRevealsPhysicalDepth() {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        let state =
            BookPreviewCameraMath
            .state(
                project:
                    project,
                open:
                    true,
                preset:
                    .reading,
                focus:
                    .automatic
            )

        XCTAssertEqual(
            state.yaw,
            0.22,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            state.pitch,
            0.92,
            accuracy:
                0.001
        )

        XCTAssertGreaterThan(
            state.pitch,
            0.75
        )

        XCTAssertLessThan(
            state.pitch,
            1.20
        )

        XCTAssertGreaterThan(
            abs(
                state.yaw
            ),
            0.10
        )

        let presentation =
            BookStudioPreset
            .reading
            .apply(
                to:
                    BookStudioPresentation()
            )

        XCTAssertTrue(
            presentation.open
        )

        XCTAssertEqual(
            presentation.openAngle,
            160,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            presentation.cameraPreset,
            .reading
        )

        XCTAssertEqual(
            presentation.cameraFieldOfView,
            24,
            accuracy:
                0.001
        )
    }


    func testRestingOpenPreviewDefaultIsARealBookView() {
        let presentation =
            BookStudioPresentation
            .restingOpenPreviewDefault

        XCTAssertTrue(
            presentation.open
        )

        XCTAssertEqual(
            presentation.openAngle,
            160,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            presentation.cameraPreset,
            .reading
        )

        XCTAssertEqual(
            presentation.cameraFieldOfView,
            24,
            accuracy:
                0.001
        )

        let pageCount =
            300

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        XCTAssertGreaterThan(
            spread,
            0
        )

        XCTAssertLessThan(
            spread,
            pageCount / 2
        )

        let stacks =
            PhysicalBookGeometry
            .pageStacks(
                pageCount:
                    pageCount,
                spreadIndex:
                    spread,
                totalDepth:
                    1
            )

        XCTAssertGreaterThan(
            stacks.leftDepth,
            0
        )

        XCTAssertGreaterThan(
            stacks.rightDepth,
            0
        )

        XCTAssertGreaterThan(
            abs(
                stacks.leftDepth
                - stacks.rightDepth
            ),
            0.05
        )
    }


    func testReadingPoseRestsOnBackWithRaisedFrontPageMass() throws {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        let pageCount =
            300

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        let presentation =
            BookStudioPresentation
            .restingOpenPreviewDefault

        func worldTiltDegrees(
            _ node:
                SCNNode,
            relativeTo root:
                SCNNode
        ) -> Double {
            let normal =
                node.convertVector(
                    SCNVector3(
                        0,
                        0,
                        1
                    ),
                    to:
                        root
                )

            return atan2(
                Double(
                    normal.x
                ),
                Double(
                    normal.z
                )
            )
            * 180
            / .pi
        }

        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            let scene =
                BookPreviewScene
                .make(
                    project:
                        project,
                    workingLayers:
                        false,
                    open:
                        true,
                    angle:
                        presentation
                        .openAngle,
                    leftPage:
                        spread * 2,
                    rightPage:
                        spread * 2 + 1,
                    pageCount:
                        pageCount,
                    spreadIndex:
                        spread,
                    leftTexture:
                        nil,
                    rightTexture:
                        nil,
                    margins:
                        false,
                    thumbMode:
                        .off,
                    leftPageSettings:
                        PageSettings(),
                    rightPageSettings:
                        PageSettings(),
                    preset:
                        .reading,
                    revisionID:
                        UUID(),
                    binding:
                        binding,
                    presentation:
                        presentation
                )

            let root =
                try XCTUnwrap(
                    scene
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            let left =
                try XCTUnwrap(
                    root
                    .childNode(
                        withName:
                            "book.left-page-block",
                        recursively:
                            true
                    )
                )

            let right =
                try XCTUnwrap(
                    root
                    .childNode(
                        withName:
                            "book.right-page-block",
                        recursively:
                            true
                    )
                )

            let leftTilt =
                worldTiltDegrees(
                    left,
                    relativeTo:
                        root
                )

            let rightTilt =
                worldTiltDegrees(
                    right,
                    relativeTo:
                        root
                )

            print(
                "SPINE_REST "
                + "\(binding) "
                + "leftWorldTilt=\(leftTilt) "
                + "rightWorldTilt=\(rightTilt)"
            )

            XCTAssertGreaterThan(
                abs(
                    leftTilt
                ),
                8
            )

            // The supported back stays nearly horizontal. Splitting the
            // opening equally between both boards made a book balance on
            // its spine instead of resting on its back.
            XCTAssertLessThan(abs(rightTilt), 2)

            XCTAssertLessThan(
                leftTilt
                * rightTilt,
                0
            )

            XCTAssertGreaterThan(abs(leftTilt), abs(rightTilt) + 15)
        }
    }
}

final class RealOpenBookVisualRegressionTests:
    XCTestCase
{
    private func project() -> CoverProject {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        return project
    }

    private func readingScene(
        binding:
            BookBinding
    ) -> SCNScene {
        let project =
            project()

        let pageCount =
            300

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        let presentation =
            BookStudioPresentation
            .restingOpenPreviewDefault

        return BookPreviewScene
            .make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    presentation
                    .openAngle,
                leftPage:
                    spread * 2,
                rightPage:
                    spread * 2 + 1,
                pageCount:
                    pageCount,
                spreadIndex:
                    spread,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .reading,
                revisionID:
                    UUID(),
                binding:
                    binding,
                presentation:
                    presentation
            )
    }

    func testReadingViewHidesRigidSpineBarAndKeepsPrintedBindingWrap() throws {
        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            let scene =
                readingScene(
                    binding:
                        binding
                )

            let root =
                try XCTUnwrap(
                    scene
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            let spine =
                try XCTUnwrap(
                    root
                    .childNode(
                        withName:
                            "book-shell.spine",
                        recursively:
                            false
                    )
                )

            let spineArtwork =
                try XCTUnwrap(
                    root
                    .childNode(
                        withName:
                            "book-shell.spine-artwork",
                        recursively:
                            false
                    )
                )

            XCTAssertTrue(
                spine.isHidden
            )

            XCTAssertFalse(spineArtwork.isHidden)
            XCTAssertEqual(spineArtwork.geometry?.sources(for:.vertex).first?.vectorCount,66,
                "The printed binding must use the hinge-following wrap, not the old rigid bar")

            for name in [
                "book.left-page-block",
                "book.right-page-block"
            ] {
                let block =
                    try XCTUnwrap(
                        root
                        .childNode(
                            withName:
                                name,
                            recursively:
                                true
                        )
                    )

                let box =
                    try XCTUnwrap(
                        block.geometry
                        as? SCNBox
                    )

                XCTAssertGreaterThan(
                    box.length,
                    0
                )

                XCTAssertFalse(
                    box.materials.isEmpty
                )

                for material in
                    box.materials
                {
                    XCTAssertEqual(
                        material.transparency,
                        0,
                        accuracy:
                            0.000_001
                    )

                    XCTAssertFalse(
                        material.writesToDepthBuffer
                    )
                }
            }
        }
    }

    func testReadingPagesHaveSubstantialBoundPaperCurvature() throws {
        func ranges(
            binding:
                BookBinding
        ) throws -> (
            page: CGFloat,
            swellScale: CGFloat
        ) {
            let scene =
                readingScene(
                    binding:
                        binding
                )

            let root =
                try XCTUnwrap(
                    scene
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            let active =
                try XCTUnwrap(
                    root
                    .childNode(
                        withName:
                            "book.right-active-page",
                        recursively:
                            true
                    )
                )

            let bounds =
                try XCTUnwrap(
                    active.geometry
                )
                .boundingBox

            let pageRange =
                bounds.max.z
                - bounds.min.z

            let block =
                try XCTUnwrap(
                    root
                    .childNode(
                        withName:
                            "book.right-page-block",
                        recursively:
                            true
                    )
                )

            let swell =
                try XCTUnwrap(
                    block
                    .childNode(
                        withName:
                            "book.right-page-stack-swell",
                        recursively:
                            false
                    )
                )

            XCTAssertNotNil(
                block
                .childNode(
                    withName:
                        "book.right-page-edge-strata.profile",
                    recursively:
                        true
                )
            )

            return (
                pageRange,
                CGFloat(
                    swell.scale.z
                )
            )
        }

        let hardcover =
            try ranges(
                binding:
                    .hardcover
            )

        let softcover =
            try ranges(
                binding:
                    .softcover
            )

        print(
            "REAL_READING_PAGE "
            + "hardcover=\(hardcover) "
            + "softcover=\(softcover)"
        )

        XCTAssertGreaterThan(
            hardcover.page,
            0.045
        )

        XCTAssertGreaterThan(
            softcover.page,
            0.075
        )

        XCTAssertGreaterThan(
            softcover.page,
            hardcover.page
        )

        XCTAssertEqual(
            hardcover.swellScale,
            11,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            softcover.swellScale,
            15,
            accuracy:
                0.001
        )
    }

    func testOtherCamerasUseCurvedBodyInsteadOfRigidSlab() throws {
        let project =
            project()

        var presentation =
            BookStudioPresentation()

        presentation.open =
            true

        presentation.openAngle =
            160

        presentation.cameraPreset =
            .perspective

        let scene =
            BookPreviewScene
            .make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    160,
                leftPage:
                    100,
                rightPage:
                    101,
                pageCount:
                    300,
                spreadIndex:
                    50,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID(),
                binding:
                    .hardcover,
                presentation:
                    presentation
            )

        let root =
            try XCTUnwrap(
                scene
                .rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let spine =
            try XCTUnwrap(
                root
                .childNode(
                    withName:
                        "book-shell.spine",
                    recursively:
                        false
                )
            )

        XCTAssertTrue(
            spine.isHidden
        )

        let block =
            try XCTUnwrap(
                root
                .childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        true
                )
            )

        let box =
            try XCTUnwrap(
                block.geometry
                as? SCNBox
            )

        XCTAssertFalse(
            box.materials
            .contains {
                $0.transparency
                > 0.9
            }
        )
    }
}

final class RealCurvedPageVolumeRegressionTests:
    XCTestCase
{
    private func project() -> CoverProject {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        return project
    }

    private func readingScene(
        binding:
            BookBinding
    ) -> SCNScene {
        let project =
            project()

        let pageCount =
            300

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        let presentation =
            BookStudioPresentation
            .restingOpenPreviewDefault

        return BookPreviewScene
            .make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    presentation
                    .openAngle,
                leftPage:
                    spread * 2,
                rightPage:
                    spread * 2 + 1,
                pageCount:
                    pageCount,
                spreadIndex:
                    spread,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .reading,
                revisionID:
                    UUID(),
                binding:
                    binding,
                presentation:
                    presentation
            )
    }

    func testBoundStackHasValleyShoulderAndForeEdgeRelaxation() {
        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            let gutter =
                BookPreviewScene
                .pageStackBodyOffset(
                    distanceFromGutter:
                        0,
                    binding:
                        binding,
                    fullness:
                        0.5666667
                )

            let shoulder =
                BookPreviewScene
                .pageStackBodyOffset(
                    distanceFromGutter:
                        0.42,
                    binding:
                        binding,
                    fullness:
                        0.5666667
                )

            let fore =
                BookPreviewScene
                .pageStackBodyOffset(
                    distanceFromGutter:
                        1,
                    binding:
                        binding,
                    fullness:
                        0.5666667
                )

            print(
                "BOUND_STACK_PROFILE "
                + "\(binding) "
                + "gutter=\(gutter) "
                + "shoulder=\(shoulder) "
                + "fore=\(fore)"
            )

            XCTAssertLessThan(
                gutter,
                -0.015
            )

            XCTAssertGreaterThan(
                shoulder,
                0.020
            )

            XCTAssertGreaterThan(
                shoulder
                - gutter,
                0.045
            )

            XCTAssertGreaterThan(
                fore,
                0
            )

            XCTAssertLessThan(
                fore,
                shoulder
            )
        }
    }

    func testReadingHasClosedCurvedPaperVolumeOnBothSides() throws {
        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            let scene =
                readingScene(
                    binding:
                        binding
                )

            let root =
                try XCTUnwrap(
                    scene
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            for side in [
                "left",
                "right"
            ] {
                let block =
                    try XCTUnwrap(
                        root
                        .childNode(
                            withName:
                                "book.\(side)-page-block",
                            recursively:
                                true
                        )
                    )

                let box =
                    try XCTUnwrap(
                        block.geometry
                        as? SCNBox
                    )

                let volume =
                    try XCTUnwrap(
                        block
                        .childNode(
                            withName:
                                "book.\(side)-page-volume",
                            recursively:
                                false
                        )
                    )

                let geometry =
                    try XCTUnwrap(
                        volume.geometry
                    )

                // Correct Swift SceneKit API for this SDK.
                let vertexCount =
                    geometry
                    .sources
                    .first?
                    .vectorCount
                    ?? 0

                XCTAssertGreaterThan(
                    vertexCount,
                    100
                )

                XCTAssertEqual(
                    geometry
                    .elements
                    .count,
                    6
                )

                XCTAssertEqual(
                    geometry
                    .materials
                    .count,
                    6
                )

                XCTAssertFalse(
                    volume.isHidden
                )

                XCTAssertTrue(
                    volume.castsShadow
                )

                let bounds =
                    geometry
                    .boundingBox

                XCTAssertGreaterThan(
                    bounds.max.x
                    - bounds.min.x,
                    4
                )

                XCTAssertGreaterThan(
                    bounds.max.y
                    - bounds.min.y,
                    5
                )

                XCTAssertGreaterThan(
                    bounds.max.z
                    - bounds.min.z,
                    box.length
                )

                let swell =
                    try XCTUnwrap(
                        block
                        .childNode(
                            withName:
                                "book.\(side)-page-stack-swell",
                            recursively:
                                false
                        )
                    )

                XCTAssertTrue(
                    swell.isHidden
                )

                XCTAssertNotNil(
                    block
                    .childNode(
                        withName:
                            "book.\(side)-page-edge-strata",
                        recursively:
                            false
                    )
                )
            }
        }
    }

    func testCurvedPaperBodyFollowsLivePageMass() throws {
        let scene =
            readingScene(
                binding:
                    .softcover
            )

        let root =
            try XCTUnwrap(
                scene
                .rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let block =
            try XCTUnwrap(
                root
                .childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        true
                )
            )

        let volume =
            try XCTUnwrap(
                block
                .childNode(
                    withName:
                        "book.right-page-volume",
                    recursively:
                        false
                )
            )

        let total:
            CGFloat =
                0.82

        let shallow:
            CGFloat =
                0.16

        let deep:
            CGFloat =
                0.66

        BookPreviewScene
            .updatePageEdgeFan(
                blockNode:
                    block,
                side:
                    .right,
                depth:
                    shallow,
                totalDepth:
                    total,
                binding:
                    .softcover
            )

        let shallowBounds =
            try XCTUnwrap(
                volume.geometry
            )
            .boundingBox

        let shallowRange =
            shallowBounds.max.z
            - shallowBounds.min.z

        BookPreviewScene
            .updatePageEdgeFan(
                blockNode:
                    block,
                side:
                    .right,
                depth:
                    deep,
                totalDepth:
                    total,
                binding:
                    .softcover
            )

        let deepBounds =
            try XCTUnwrap(
                volume.geometry
            )
            .boundingBox

        let deepRange =
            deepBounds.max.z
            - deepBounds.min.z

        print(
            "LIVE_PAGE_VOLUME "
            + "shallow=\(shallowRange) "
            + "deep=\(deepRange)"
        )

        XCTAssertGreaterThan(
            deepRange,
            shallowRange
            + 0.40
        )
    }

    func testSoftcoverPageBodyFlexesMoreThanHardcover() {
        let hard =
            BookPreviewScene
            .pageStackBodyOffset(
                distanceFromGutter:
                    0.42,
                binding:
                    .hardcover,
                fullness:
                    0.56
            )
            - BookPreviewScene
            .pageStackBodyOffset(
                distanceFromGutter:
                    0,
                binding:
                    .hardcover,
                fullness:
                    0.56
            )

        let soft =
            BookPreviewScene
            .pageStackBodyOffset(
                distanceFromGutter:
                    0.42,
                binding:
                    .softcover,
                fullness:
                    0.56
            )
            - BookPreviewScene
            .pageStackBodyOffset(
                distanceFromGutter:
                    0,
                binding:
                    .softcover,
                fullness:
                    0.56
            )

        XCTAssertGreaterThan(
            soft,
            hard
        )
    }
}

final class BoundPaperSurfaceRegressionTests:
    XCTestCase
{
    private func project() -> CoverProject {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        return project
    }

    private func readingScene(
        binding:
            BookBinding
    ) -> SCNScene {
        let project =
            project()

        let pageCount =
            300

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        let presentation =
            BookStudioPresentation
            .restingOpenPreviewDefault

        return BookPreviewScene
            .make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    presentation
                    .openAngle,
                leftPage:
                    spread * 2,
                rightPage:
                    spread * 2 + 1,
                pageCount:
                    pageCount,
                spreadIndex:
                    spread,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .reading,
                revisionID:
                    UUID(),
                binding:
                    binding,
                presentation:
                    presentation
            )
    }

    func testBoundPaperHasLongitudinalShapeWithoutMeltingAtHeadAndTail() {
        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            let tail =
                BookPreviewScene
                .pageStackLongitudinalOffset(
                    verticalPosition:
                        0,
                    distanceFromGutter:
                        0.75,
                    binding:
                        binding,
                    fullness:
                        0.56
                )

            let middle =
                BookPreviewScene
                .pageStackLongitudinalOffset(
                    verticalPosition:
                        0.5,
                    distanceFromGutter:
                        0.75,
                    binding:
                        binding,
                    fullness:
                        0.56
                )

            let head =
                BookPreviewScene
                .pageStackLongitudinalOffset(
                    verticalPosition:
                        1,
                    distanceFromGutter:
                        0.75,
                    binding:
                        binding,
                    fullness:
                        0.56
                )

            print(
                "LONGITUDINAL_PAPER "
                + "\(binding) "
                + "tail=\(tail) "
                + "middle=\(middle) "
                + "head=\(head)"
            )

            XCTAssertEqual(
                tail,
                0,
                accuracy:
                    0.000_001
            )

            XCTAssertEqual(
                head,
                0,
                accuracy:
                    0.000_001
            )

            XCTAssertGreaterThan(
                middle,
                0.003
            )

            XCTAssertLessThan(
                middle,
                0.014
            )
        }
    }

    func testSoftcoverLongitudinalPaperFlexExceedsHardcover() {
        let hard =
            BookPreviewScene
            .pageStackLongitudinalOffset(
                verticalPosition:
                    0.5,
                distanceFromGutter:
                    0.8,
                binding:
                    .hardcover,
                fullness:
                    0.56
            )

        let soft =
            BookPreviewScene
            .pageStackLongitudinalOffset(
                verticalPosition:
                    0.5,
                distanceFromGutter:
                    0.8,
                binding:
                    .softcover,
                fullness:
                    0.56
            )

        XCTAssertGreaterThan(
            soft,
            hard
        )
    }

    func testVisiblePageVolumeUsesDenseTwoDimensionalSurface() throws {
        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            let scene =
                readingScene(
                    binding:
                        binding
                )

            let root =
                try XCTUnwrap(
                    scene
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            for side in [
                "left",
                "right"
            ] {
                let volume =
                    try XCTUnwrap(
                        root
                        .childNode(
                            withName:
                                "book.\(side)-page-volume",
                            recursively:
                                true
                        )
                    )

                let geometry =
                    try XCTUnwrap(
                        volume.geometry
                    )

                let vertexCount =
                    geometry
                    .sources
                    .first?
                    .vectorCount
                    ?? 0

                // 2 surfaces × 37 X samples × 15 Y samples = 1,110 vertices.
                XCTAssertEqual(
                    vertexCount,
                    1110
                )

                XCTAssertEqual(
                    geometry
                    .elements
                    .count,
                    6
                )
            }
        }
    }

    func testReadingTopPageCurvatureIsBoundedByItsPhysicalPageMass() throws {
        func pageRange(
            binding:
                BookBinding
        ) throws -> (range: CGFloat, depth: CGFloat) {
            let scene =
                readingScene(
                    binding:
                        binding
                )

            let root =
                try XCTUnwrap(
                    scene
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            let page =
                try XCTUnwrap(
                    root
                    .childNode(
                        withName:
                            "book.right-active-page",
                        recursively:
                            true
                    )
                )

            let bounds =
                try XCTUnwrap(
                    page.geometry
                )
                .boundingBox

            let block = try XCTUnwrap(root.childNode(withName:"book.right-page-block",recursively:true)?.geometry as? SCNBox)
            return (bounds.max.z-bounds.min.z,block.length)
        }

        let hardcover =
            try pageRange(
                binding:
                    .hardcover
            )

        let softcover =
            try pageRange(
                binding:
                    .softcover
            )

        print(
            "TOP_PAGE_RANGE "
            + "hardcover=\(hardcover) "
            + "softcover=\(softcover)"
        )

        XCTAssertGreaterThan(
            hardcover.range,
            0.045
        )

        XCTAssertLessThan(
            hardcover.range,
            hardcover.depth + 0.075
        )

        XCTAssertGreaterThan(
            softcover.range,
            hardcover.range
        )

        XCTAssertLessThan(
            softcover.range,
            softcover.depth + 0.075
        )
    }
}

final class PhysicalBookBindingGutterRegressionTests:
    XCTestCase
{
    private func project() -> CoverProject {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        return project
    }

    private func readingScene(
        binding:
            BookBinding
    ) -> SCNScene {
        let project =
            project()

        let pageCount =
            300

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        let presentation =
            BookStudioPresentation
            .restingOpenPreviewDefault

        return BookPreviewScene
            .make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    presentation
                    .openAngle,
                leftPage:
                    spread * 2,
                rightPage:
                    spread * 2 + 1,
                pageCount:
                    pageCount,
                spreadIndex:
                    spread,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .reading,
                revisionID:
                    UUID(),
                binding:
                    binding,
                presentation:
                    presentation
            )
    }

    func testBindingFoldDepthIsRestrainedAndSoftcoverIsDeeper() {
        let hard =
            BookPreviewScene
            .pageGutterFoldDepth(
                binding:
                    .hardcover,
                fullness:
                    0.56
            )

        let soft =
            BookPreviewScene
            .pageGutterFoldDepth(
                binding:
                    .softcover,
                fullness:
                    0.56
            )

        print(
            "GUTTER_FOLD_DEPTH "
            + "hardcover=\(hard) "
            + "softcover=\(soft)"
        )

        XCTAssertGreaterThan(
            hard,
            0.010
        )

        XCTAssertLessThan(
            hard,
            0.024
        )

        XCTAssertGreaterThan(
            soft,
            hard
        )

        XCTAssertLessThan(
            soft,
            0.035
        )
    }

    func testReadingSceneHasNarrowBoundGutterFoldOnBothPageMasses() throws {
        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            let scene =
                readingScene(
                    binding:
                        binding
                )

            let root =
                try XCTUnwrap(
                    scene
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            for side in [
                "left",
                "right"
            ] {
                let block =
                    try XCTUnwrap(
                        root
                        .childNode(
                            withName:
                                "book.\(side)-page-block",
                            recursively:
                                true
                        )
                    )

                let fold =
                    try XCTUnwrap(
                        block
                        .childNode(
                            withName:
                                "book.\(side)-gutter-fold",
                            recursively:
                                false
                        )
                    )

                let geometry =
                    try XCTUnwrap(
                        fold.geometry
                    )

                let vertexCount =
                    geometry
                    .sources
                    .first?
                    .vectorCount
                    ?? 0

                // 13 X samples × 15 Y samples.
                XCTAssertEqual(
                    vertexCount,
                    195
                )

                XCTAssertFalse(
                    fold.isHidden
                )

                XCTAssertTrue(
                    fold.castsShadow
                )

                let bounds =
                    geometry
                    .boundingBox

                XCTAssertGreaterThan(
                    bounds.max.y
                    - bounds.min.y,
                    5
                )

                // V19: V18C measured that the printed page hinges already meet.
                // Keep a narrow physical crease without allowing the blank
                // gutter overlay to cover the printed inner-page surface.
                XCTAssertGreaterThan(
                    bounds.max.x
                    - bounds.min.x,
                    0.04
                )

                XCTAssertLessThan(
                    bounds.max.x
                    - bounds.min.x,
                    0.10
                )

                XCTAssertGreaterThan(
                    bounds.max.z
                    - bounds.min.z,
                    0.005
                )
            }
        }
    }

    func testPageVolumeEdgeMaterialHasPaperMicrorelief() throws {
        let scene =
            readingScene(
                binding:
                    .hardcover
            )

        let root =
            try XCTUnwrap(
                scene
                .rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let volume =
            try XCTUnwrap(
                root
                .childNode(
                    withName:
                        "book.right-page-volume",
                    recursively:
                        true
                )
            )

        let geometry =
            try XCTUnwrap(
                volume.geometry
            )

        XCTAssertEqual(
            geometry
            .materials
            .count,
            6
        )

        // Material slots 2...5 are exposed page-stack edges.
        for material in
            geometry
            .materials[
                2...5
            ]
        {
            XCTAssertNotNil(
                material
                .normal
                .contents
            )

            XCTAssertEqual(
                material
                .normal
                .intensity,
                0.16,
                accuracy:
                    0.001
            )
        }
    }

    func testGutterFoldTracksLivePageMassTransfer() throws {
        let scene =
            readingScene(
                binding:
                    .softcover
            )

        let root =
            try XCTUnwrap(
                scene
                .rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let block =
            try XCTUnwrap(
                root
                .childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        true
                )
            )

        let fold =
            try XCTUnwrap(
                block
                .childNode(
                    withName:
                        "book.right-gutter-fold",
                    recursively:
                        false
                )
            )

        let total:
            CGFloat =
                0.82

        BookPreviewScene
            .updatePageEdgeFan(
                blockNode:
                    block,
                side:
                    .right,
                depth:
                    0.16,
                totalDepth:
                    total,
                binding:
                    .softcover
            )

        let shallow =
            try XCTUnwrap(
                fold.geometry
            )
            .boundingBox

        BookPreviewScene
            .updatePageEdgeFan(
                blockNode:
                    block,
                side:
                    .right,
                depth:
                    0.66,
                totalDepth:
                    total,
                binding:
                    .softcover
            )

        let deep =
            try XCTUnwrap(
                fold.geometry
            )
            .boundingBox

        let shallowCenter =
            (
                shallow.max.z
                + shallow.min.z
            )
            / 2

        let deepCenter =
            (
                deep.max.z
                + deep.min.z
            )
            / 2

        print(
            "LIVE_GUTTER_FOLD "
            + "shallowCenter=\(shallowCenter) "
            + "deepCenter=\(deepCenter)"
        )

        XCTAssertGreaterThan(
            deepCenter,
            shallowCenter
            + 0.20
        )

        XCTAssertFalse(
            fold.isHidden
        )
    }
}

final class VisibleBoundLeafStackRegressionTests:
    XCTestCase
{
    private func project() -> CoverProject {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        return project
    }

    private func readingScene(
        binding:
            BookBinding
    ) -> SCNScene {
        let project =
            project()

        let pageCount =
            300

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        let presentation =
            BookStudioPresentation
            .restingOpenPreviewDefault

        return BookPreviewScene
            .make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    presentation
                    .openAngle,
                leftPage:
                    spread * 2,
                rightPage:
                    spread * 2 + 1,
                pageCount:
                    pageCount,
                spreadIndex:
                    spread,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .reading,
                revisionID:
                    UUID(),
                binding:
                    binding,
                presentation:
                    presentation
            )
    }

    func testReadingAddsSeveralFullCurvedLeavesBeneathEachActivePage() throws {
        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            let scene =
                readingScene(
                    binding:
                        binding
                )

            let root =
                try XCTUnwrap(
                    scene
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            let expectedCount =
                binding == .hardcover
                ? 5
                : 7

            for side in [
                "left",
                "right"
            ] {
                let active =
                    try XCTUnwrap(
                        root
                        .childNode(
                            withName:
                                "book.\(side)-active-page",
                            recursively:
                                true
                        )
                    )

                var previousDepth:
                    CGFloat =
                        0

                for index in
                    1...expectedCount
                {
                    let leaf =
                        try XCTUnwrap(
                            active
                            .childNode(
                                withName:
                                    "book.\(side)-visible-leaf-\(index)",
                                recursively:
                                    false
                            )
                        )

                    XCTAssertTrue(
                        leaf.parent
                        === active
                    )

                    XCTAssertNotNil(
                        leaf.geometry
                    )

                    XCTAssertFalse(
                        leaf.geometry
                        is SCNPlane
                    )

                    XCTAssertTrue(
                        leaf.castsShadow
                    )

                    XCTAssertLessThan(
                        leaf.position.z,
                        0
                    )

                    if index > 1 {
                        XCTAssertLessThan(
                            leaf.position.z,
                            previousDepth
                        )
                    }

                    previousDepth =
                        leaf.position.z

                    let material =
                        try XCTUnwrap(
                            leaf
                            .geometry?
                            .firstMaterial
                        )

                    XCTAssertEqual(
                        material
                        .lightingModel,
                        .physicallyBased
                    )

                    XCTAssertTrue(
                        material
                        .isDoubleSided
                    )
                }

                let found =
                    active
                    .childNodes
                    .filter {
                        $0.name?
                        .hasPrefix(
                            "book.\(side)-visible-leaf-"
                        )
                        == true
                    }
                    .count

                XCTAssertEqual(
                    found,
                    expectedCount
                )
            }
        }
    }

    func testSoftcoverShowsMoreVisibleTopLeavesThanHardcover() throws {
        func count(
            binding:
                BookBinding
        ) throws -> Int {
            let scene =
                readingScene(
                    binding:
                        binding
                )

            let root =
                try XCTUnwrap(
                    scene
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            let active =
                try XCTUnwrap(
                    root
                    .childNode(
                        withName:
                            "book.right-active-page",
                        recursively:
                            true
                    )
                )

            return
                active
                .childNodes
                .filter {
                    $0.name?
                    .hasPrefix(
                        "book.right-visible-leaf-"
                    )
                    == true
                }
                .count
        }

        let hardcover =
            try count(
                binding:
                    .hardcover
            )

        let softcover =
            try count(
                binding:
                    .softcover
            )

        print(
            "VISIBLE_LEAF_COUNT "
            + "hardcover=\(hardcover) "
            + "softcover=\(softcover)"
        )

        XCTAssertEqual(
            hardcover,
            5
        )

        XCTAssertEqual(
            softcover,
            7
        )

        XCTAssertGreaterThan(
            softcover,
            hardcover
        )
    }

    func testVisibleLeafStackRemainsTightlyCompressed() throws {
        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            let scene =
                readingScene(
                    binding:
                        binding
                )

            let root =
                try XCTUnwrap(
                    scene
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            let active =
                try XCTUnwrap(
                    root
                    .childNode(
                        withName:
                            "book.right-active-page",
                        recursively:
                            true
                    )
                )

            let layers =
                active
                .childNodes
                .filter {
                    $0.name?
                    .hasPrefix(
                        "book.right-visible-leaf-"
                    )
                    == true
                }

            let deepest =
                try XCTUnwrap(
                    layers
                    .map {
                        $0.position.z
                    }
                    .min()
                )

            print(
                "VISIBLE_LEAF_DEPTH "
                + "\(binding)="
                + "\(deepest)"
            )

            XCTAssertGreaterThan(
                deepest,
                -0.020
            )

            XCTAssertLessThan(
                deepest,
                -0.008
            )
        }
    }

    func testVisibleLeavesHaveTinyDeterministicTrimVariation() throws {
        let scene =
            readingScene(
                binding:
                    .softcover
            )

        let root =
            try XCTUnwrap(
                scene
                .rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let active =
            try XCTUnwrap(
                root
                .childNode(
                    withName:
                        "book.right-active-page",
                    recursively:
                        true
                )
            )

        let leaves =
            active
            .childNodes
            .filter {
                $0.name?
                .hasPrefix(
                    "book.right-visible-leaf-"
                )
                == true
            }

        XCTAssertEqual(
            leaves.count,
            7
        )

        let maxX =
            leaves
            .map {
                abs(
                    $0.position.x
                )
            }
            .max()
            ?? 0

        let maxY =
            leaves
            .map {
                abs(
                    $0.position.y
                )
            }
            .max()
            ?? 0

        XCTAssertGreaterThan(
            maxX,
            0
        )

        XCTAssertLessThan(
            maxX,
            0.003
        )

        XCTAssertGreaterThan(
            maxY,
            0
        )

        XCTAssertLessThan(
            maxY,
            0.002
        )
    }

    func testOtherCamerasKeepUnderlyingLeaves() throws {
        let project =
            project()

        var presentation =
            BookStudioPresentation()

        presentation.open =
            true

        presentation.openAngle =
            160

        presentation.cameraPreset =
            .perspective

        let scene =
            BookPreviewScene
            .make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    160,
                leftPage:
                    100,
                rightPage:
                    101,
                pageCount:
                    300,
                spreadIndex:
                    50,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID(),
                binding:
                    .hardcover,
                presentation:
                    presentation
            )

        let root =
            try XCTUnwrap(
                scene
                .rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        if let active =
            root
            .childNode(
                withName:
                    "book.right-active-page",
                recursively:
                    true
            )
        {
            XCTAssertTrue(
                active
                .childNodes
                .contains {
                    $0.name?
                    .contains(
                        "-visible-leaf-"
                    )
                    == true
                }
            )
        }
    }
}

final class PhysicalBookEndpaperRegressionTests:
    XCTestCase
{
    private func project() -> CoverProject {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        return project
    }

    private func readingScene(
        binding:
            BookBinding
    ) -> SCNScene {
        let project =
            project()

        let pageCount =
            300

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        let presentation =
            BookStudioPresentation
            .restingOpenPreviewDefault

        return BookPreviewScene
            .make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    presentation
                    .openAngle,
                leftPage:
                    spread * 2,
                rightPage:
                    spread * 2 + 1,
                pageCount:
                    pageCount,
                spreadIndex:
                    spread,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .reading,
                revisionID:
                    UUID(),
                binding:
                    binding,
                presentation:
                    presentation
            )
    }

    func testReadingEndpaperLiningContactsItsSupportingBoardUnderBothPageMasses() throws {
        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            let scene =
                readingScene(
                    binding:
                        binding
                )

            let root =
                try XCTUnwrap(
                    scene
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            for side in [
                "left",
                "right"
            ] {
                let block =
                    try XCTUnwrap(
                        root
                        .childNode(
                            withName:
                                "book.\(side)-page-block",
                            recursively:
                                true
                        )
                    )

                let box =
                    try XCTUnwrap(
                        block.geometry
                        as? SCNBox
                    )

                let endpaper =
                    try XCTUnwrap(
                        block
                        .childNode(
                            withName:
                                "book.\(side)-endpaper",
                            recursively:
                                false
                        )
                    )

                let geometry =
                    try XCTUnwrap(
                        endpaper.geometry
                    )

                let bounds =
                    geometry
                    .boundingBox

                XCTAssertGreaterThan(
                    bounds.max.x
                    - bounds.min.x,
                    box.width
                    + (binding == .hardcover ? 0.05 : -0.0001)
                )

                XCTAssertGreaterThan(
                    bounds.max.y
                    - bounds.min.y,
                    box.height
                    + (binding == .hardcover ? 0.05 : -0.0001)
                )

                // The endpaper is pasted to the supporting board, not a
                // second independent curved slab floating through the pages.
                let cover=try XCTUnwrap(root.childNode(
                    withName: side == "left" ? "book-shell.front-cover":"book-shell.back-cover",
                    recursively:true))
                let coverBounds=try XCTUnwrap(cover.geometry).boundingBox
                let front=side == "left"
                let flex=(cover.geometry is SCNBox) ? nil:cover.geometry?.sources(for:.vertex).first.map(BookOpenGutterGeometry.vertices)
                let source=try XCTUnwrap(geometry.sources(for:.vertex).first)
                for vertex in BookOpenGutterGeometry.vertices(source) {
                    let local=cover.convertPosition(vertex,from:endpaper)
                    var lining=front ? coverBounds.min.z:coverBounds.max.z
                    if let flex {
                        let u=min(24,max(0,(local.x-coverBounds.min.x)/(coverBounds.max.x-coverBounds.min.x)*24))
                        let i=min(23,Int(u)),t=u-CGFloat(i),offset=front ? 50:0
                        lining=flex[i*2+offset].z+(flex[(i+1)*2+offset].z-flex[i*2+offset].z)*t
                    }
                    XCTAssertEqual((local.z-lining)*(front ? -1:1),0.001,accuracy:0.00002)
                }

                XCTAssertTrue(
                    endpaper.castsShadow
                )

                XCTAssertFalse(
                    endpaper.isHidden
                )

                XCTAssertEqual(
                    geometry
                    .sources
                    .first?
                    .vectorCount,
                    319
                )
            }
        }
    }

    func testHardcoverEndpaperOverhangExceedsSoftcover() throws {
        func width(
            binding:
                BookBinding
        ) throws -> CGFloat {
            let scene =
                readingScene(
                    binding:
                        binding
                )

            let root =
                try XCTUnwrap(
                    scene
                    .rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
                )

            let endpaper =
                try XCTUnwrap(
                    root
                    .childNode(
                        withName:
                            "book.right-endpaper",
                        recursively:
                            true
                    )
                )

            let bounds =
                try XCTUnwrap(
                    endpaper.geometry
                )
                .boundingBox

            return
                bounds.max.x
                - bounds.min.x
        }

        let hardcover =
            try width(
                binding:
                    .hardcover
            )

        let softcover =
            try width(
                binding:
                    .softcover
            )

        print(
            "ENDPAPER_WIDTH "
            + "hardcover=\(hardcover) "
            + "softcover=\(softcover)"
        )

        XCTAssertGreaterThan(
            hardcover,
            softcover
        )
    }

    func testEndpaperTracksLivePageMassDepth() throws {
        let scene =
            readingScene(
                binding:
                    .softcover
            )

        let root =
            try XCTUnwrap(
                scene
                .rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        let block =
            try XCTUnwrap(
                root
                .childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        true
                )
            )

        let endpaper =
            try XCTUnwrap(
                block
                .childNode(
                    withName:
                        "book.right-endpaper",
                    recursively:
                        false
                )
            )

        let total:
            CGFloat =
                0.82

        BookPreviewScene
            .updatePageEdgeFan(
                blockNode:
                    block,
                side:
                    .right,
                depth:
                    0.18,
                totalDepth:
                    total,
                binding:
                    .softcover
            )

        let shallow =
            try XCTUnwrap(
                endpaper.geometry
            )
            .boundingBox

        BookPreviewScene
            .updatePageEdgeFan(
                blockNode:
                    block,
                side:
                    .right,
                depth:
                    0.66,
                totalDepth:
                    total,
                binding:
                    .softcover
            )

        let deep =
            try XCTUnwrap(
                endpaper.geometry
            )
            .boundingBox

        let shallowCenter =
            (
                shallow.max.z
                + shallow.min.z
            )
            / 2

        let deepCenter =
            (
                deep.max.z
                + deep.min.z
            )
            / 2

        print(
            "LIVE_ENDPAPER "
            + "shallowCenter=\(shallowCenter) "
            + "deepCenter=\(deepCenter)"
        )

        XCTAssertLessThan(
            deepCenter,
            shallowCenter
            - 0.20
        )

        XCTAssertFalse(
            endpaper.isHidden
        )
    }

    func testOtherCamerasKeepPhysicalEndpapers() throws {
        let project =
            project()

        var presentation =
            BookStudioPresentation()

        presentation.open =
            true

        presentation.openAngle =
            160

        presentation.cameraPreset =
            .perspective

        let scene =
            BookPreviewScene
            .make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    160,
                leftPage:
                    100,
                rightPage:
                    101,
                pageCount:
                    300,
                spreadIndex:
                    50,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID(),
                binding:
                    .hardcover,
                presentation:
                    presentation
            )

        let root =
            try XCTUnwrap(
                scene
                .rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
            )

        XCTAssertNotNil(
            root
            .childNode(
                withName:
                    "book.right-endpaper",
                recursively:
                    true
            )
        )
    }
}

final class ReadingBackCoverAlignmentRegressionTests:
    XCTestCase
{
    private func project() -> CoverProject {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        return project
    }

    private func readingScene(
        binding:
            BookBinding
    ) -> SCNScene {
        let project =
            project()

        let pageCount =
            300

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        let presentation =
            BookStudioPresentation
            .restingOpenPreviewDefault

        return BookPreviewScene.make(
            project:
                project,
            workingLayers:
                false,
            open:
                true,
            angle:
                presentation.openAngle,
            leftPage:
                spread * 2,
            rightPage:
                spread * 2 + 1,
            pageCount:
                pageCount,
            spreadIndex:
                spread,
            leftTexture:
                nil,
            rightTexture:
                nil,
            margins:
                false,
            thumbMode:
                .off,
            leftPageSettings:
                PageSettings(),
            rightPageSettings:
                PageSettings(),
            preset:
                .reading,
            revisionID:
                UUID(),
            binding:
                binding,
            presentation:
                presentation
        )
    }

    private func innerEdgeX(
        node:
            SCNNode,
        root:
            SCNNode
    ) -> CGFloat {
        let bounds =
            node.geometry?.boundingBox
            ?? node.boundingBox

        let centerY:
            CGFloat =
                (
                    bounds.min.y
                    + bounds.max.y
                )
                / 2

        let centerZ:
            CGFloat =
                (
                    bounds.min.z
                    + bounds.max.z
                )
                / 2

        let negative =
            node.convertPosition(
                SCNVector3(
                    bounds.min.x,
                    centerY,
                    centerZ
                ),
                to:
                    root
            )

        let positive =
            node.convertPosition(
                SCNVector3(
                    bounds.max.x,
                    centerY,
                    centerZ
                ),
                to:
                    root
            )

        return
            abs(
                negative.x
            )
            <= abs(
                positive.x
            )
            ? negative.x
            : positive.x
    }

    func testReadingRightCoverInnerEdgeReturnsToPageBlock()
    throws
    {
        for binding in [
            BookBinding.hardcover,
            .softcover
        ] {
            let scene =
                readingScene(
                    binding:
                        binding
                )

            let root =
                try XCTUnwrap(
                    scene.rootNode.childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            true
                    )
                )

            let cover =
                try XCTUnwrap(
                    root.childNode(
                        withName:
                            "book-shell.back-cover",
                        recursively:
                            true
                    )
                )

            let pageBlock =
                try XCTUnwrap(
                    root.childNode(
                        withName:
                            "book.right-page-block",
                        recursively:
                            true
                    )
                )

            let coverInner =
                innerEdgeX(
                    node:
                        cover,
                    root:
                        root
                )

            let pageInner =
                innerEdgeX(
                    node:
                        pageBlock,
                    root:
                        root
                )

            let correction =
                try XCTUnwrap(
                    cover.value(
                        forKey:
                            "bookReadingBackCoverAlignmentX"
                    )
                    as? NSNumber
                )
                .doubleValue

            print(
                "RIGHT_COVER_FIXED "
                + "\(binding) "
                + "coverPositionX=\(cover.position.x) "
                + "coverInnerX=\(coverInner) "
                + "pageInnerX=\(pageInner) "
                + "correctionX=\(correction)"
            )

            XCTAssertLessThan(
                abs(
                    coverInner
                    - pageInner
                ),
                0.20
            )

            XCTAssertLessThan(
                cover.position.x,
                3.0
            )

            XCTAssertLessThan(
                correction,
                -1.0
            )
        }
    }

    func testPaperGutterWasNotMovedByCoverFix() throws {
        let scene=readingScene(binding:.hardcover)
        let root=try XCTUnwrap(scene.rootNode.childNode(withName:"physical-book.root",recursively:true))
        for (side,index) in [("left",72),("right",0)] {
            let page=try XCTUnwrap(root.childNode(withName:"book.\(side)-active-page",recursively:true))
            let points=BookOpenGutterGeometry.vertices(try XCTUnwrap(page.geometry?.sources(for:.vertex).first))
            XCTAssertEqual(page.convertPosition(points[index],to:root).x,0,accuracy:0.00001,
                "Measure the printed binding, not the case support beneath it")
        }
    }

    func testOtherCamerasKeepCommonGutterAlignment()
    throws
    {
        let project =
            project()

        var presentation =
            BookStudioPresentation()

        presentation.open =
            true

        presentation.openAngle =
            160

        presentation.cameraPreset =
            .perspective

        let scene =
            BookPreviewScene.make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    160,
                leftPage:
                    130,
                rightPage:
                    131,
                pageCount:
                    300,
                spreadIndex:
                    65,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .perspective,
                revisionID:
                    UUID(),
                binding:
                    .hardcover,
                presentation:
                    presentation
            )

        let cover =
            try XCTUnwrap(
                scene.rootNode.childNode(
                    withName:
                        "book-shell.back-cover",
                    recursively:
                        true
                )
            )

        XCTAssertNotNil(
            cover.value(
                forKey:
                    "bookReadingBackCoverAlignmentX"
            )
        )
    }
}


// BOLD WRITER V10 — Reading tabletop presentation regression.
final class ReadingTabletopPresentationRegressionTests:
    XCTestCase
{
    func testReadingPresentationPlacesOpenPagesParallelToStudioGround()
        throws
    {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            1.2

        let presentation =
            BookStudioPresentation(
                binding:
                    .hardcover,
                open:
                    true,
                openAngle:
                    180,
                spreadIndex:
                    75,
                cameraPreset:
                    .reading
            )
            .normalized(
                pageCount:
                    300
            )

        let scene =
            BookPreviewScene.make(
                project:
                    project,
                workingLayers:
                    false,
                open:
                    true,
                angle:
                    180,
                leftPage:
                    150,
                rightPage:
                    151,
                pageCount:
                    300,
                spreadIndex:
                    75,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .reading,
                revisionID:
                    UUID(),
                binding:
                    .hardcover,
                presentation:
                    presentation
            )

        BookStudioTransformScene.apply(
            to:
                scene,
            presentation:
                presentation,
            selectedCustomLightID:
                nil
        )

        let leftPage =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "book.left-active-page",
                        recursively:
                            true
                    )
            )

        let normal =
            leftPage.convertVector(
                SCNVector3(
                    0,
                    0,
                    1
                ),
                to:
                    scene.rootNode
            )

        let length =
            sqrt(
                normal.x * normal.x
                + normal.y * normal.y
                + normal.z * normal.z
            )

        XCTAssertGreaterThan(
            length,
            0.999
        )

        let x =
            normal.x / length

        let y =
            normal.y / length

        let z =
            normal.z / length

        XCTAssertEqual(
            x,
            0,
            accuracy:
                0.03,
            "Reading mode must not roll an open spread sideways."
        )

        XCTAssertGreaterThan(
            y,
            0.99,
            "Reading mode must turn the printed page normal upward toward +Y."
        )

        XCTAssertEqual(
            z,
            0,
            accuracy:
                0.03,
            "A fully-open Reading spread must be parallel to the XZ studio floor."
        )

        XCTAssertEqual(
            presentation
                .modelTransform
                .rotationX,
            0,
            accuracy:
                0.000001,
            "The -90° tabletop orientation is a Reading presentation base pose and must not overwrite the user's stored model rotation."
        )
    }
}

// BOLD WRITER V13 — keep camera framing in the same space as the book.
final class ReadingCameraTargetRegressionTests: XCTestCase {
    func testReadingBookRestsOnGroundWithoutClippingOrTransformDrift() throws {
        var project = CoverProject(type: .printFullWrap)
        project.trimWidth = 6; project.backWidth = 6; project.trimHeight = 9; project.spineWidth = 1.2
        for binding in BookBinding.allCases {
            for angle in [160.0, 180.0] {
                var presentation = BookStudioPreset.reading.apply(to: BookStudioPresentation())
                presentation.binding = binding
                presentation.openAngle = angle
                let scene = BookPreviewScene.make(project: project, workingLayers: false, open: true, angle: angle,
                    leftPage: 150, rightPage: 151, pageCount: 300, spreadIndex: 75,
                    leftTexture: nil, rightTexture: nil, margins: false, thumbMode: .off,
                    leftPageSettings: PageSettings(), rightPageSettings: PageSettings(), preset: .reading,
                    revisionID: UUID(), binding: binding, presentation: presentation)
                let root = try XCTUnwrap(scene.rootNode.childNode(withName: BookStudioTransformScene.modelRootName, recursively: true))
                let ground = try XCTUnwrap(scene.rootNode.childNode(withName: "studio-ground", recursively: true))
                func lowestPoint() -> CGFloat {
                    var lowest = CGFloat.infinity
                    root.enumerateChildNodes { node, _ in
                        var ancestor: SCNNode? = node
                        while let current = ancestor, current !== root {
                            if current.isHidden { return }; ancestor = current.parent
                        }
                        guard node.name != "book.left-page-block", node.name != "book.right-page-block",
                              let geometry = node.geometry else { return }
                        for point in BookOpenGutterGeometry.surfaceVertices(geometry) {
                            lowest = min(lowest,node.convertPosition(point,to:scene.rootNode).y)
                        }
                    }
                    return lowest
                }
                BookStudioTransformScene.apply(to: scene, presentation: presentation)
                XCTAssertEqual(lowestPoint(), ground.position.y, accuracy: 0.0001)
                let restingY = root.position.y
                BookStudioTransformScene.apply(to: scene, presentation: presentation)
                XCTAssertEqual(root.position.y, restingY, accuracy: 0.0001)
                presentation.modelTransform.positionY = 0.5
                BookStudioTransformScene.apply(to: scene, presentation: presentation)
                XCTAssertEqual(lowestPoint(), ground.position.y + 0.5, accuracy: 0.0001)
            }
        }
    }

    func testPerspectiveFitContainsTransformedBookAtDifferentViewportShapes() {
        for aspect in [0.65, 4.0 / 3, 2.0] {
            for pitch in [0.42, 0.92, 1.48] {
                let scene = SCNScene()
                let book = SCNNode(geometry: SCNBox(width: 11.55, height: 7.7, length: 0.9, chamferRadius: 0))
                book.eulerAngles = SCNVector3(-Double.pi / 2, 0.12, 0.08)
                book.position = SCNVector3(0.2, 0.4, -3.85)
                book.name = BookStudioTransformScene.modelRootName
                scene.rootNode.addChildNode(book)
                var presentation = BookStudioPresentation()
                presentation.open = false
                presentation.cameraFieldOfView = 24
                // Closed front/back/spine views also need viewport fitting; the
                // old Reading-only gate clipped real covers at a 24-degree FOV.
                let fitted = BookPreviewCameraMath.fitBook(
                    BookPreviewCameraState(yaw:0.22,pitch:pitch,distance:1),
                    in:scene,presentation:presentation,viewportAspect:aspect)
                let camera = SCNNode()
                scene.rootNode.addChildNode(camera)
                camera.position = SCNVector3(fitted.target.x + fitted.distance * cos(pitch) * sin(fitted.yaw),
                    fitted.target.y + fitted.distance * sin(pitch),
                    fitted.target.z + fitted.distance * cos(pitch) * cos(fitted.yaw))
                camera.look(at: SCNVector3(fitted.target.x, fitted.target.y, fitted.target.z))
                let bounds = book.boundingBox
                for x in [bounds.min.x, bounds.max.x] {
                    for y in [bounds.min.y, bounds.max.y] {
                        for z in [bounds.min.z, bounds.max.z] {
                            let point = book.convertPosition(SCNVector3(x, y, z), to: camera)
                            let halfHeight = -Double(point.z) * tan(24 * Double.pi / 360)
                            XCTAssertGreaterThan(halfHeight, 0)
                            XCTAssertLessThan(abs(Double(point.x)), halfHeight * aspect)
                            XCTAssertLessThan(abs(Double(point.y)), halfHeight)
                        }
                    }
                }
            }
        }
    }

    func testReadingCameraTargetsTabletopCenterAndPreservesUprightViews() {
        var project = CoverProject(type: .printFullWrap)
        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.spineWidth = 1.2
        for preset in BookViewPreset.allCases {
            for open in [false, true] {
                for focus in [BookFocusTarget.automatic, .text, .spine] {
                    let state = BookPreviewCameraMath.state(project: project, open: open, preset: preset, focus: focus)
                    let tabletop = open && (preset == .reading || preset == .underside || preset == .headEdge || preset == .footEdge || preset == .foreEdge || preset == .lowPerspective)
                    let expectedX = (!open && focus != .spine) || (open && focus == .text) ? 2.1 : 0
                    XCTAssertEqual(state.target.x, expectedX, accuracy: 0.000001)
                    XCTAssertEqual(state.target.y, tabletop ? 0 : 3.15, accuracy: 0.000001)
                    XCTAssertEqual(state.target.z, tabletop ? -3.15 : 0, accuracy: 0.000001)
                }
            }
        }
        let reading = BookStudioPreset.reading.apply(to: BookStudioPresentation())
        XCTAssertEqual(reading.cameraFieldOfView, 24)
        XCTAssertTrue(reading.open)
        XCTAssertEqual(reading.cameraPreset, .reading)
    }
}


final class BookSurfaceBrightnessRegressionTests:
    XCTestCase
{
    private func material(
        intensity:
            CGFloat = 1
    ) -> SCNMaterial
    {
        let material =
            SCNMaterial()

        material
            .diffuse
            .contents =
            NSColor(
                calibratedRed:
                    0.20,
                green:
                    0.16,
                blue:
                    0.10,
                alpha:
                    1
            )

        material
            .diffuse
            .intensity =
            intensity

        return material
    }

    private func node(
        name:
            String
    ) -> SCNNode
    {
        let geometry =
            SCNPlane(
                width:
                    1,
                height:
                    1
            )

        geometry.materials = [
            material()
        ]

        let node =
            SCNNode(
                geometry:
                    geometry
            )

        node.name =
            name

        return node
    }

    func testV17AddsStrongestFillToCoverArtwork()
    {
        let root =
            SCNNode()

        let cover =
            node(
                name:
                    "book-shell.front-cover-artwork"
            )

        root.addChildNode(
            cover
        )

        BookPreviewScene
            .applyBookSurfaceBrightnessFill(
                root:
                    root
            )

        let material =
            try! XCTUnwrap(
                cover
                    .geometry?
                    .firstMaterial
            )

        XCTAssertNotNil(
            material
                .emission
                .contents
        )

        XCTAssertEqual(
            material
                .emission
                .intensity,
            0.34,
            accuracy:
                0.0001
        )
    }

    func testV17AddsRestrainedFillToPrintedPage()
    {
        let root =
            SCNNode()

        let page =
            node(
                name:
                    "book.left-active-page"
            )

        root.addChildNode(
            page
        )

        BookPreviewScene
            .applyBookSurfaceBrightnessFill(
                root:
                    root
            )

        let material =
            try! XCTUnwrap(
                page
                    .geometry?
                    .firstMaterial
            )

        XCTAssertEqual(
            material
                .emission
                .intensity,
            0.18,
            accuracy:
                0.0001
        )
    }

    func testV17DoesNotSelfLightStructuralPageBlock()
    {
        let root =
            SCNNode()

        let block =
            node(
                name:
                    "book.left-page-block"
            )

        root.addChildNode(
            block
        )

        let material =
            try! XCTUnwrap(
                block
                    .geometry?
                    .firstMaterial
            )

        // SceneKit supplies a default black emission property on a fresh
        // SCNMaterial, so nil is NOT the correct baseline expectation.
        // V17's contract is that structural page blocks are not modified.
        let beforeEmissionContents =
            String(
                describing:
                    material
                    .emission
                    .contents
            )

        let beforeEmissionIntensity =
            material
            .emission
            .intensity

        let beforeTransform =
            material
            .emission
            .contentsTransform

        BookPreviewScene
            .applyBookSurfaceBrightnessFill(
                root:
                    root
            )

        XCTAssertEqual(
            String(
                describing:
                    material
                    .emission
                    .contents
            ),
            beforeEmissionContents,
            "V17 must leave structural page-block emission contents unchanged."
        )

        XCTAssertEqual(
            material
                .emission
                .intensity,
            beforeEmissionIntensity,
            accuracy:
                0.0001,
            "V17 must leave structural page-block emission intensity unchanged."
        )

        XCTAssertEqual(
            material
                .emission
                .contentsTransform
                .m11,
            beforeTransform.m11,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            material
                .emission
                .contentsTransform
                .m22,
            beforeTransform.m22,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            material
                .emission
                .contentsTransform
                .m41,
            beforeTransform.m41,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            material
                .emission
                .contentsTransform
                .m42,
            beforeTransform.m42,
            accuracy:
                0.0001
        )
    }
}


final class LiveBookSurfaceBrightnessParityRegressionTests:
    XCTestCase
{
    private func artworkNode()
        -> SCNNode
    {
        let geometry =
            SCNPlane(
                width:
                    1,
                height:
                    1
            )

        let material =
            SCNMaterial()

        material
            .diffuse
            .contents =
            NSColor(
                calibratedRed:
                    0.40,
                green:
                    0.25,
                blue:
                    0.15,
                alpha:
                    1
            )

        geometry.materials = [
            material
        ]

        let node =
            SCNNode(
                geometry:
                    geometry
            )

        node.name =
            "book-shell.front-cover-artwork"

        return node
    }

    func testV17CanBeReappliedAfterLiveStylingMutation()
    {
        let root =
            SCNNode()

        let artwork =
            artworkNode()

        root.addChildNode(
            artwork
        )

        BookPreviewScene
            .applyBookSurfaceBrightnessFill(
                root:
                    root
            )

        let material =
            try! XCTUnwrap(
                artwork
                    .geometry?
                    .firstMaterial
            )

        XCTAssertEqual(
            material
                .emission
                .intensity,
            0.34,
            accuracy:
                0.0001
        )

        // Simulate a post-build live styling/material pass.
        material
            .emission
            .intensity =
            0

        material
            .emission
            .contents =
            NSColor.black

        BookPreviewScene
            .applyBookSurfaceBrightnessFill(
                root:
                    root
            )

        XCTAssertEqual(
            material
                .emission
                .intensity,
            0.34,
            accuracy:
                0.0001,
            "The final live pass must restore the same V17 cover fill."
        )

        XCTAssertEqual(
            String(
                describing:
                    material
                    .emission
                    .contents
            ),
            String(
                describing:
                    material
                    .diffuse
                    .contents
            ),
            "Live parity must restore the diffuse artwork as the emission fill source."
        )
    }

    func testV17LiveReapplicationRemainsIdempotent()
    {
        let root =
            SCNNode()

        let artwork =
            artworkNode()

        root.addChildNode(
            artwork
        )

        BookPreviewScene
            .applyBookSurfaceBrightnessFill(
                root:
                    root
            )

        BookPreviewScene
            .applyBookSurfaceBrightnessFill(
                root:
                    root
            )

        BookPreviewScene
            .applyBookSurfaceBrightnessFill(
                root:
                    root
            )

        let material =
            try! XCTUnwrap(
                artwork
                    .geometry?
                    .firstMaterial
            )

        XCTAssertEqual(
            material
                .emission
                .intensity,
            0.34,
            accuracy:
                0.0001,
            "Repeated live updates must not accumulate brightness."
        )
    }
}


final class LiveBookBrightnessV20RegressionTests:
    XCTestCase
{
    private func node(
        name:
            String
    ) -> SCNNode
    {
        let geometry =
            SCNPlane(
                width:
                    1,
                height:
                    1
            )

        let material =
            SCNMaterial()

        material
            .diffuse
            .contents =
            NSColor(
                calibratedRed:
                    0.35,
                green:
                    0.25,
                blue:
                    0.15,
                alpha:
                    1
            )

        geometry.materials = [
            material
        ]

        let result =
            SCNNode(
                geometry:
                    geometry
            )

        result.name =
            name

        return result
    }

    func testLiveCoverUsesStrongerFillThanExport()
    {
        let root =
            SCNNode()

        let cover =
            node(
                name:
                    "book-shell.front-cover-artwork"
            )

        root.addChildNode(
            cover
        )

        BookPreviewScene
            .applyBookSurfaceBrightnessFill(
                root:
                    root
            )

        let material =
            try! XCTUnwrap(
                cover
                    .geometry?
                    .firstMaterial
            )

        XCTAssertEqual(
            material
                .emission
                .intensity,
            0.34,
            accuracy:
                0.0001
        )

        BookPreviewScene
            .applyLiveBookBrightnessV20(
                root:
                    root
            )

        XCTAssertEqual(
            material
                .emission
                .intensity,
            0.85,
            accuracy:
                0.0001
        )
    }

    func testLivePrintedPageUsesStrongReadableFill()
    {
        let root =
            SCNNode()

        let page =
            node(
                name:
                    "book.left-active-page"
            )

        root.addChildNode(
            page
        )

        BookPreviewScene
            .applyLiveBookBrightnessV20(
                root:
                    root
            )

        let material =
            try! XCTUnwrap(
                page
                    .geometry?
                    .firstMaterial
            )

        XCTAssertEqual(
            material
                .emission
                .intensity,
            0.42,
            accuracy:
                0.0001
        )
    }

    func testLiveBrightnessIsIdempotent()
    {
        let root =
            SCNNode()

        let cover =
            node(
                name:
                    "book-shell.front-cover-artwork"
            )

        root.addChildNode(
            cover
        )

        for _ in 0..<5 {
            BookPreviewScene
                .applyLiveBookBrightnessV20(
                    root:
                        root
                )
        }

        let material =
            try! XCTUnwrap(
                cover
                    .geometry?
                    .firstMaterial
            )

        XCTAssertEqual(
            material
                .emission
                .intensity,
            0.85,
            accuracy:
                0.0001
        )
    }
}


final class RealLiveBookLightingV22RegressionTests:
    XCTestCase
{
    func testLiveLightingTargetsBookWithoutLightingGround()
    {
        let scene =
            SCNScene()

        let book =
            SCNNode()

        book.name =
            "physical-book.root"

        let page =
            SCNNode(
                geometry:
                    SCNPlane(
                        width:
                            1,
                        height:
                            1
                    )
            )

        page.name =
            "book.left-active-page"

        book.addChildNode(
            page
        )

        scene.rootNode.addChildNode(
            book
        )

        let ground =
            SCNNode(
                geometry:
                    SCNPlane(
                        width:
                            2,
                        height:
                            2
                    )
            )

        ground.name =
            "studio-ground"

        scene.rootNode.addChildNode(
            ground
        )

        let camera =
            SCNNode()

        camera.name =
            "preview-camera"

        camera.camera =
            SCNCamera()

        scene.rootNode.addChildNode(
            camera
        )

        BookPreviewScene
            .applyRealLiveBookLightingV22(
                to:
                    scene
            )

        let mask =
            1 << 20

        XCTAssertNotEqual(
            page.categoryBitMask
            & mask,
            0
        )

        XCTAssertEqual(
            ground.categoryBitMask
            & mask,
            0
        )

        let ambient =
            scene
            .rootNode
            .childNode(
                withName:
                    "studio-light.live-book-ambient-v22",
                recursively:
                    true
            )

        let overhead =
            scene
            .rootNode
            .childNode(
                withName:
                    "studio-light.live-book-overhead-v22",
                recursively:
                    true
            )

        let cameraFill =
            scene
            .rootNode
            .childNode(
                withName:
                    "studio-light.live-book-camera-fill-v22",
                recursively:
                    true
            )

        XCTAssertEqual(
            ambient?
                .light?
                .categoryBitMask,
            mask
        )

        XCTAssertEqual(
            overhead?
                .light?
                .categoryBitMask,
            mask
        )

        XCTAssertEqual(
            cameraFill?
                .light?
                .categoryBitMask,
            mask
        )

        let ambientIntensity =
            try! XCTUnwrap(
                ambient?
                    .light?
                    .intensity
            )

        let overheadIntensity =
            try! XCTUnwrap(
                overhead?
                    .light?
                    .intensity
            )

        let cameraFillIntensity =
            try! XCTUnwrap(
                cameraFill?
                    .light?
                    .intensity
            )

        XCTAssertEqual(
            ambientIntensity,
            CGFloat(60),
            accuracy:
                CGFloat(0.001)
        )

        XCTAssertEqual(
            overheadIntensity,
            CGFloat(180),
            accuracy:
                CGFloat(0.001)
        )

        XCTAssertEqual(
            cameraFillIntensity,
            CGFloat(240),
            accuracy:
                CGFloat(0.001)
        )
    }

    func testLiveLightingIsIdempotent()
    {
        let scene =
            SCNScene()

        let book =
            SCNNode()

        book.name =
            "physical-book.root"

        scene.rootNode.addChildNode(
            book
        )

        let camera =
            SCNNode()

        camera.name =
            "preview-camera"

        camera.camera =
            SCNCamera()

        scene.rootNode.addChildNode(
            camera
        )

        for _ in 0..<5 {
            BookPreviewScene
                .applyRealLiveBookLightingV22(
                    to:
                        scene
                )
        }

        var names:
            [String] = []

        scene.rootNode.enumerateChildNodes {
            node,
            _ in

            if let name =
                node.name,
               name.contains(
                    "live-book-"
               )
            {
                names.append(
                    name
                )
            }
        }

        XCTAssertEqual(
            names.filter {
                $0
                    == "studio-light.live-book-ambient-v22"
            }.count,
            1
        )

        XCTAssertEqual(
            names.filter {
                $0
                    == "studio-light.live-book-overhead-v22"
            }.count,
            1
        )

        XCTAssertEqual(
            names.filter {
                $0
                    == "studio-light.live-book-camera-fill-v22"
            }.count,
            1
        )
    }
}


final class KDPAuthoritativeSpineV24BRegressionTests:
    XCTestCase
{
    func testCaseLaminateFilenameParsesAuthoritativeKDPPrintSpecification()
    throws
    {
        let specification =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .importedKDPTemplateSpecification(
                        name:
                            "TRY Kindle CASE_LAMINATE_8.250x11.000_535_BW_WHITE_en_US"
                    )
            )

        XCTAssertEqual(
            specification
                .trimWidth,
            8.25,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            specification
                .trimHeight,
            11,
            accuracy:
                0.000_001
        )

        XCTAssertEqual(
            specification
                .pageCount,
            535
        )

        XCTAssertEqual(
            specification
                .caliper,
            0.002252,
            accuracy:
                0.000_000_001
        )

        XCTAssertEqual(
            specification
                .binding,
            .hardcover
        )
    }

    func test535PageWhitePaperBlockUsesExactKDPSpineMath()
    throws
    {
        let specification =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .importedKDPTemplateSpecification(
                        name:
                            "TRY Kindle CASE_LAMINATE_8.250x11.000_535_BW_WHITE_en_US"
                    )
            )

        let spine =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .expectedSpine(
                        pageCount:
                            specification
                                .pageCount,
                        caliper:
                            specification
                                .caliper
                    )
            )

        XCTAssertEqual(
            spine,
            1.204_820,
            accuracy:
                0.000_000_5
        )
    }

    func testKDPTemplateSpecificationWinsOverStale356PageMetadata()
    throws
    {
        var project =
            CoverProject(
                type:
                    .printFullWrap,
                width:
                    17.551_712,
                height:
                    11.25
            )

        project.name =
            "TRY Kindle CASE_LAMINATE_8.250x11.000_535_BW_WHITE_en_US"

        project.trimWidth =
            8.25

        project.backWidth =
            8.25

        project.trimHeight =
            11

        project.bleed =
            0.125

        project.spinePageCount =
            356

        project.spineCaliperInches =
            0.002252

        project.spineWidth =
            0.801_712

        let geometry =
            PhysicalBookGeometry(
                project:
                    project
            )

        XCTAssertEqual(
            geometry
                .spineWidth,
            1.204_820,
            accuracy:
                0.000_000_5
        )

        XCTAssertEqual(
            geometry
                .paperBlockDepth,
            1.204_820,
            accuracy:
                0.000_000_5
        )
    }

    func testCoverBoardsSitOutsideExactPaperBlock()
    {
        var project =
            CoverProject(
                type:
                    .printFullWrap,
                width:
                    17.954_82,
                height:
                    11.25
            )

        project.name =
            "TRY Kindle CASE_LAMINATE_8.250x11.000_535_BW_WHITE_en_US"

        project.trimWidth =
            8.25

        project.backWidth =
            8.25

        project.trimHeight =
            11

        project.bleed =
            0.125

        project.spinePageCount =
            535

        project.spineCaliperInches =
            0.002252

        project.spineWidth =
            1.204_820

        let geometry =
            PhysicalBookGeometry(
                project:
                    project
            )

        for binding in [
            BookBinding.softcover,
            .hardcover
        ] {
            XCTAssertEqual(
                geometry
                    .pageBlockDepth(
                        for:
                            binding
                    ),
                geometry
                    .paperBlockDepth,
                accuracy:
                    0.000_000_5
            )

            XCTAssertEqual(
                geometry
                    .outerBookDepth(
                        for:
                            binding
                    ),
                geometry
                    .paperBlockDepth
                + 2
                * geometry
                    .coverThickness(
                        for:
                            binding
                    ),
                accuracy:
                    0.000_000_5
            )

            XCTAssertGreaterThan(
                geometry
                    .outerBookDepth(
                        for:
                            binding
                    ),
                geometry
                    .paperBlockDepth
            )
        }
    }

    func testSynchronizerPreservesImportedKDPTemplatePageCount()
    throws
    {
        var project =
            CoverProject(
                type:
                    .printFullWrap,
                width:
                    17.551_712,
                height:
                    11.25
            )

        project.name =
            "TRY Kindle CASE_LAMINATE_8.250x11.000_535_BW_WHITE_en_US"

        project.trimWidth =
            8.25

        project.backWidth =
            8.25

        project.trimHeight =
            11

        project.bleed =
            0.125

        project.spinePageCount =
            356

        project.spineCaliperInches =
            0.002252

        project.spineWidth =
            0.801_712

        let repaired =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .synchronizedPrintCover(
                        project,
                        manuscriptPageCount:
                            356
                    )
            )

        XCTAssertEqual(
            repaired
                .spinePageCount,
            535
        )

        XCTAssertEqual(
            repaired
                .spineWidth,
            1.204_820,
            accuracy:
                0.000_000_5
        )
    }
}


final class TrueClosedBookV25RegressionTests:
    XCTestCase
{
    private func project() -> CoverProject
    {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.name =
            "CASE_LAMINATE_8.250x11.000_535_BW_WHITE_en_US"

        project.trimWidth =
            8.25

        project.backWidth =
            8.25

        project.trimHeight =
            11

        project.spinePageCount =
            535

        project.spineCaliperInches =
            0.002252

        project.spineWidth =
            1.204820

        project.bleed =
            0.125

        return project
    }

    private func scene(
        open:
            Bool,
        angle:
            Double
    ) -> SCNScene {
        BookPreviewScene.make(
            project:
                project(),
            workingLayers:
                false,
            open:
                open,
            angle:
                angle,
            leftPage:
                100,
            rightPage:
                101,
            pageCount:
                535,
            spreadIndex:
                50,
            leftTexture:
                nil,
            rightTexture:
                nil,
            margins:
                false,
            thumbMode:
                .off,
            leftPageSettings:
                PageSettings(),
            rightPageSettings:
                PageSettings(),
            preset:
                .perspective,
            revisionID:
                UUID(
                    uuidString:
                        "00000000-0000-0000-0000-000000002525"
                )!,
            binding:
                .hardcover
        )
    }

    private func node(
        _ name:
            String,
        in scene:
            SCNScene
    ) throws -> SCNNode {
        try XCTUnwrap(
            scene
                .rootNode
                .childNode(
                    withName:
                        name,
                    recursively:
                        true
                )
        )
    }

    private func assertSameTransform(
        _ lhs:
            SCNNode,
        _ rhs:
            SCNNode,
        file:
            StaticString = #filePath,
        line:
            UInt = #line
    ) {
        XCTAssertEqual(
            lhs.position.x,
            rhs.position.x,
            accuracy:
                0.000001,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            lhs.position.y,
            rhs.position.y,
            accuracy:
                0.000001,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            lhs.position.z,
            rhs.position.z,
            accuracy:
                0.000001,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            lhs.eulerAngles.x,
            rhs.eulerAngles.x,
            accuracy:
                0.000001,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            lhs.eulerAngles.y,
            rhs.eulerAngles.y,
            accuracy:
                0.000001,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            lhs.eulerAngles.z,
            rhs.eulerAngles.z,
            accuracy:
                0.000001,
            file:
                file,
            line:
                line
        )
    }

    func testClosedBookIgnoresStaleOpenAngle()
    throws
    {
        let zero =
            scene(
                open:
                    false,
                angle:
                    0
            )

        let fifteen =
            scene(
                open:
                    false,
                angle:
                    15
            )

        let oneSixty =
            scene(
                open:
                    false,
                angle:
                    160
            )

        let oneEighty =
            scene(
                open:
                    false,
                angle:
                    180
            )

        let referenceFront =
            try node(
                "book-shell.front-cover",
                in:
                    zero
            )

        let referenceRoot =
            try node(
                "physical-book.root",
                in:
                    zero
            )

        let referenceBounds =
            referenceRoot.boundingBox

        XCTAssertGreaterThan(
            referenceBounds.max.x
                - referenceBounds.min.x,
            0
        )

        XCTAssertGreaterThan(
            referenceBounds.max.y
                - referenceBounds.min.y,
            0
        )

        XCTAssertGreaterThan(
            referenceBounds.max.z
                - referenceBounds.min.z,
            0
        )

        for candidate in [
            fifteen,
            oneSixty,
            oneEighty
        ] {
            let candidateFront =
                try node(
                    "book-shell.front-cover",
                    in:
                        candidate
                )

            assertSameTransform(
                referenceFront,
                candidateFront
            )

            let candidateRoot =
                try node(
                    "physical-book.root",
                    in:
                        candidate
                )

            let candidateBounds =
                candidateRoot.boundingBox

            XCTAssertEqual(
                referenceBounds.min.x,
                candidateBounds.min.x,
                accuracy:
                    0.000001
            )

            XCTAssertEqual(
                referenceBounds.min.y,
                candidateBounds.min.y,
                accuracy:
                    0.000001
            )

            XCTAssertEqual(
                referenceBounds.min.z,
                candidateBounds.min.z,
                accuracy:
                    0.000001
            )

            XCTAssertEqual(
                referenceBounds.max.x,
                candidateBounds.max.x,
                accuracy:
                    0.000001
            )

            XCTAssertEqual(
                referenceBounds.max.y,
                candidateBounds.max.y,
                accuracy:
                    0.000001
            )

            XCTAssertEqual(
                referenceBounds.max.z,
                candidateBounds.max.z,
                accuracy:
                    0.000001
            )
        }
    }

    func testActuallyOpenBookStillRespondsToAngle()
    throws
    {
        let closed =
            scene(
                open:
                    false,
                angle:
                    160
            )

        let opened =
            scene(
                open:
                    true,
                angle:
                    160
            )

        let closedFront =
            try node(
                "book-shell.front-cover",
                in:
                    closed
            )

        let openedFront =
            try node(
                "book-shell.front-cover",
                in:
                    opened
            )

        XCTAssertNotEqual(
            closedFront
                .eulerAngles
                .y,
            openedFront
                .eulerAngles
                .y,
            accuracy:
                0.000001
        )
    }

    func test535PageKDPGeometryRemainsAuthoritative()
    {
        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        XCTAssertEqual(
            geometry
                .pageBlockDepth(
                    for:
                        .hardcover
                ),
            1.204820,
            accuracy:
                0.000001
        )

        XCTAssertGreaterThan(
            geometry
                .outerBookDepth(
                    for:
                        .hardcover
                ),
            geometry
                .pageBlockDepth(
                    for:
                        .hardcover
                )
        )
    }
}


final class ExactKDPHardcoverCaseV27BRegressionTests:
    XCTestCase
{
    private func project()
        -> CoverProject
    {
        var result =
            CoverProject(
                type:
                    .printFullWrap
            )

        result.trimWidth = 8.25
        result.backWidth = 8.25
        result.trimHeight = 11
        result.spinePageCount = 535
        result.spineCaliperInches = 0.002252
        result.spineWidth =
            Double(535)
            * 0.002252
        result.bleed = 0.125

        return result
    }

    func testExactKDPCaseDimensions()
        throws
    {
        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        XCTAssertEqual(
            geometry.pageBlockDepth(
                for:
                    .hardcover
            ),
            1.204820,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            geometry.coverThickness(
                for:
                    .hardcover
            ),
            2.4 / 25.4,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            geometry.coverHorizontalOverhang(
                for:
                    .hardcover
            ),
            2.5 / 25.4,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            geometry.coverVerticalOverhang(
                for:
                    .hardcover
            ),
            3.0 / 25.4,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            geometry.hardcoverHingeChannelWidth(
                for:
                    .hardcover
            ),
            10.0 / 25.4,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            geometry.closedBook.depth,
            1.204820
                + 4.8 / 25.4,
            accuracy:
                0.000001
        )
    }

    func testClosedHardcoverSpineInnerFaceStopsAtHingePlane()
        throws
    {
        let scene =
            BookPreviewScene.make(
                project:
                    project(),
                workingLayers:
                    false,
                open:
                    false,
                angle:
                    0,
                leftPage:
                    1,
                rightPage:
                    2,
                pageCount:
                    535,
                spreadIndex:
                    0,
                leftTexture:
                    nil,
                rightTexture:
                    nil,
                margins:
                    false,
                thumbMode:
                    .off,
                leftPageSettings:
                    PageSettings(),
                rightPageSettings:
                    PageSettings(),
                preset:
                    .front,
                revisionID:
                    UUID(
                        uuidString:
                            "00000000-0000-0000-0000-000000002727"
                    )!,
                binding:
                    .hardcover
            )

        let root =
            try XCTUnwrap(
                scene.rootNode
                    .childNode(
                        withName:
                            "physical-book.root",
                        recursively:
                            false
                    )
            )

        let spine =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book-shell.spine",
                    recursively:
                        true
                )
            )

        let box =
            try XCTUnwrap(
                spine.geometry
                    as? SCNBox
            )

        let innerFaceX =
            spine.position.x
            + CGFloat(
                box.width / 2
            )

        XCTAssertEqual(
            innerFaceX,
            0,
            accuracy:
                0.002
        )

        XCTAssertLessThan(
            spine.position.x,
            0
        )

        XCTAssertNotNil(
            root.childNode(
                withName:
                    "book-shell.front-hinge-channel",
                recursively:
                    true
            )
        )

        XCTAssertNotNil(
            root.childNode(
                withName:
                    "book-shell.back-hinge-channel",
                recursively:
                    true
            )
        )
    }

    func testSoftcoverDoesNotReceiveCaseLaminateGrowth()
        throws
    {
        let geometry =
            PhysicalBookGeometry(
                project:
                    project()
            )

        XCTAssertEqual(
            geometry.coverHorizontalOverhang(
                for:
                    .softcover
            ),
            0,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            geometry.coverVerticalOverhang(
                for:
                    .softcover
            ),
            0,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            geometry.hardcoverHingeChannelWidth(
                for:
                    .softcover
            ),
            0,
            accuracy:
                0.000001
        )
    }
}

final class BookStudioSceneStyleInvalidationTests: XCTestCase {
    func testCameraOnlyChangesDoNotInvalidateSceneMaterials() {
        let original = BookStudioPresentation()
        var cameraChange = original
        cameraChange.cameraFieldOfView += 1
        cameraChange.savedCamera = BookSavedCamera(
            yaw: 0.2, pitch: 0.3, distance: 4, targetX: 0, targetY: 0, targetZ: 0
        )

        XCTAssertFalse(BookStudioSceneStyling.needsReapplication(from: original, to: cameraChange))
    }

    func testSurfaceStyleChangesInvalidateSceneMaterials() {
        let original = BookStudioPresentation()
        var changed = original
        changed.environmentIntensity += 0.1

        XCTAssertTrue(BookStudioSceneStyling.needsReapplication(from: original, to: changed))
    }

    func testNewSceneAlwaysReceivesInitialStyling() {
        XCTAssertTrue(BookStudioSceneStyling.needsReapplication(from: nil, to: BookStudioPresentation()))
    }
}
