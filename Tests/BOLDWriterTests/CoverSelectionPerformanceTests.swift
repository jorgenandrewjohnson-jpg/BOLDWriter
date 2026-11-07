import XCTest
@testable import BOLDWriter

final class CoverSelectionPerformanceTests: XCTestCase {
    private func reference(_ mask: Data, width: Int, height: Int, radius: Int, operation: Int) -> Data {
        let source = [UInt8](mask)
        var output = source
        for y in 0..<height { for x in 0..<width {
            var sum = 0, count = 0, extreme: UInt8 = operation == 1 ? 0 : 255
            for yy in max(0, y-radius)...min(height-1, y+radius) {
                for xx in max(0, x-radius)...min(width-1, x+radius) {
                    let value = source[yy*width+xx]
                    sum += Int(value); count += 1
                    extreme = operation == 1 ? max(extreme,value) : min(extreme,value)
                }
            }
            output[y*width+x] = operation == 0 ? UInt8(sum/count) : extreme
        } }
        return Data(output)
    }

    func testEveryByteMatchesClippedReferenceForFractionalCoverage() {
        for (width,height) in [(1,1),(1,13),(17,1),(7,11),(23,16)] {
            let bytes: [UInt8] = (0..<(width * height)).map { index in
                let value = index * 73 + (index / 3) * 19
                return UInt8(value % 256)
            }
            let source = Data(bytes)
            for radius in [1,2,5,24] {
                XCTAssertEqual(CoverEditorEngine.feather(source,width:width,height:height,radius:radius),
                               reference(source,width:width,height:height,radius:radius,operation:0))
                XCTAssertEqual(CoverEditorEngine.expandSelection(source,width:width,height:height,radius:radius),
                               reference(source,width:width,height:height,radius:radius,operation:1))
                XCTAssertEqual(CoverEditorEngine.contractSelection(source,width:width,height:height,radius:radius),
                               reference(source,width:width,height:height,radius:radius,operation:2))
            }
        }
    }

    func testExpansionAndContractionHonorRequestedRadiusAbove64() {
        var point = Data(repeating:0,count:201); point[100] = 255
        let expanded = CoverEditorEngine.expandSelection(point,width:201,height:1,radius:80)
        XCTAssertEqual(expanded.filter { $0 == 255 }.count,161)
        XCTAssertEqual(expanded[19],0); XCTAssertEqual(expanded[20],255)
        let contracted = CoverEditorEngine.contractSelection(Data(point.map { 255-$0 }),width:201,height:1,radius:80)
        XCTAssertEqual(contracted,Data(expanded.map { 255-$0 }))
    }

    func testInvalidDimensionsAndZeroRadiusLeaveSelectionUnchanged() {
        let source = Data([0,64,128,255])
        for (width,height,radius) in [(2,2,0),(-1,4,2),(Int.max,2,2),(2,3,1)] {
            XCTAssertEqual(CoverEditorEngine.feather(source,width:width,height:height,radius:radius),source)
            XCTAssertEqual(CoverEditorEngine.expandSelection(source,width:width,height:height,radius:radius),source)
            XCTAssertEqual(CoverEditorEngine.contractSelection(source,width:width,height:height,radius:radius),source)
        }
        XCTAssertEqual(CoverEditorEngine.expandSelection(source,width:2,height:2,radius:Int.max),Data(repeating:255,count:4))
    }

    func testMeasuredReferenceAndFullCoverProcessing() {
        let width = 160, height = 120, radius = 20
        let source = Data((0..<width*height).map { UInt8(($0*73)%256) })
        let start = Date()
        let expected = reference(source,width:width,height:height,radius:radius,operation:0)
        let referenceSeconds = Date().timeIntervalSince(start)
        let optimizedStart = Date()
        let actual = CoverEditorEngine.feather(source,width:width,height:height,radius:radius)
        let optimizedSeconds = Date().timeIntervalSince(optimizedStart)
        XCTAssertEqual(actual,expected)
        let cover = Data(repeating:128,count:2804*1788)
        let fullStart = Date()
        let feather = CoverEditorEngine.feather(cover,width:2804,height:1788,radius:100)
        let expanded = CoverEditorEngine.expandSelection(cover,width:2804,height:1788,radius:100)
        let contracted = CoverEditorEngine.contractSelection(cover,width:2804,height:1788,radius:100)
        XCTAssertEqual(feather,cover); XCTAssertEqual(expanded,cover); XCTAssertEqual(contracted,cover)
        print("COVER_BENCHMARK reference=\(referenceSeconds)s optimized=\(optimizedSeconds)s speedup=\(referenceSeconds/max(0.000001,optimizedSeconds))x fullCoverThreeOperations=\(Date().timeIntervalSince(fullStart))s dimensions=2804x1788 radius=100")
    }
}
