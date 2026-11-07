import XCTest
@testable import BOLDWriter

final class CoverUndoRedoTests:XCTestCase {
    func testTransformTransactionCommitAndCancelUseExactOriginalLayers() throws {
        var a=CoverLayer(kind:.image,name:"a",frame:CoverRect(x:0.1,y:0.2,width:0.3,height:0.4));a.rotation=15
        let b=CoverLayer(kind:.text,name:"b",frame:CoverRect(x:0.6,y:0.3,width:0.2,height:0.1))
        let originals=[a,b];let ids=Set(originals.map{$0.id});var transaction=CoverTransformTransaction(layers:originals,ids:ids)
        transaction.update(layerID:a.id){$0.frame.x=0.8;$0.rotation=90};transaction.update(layerID:b.id){$0.frame.y=0.9}
        XCTAssertNotEqual(transaction.committedLayers()[a.id],a)
        XCTAssertEqual(transaction.cancelledLayers()[a.id],a)
        XCTAssertEqual(transaction.cancelledLayers()[b.id],b)
        XCTAssertEqual(transaction.committedLayers()[a.id]?.rotation,90)
    }

    func testBackwardCompatibleProjectPayloadsWithoutPhaseThreeFieldsDecode() throws {
        let project=CoverProject(type:.printFullWrap,width:12.7,height:9.25)
        let data=try JSONEncoder().encode(project);var object=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        for key in ["snapGuides","snapGrid","snapBounds","snapLayers","gridSubdivisions","pixelGridVisible","userGuidesX","userGuidesY"]{object.removeValue(forKey:key)}
        XCTAssertNoThrow(try JSONDecoder().decode(CoverProject.self,from:JSONSerialization.data(withJSONObject:object)))
    }
}
