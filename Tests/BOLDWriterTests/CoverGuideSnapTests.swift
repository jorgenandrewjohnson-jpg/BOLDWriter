import XCTest
@testable import BOLDWriter

final class CoverGuideSnapTests: XCTestCase {
    func testSnapUsesDocumentGuidesConvertedThroughDisplayedScale() {
        var project=CoverProject(width:10,height:8);project.userGuidesX=[1.0];project.userGuidesY=[2.0]
        let input=CoverRect(x:0.105,y:0.247,width:0.2,height:0.2)
        let result=CoverEditorEngine.snap(input,layerID:nil,project:project,displayedCanvas:CGSize(width:1000,height:800),thresholdPoints:8)
        XCTAssertEqual(result.frame.x,0.1,accuracy:0.00001)
        XCTAssertEqual(result.frame.y,0.25,accuracy:0.00001)
        XCTAssertFalse(result.indicators.isEmpty)
    }

    func testGridSnapUsesPhysicalSpacingAndCanBeDisabled() {
        var project=CoverProject(width:10,height:8);project.gridVisible=true;project.gridSpacingInches=2.5
        let input=CoverRect(x:0.247,y:0.25,width:0.1,height:0.1)
        let snapped=CoverEditorEngine.snap(input,layerID:nil,project:project,displayedCanvas:CGSize(width:1000,height:800),thresholdPoints:5)
        XCTAssertEqual(snapped.frame.x,0.25,accuracy:0.00001)
        project.snapEnabled=false
        XCTAssertEqual(CoverEditorEngine.snap(input,layerID:nil,project:project,displayedCanvas:CGSize(width:1000,height:800)).frame,input)
    }

    func testGuideAndGridSettingsSurviveCoverProjectEncoding() throws {
        var p=CoverProject();p.userGuidesX=[1.25,3.5];p.userGuidesY=[2];p.gridVisible=true;p.gridSpacingInches=0.25;p.gridSubdivisions=4;p.pixelGridVisible=true;p.unit="mm"
        let reopened=try JSONDecoder().decode(CoverProject.self,from:JSONEncoder().encode(p))
        XCTAssertEqual(reopened.userGuidesX,p.userGuidesX);XCTAssertEqual(reopened.gridSpacingInches,0.25);XCTAssertEqual(reopened.pixelGridVisible,true);XCTAssertEqual(reopened.unit,"mm")
    }

    func testSnapCategoriesCanBeIndependentlyDisabled() {
        var p=CoverProject(width:10,height:8);p.userGuidesX=[5];p.gridSpacingInches=2;p.snapGuides=false;p.snapGrid=false;p.snapBounds=false;p.snapLayers=false
        let frame=CoverRect(x:0.49,y:0.49,width:0.1,height:0.1)
        XCTAssertEqual(CoverEditorEngine.snap(frame,layerID:nil,project:p,displayedCanvas:CGSize(width:1000,height:800)).frame,frame)
    }

    func testRotatedLayerSnapsToVisibleEdgeOnNonSquareCanvas() {
        var project = CoverProject(width: 10, height: 8)
        project.snapBounds = false
        project.snapGuides = false
        project.snapGrid = false
        project.snapLayerCenters = false
        project.snapLayerEdges = true
        var target = CoverLayer(kind: .shape, name: "rotated", frame: CoverRect(x: 0.5, y: 0.2, width: 0.2, height: 0.1))
        target.rotation = 90
        let moving = CoverRect(x: 0.456, y: 0.7, width: 0.1, height: 0.1)
        let result = CoverEditorEngine.snap(moving, layerID: nil, project: project,
                                            displayedCanvas: CGSize(width: 1000, height: 800),
                                            thresholdPoints: 8, otherLayers: [target])
        XCTAssertEqual(result.frame.x, 0.46, accuracy: 0.00001)
        XCTAssertEqual(result.frame.y, moving.y, accuracy: 0.00001)
    }

    func testMovingRotatedLayerSnapsItsVisibleEdgeToGuide() {
        var project = CoverProject(width: 10, height: 8)
        project.snapBounds = false
        project.snapGrid = false
        project.snapLayers = false
        project.userGuidesX = [3.65]
        let moving = CoverRect(x: 0.3, y: 0.2, width: 0.2, height: 0.1)
        let result = CoverEditorEngine.snap(moving, layerID: nil, project: project,
                                            displayedCanvas: CGSize(width: 1000, height: 800),
                                            thresholdPoints: 8, rotationDegrees: 90)
        XCTAssertEqual(result.frame.x, 0.305, accuracy: 0.00001)
        XCTAssertEqual(result.frame.y, moving.y, accuracy: 0.00001)
        XCTAssertEqual(result.indicators.first?.x ?? -1, 0.365, accuracy: 0.00001)
    }
}
