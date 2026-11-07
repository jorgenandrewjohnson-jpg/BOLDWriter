import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import BOLDWriter

@MainActor
final class LocalFileDropTests: XCTestCase {
    private func provider(_ url: URL?, delay: Double = 0) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier,
                                            visibility: .all) { completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                if let url { completion(url.absoluteString.data(using: .utf8), nil) }
                else { completion(nil, NSError(domain: "DropFixture", code: 17)) }
            }
            return nil
        }
        return provider
    }

    func testEveryFileResolvesInDragOrderOnMainQueueDespiteDelayedFirstProvider() {
        let urls = ["first photo.jpg", "second.pdf", "third.png"].map {
            URL(fileURLWithPath: "/tmp/" + $0)
        }
        let done = expectation(description: "All three dropped files")
        XCTAssertTrue(LocalFileDrop.load([provider(urls[0], delay: 0.05), provider(urls[1]), provider(urls[2])]) { results in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(results.compactMap { try? $0.get() }, urls)
            XCTAssertEqual(results.count, 3)
            done.fulfill()
        })
        wait(for: [done], timeout: 5)
    }

    func testFailedProviderIsReportedWithoutDiscardingFollowingFiles() {
        let url = URL(fileURLWithPath: "/tmp/next artwork.png")
        let done = expectation(description: "Failure and remaining file")
        XCTAssertTrue(LocalFileDrop.load([provider(nil), provider(url)]) { results in
            XCTAssertEqual(results.count, 2)
            if results.count == 2 {
                if case .success = results[0] { XCTFail("Provider error was lost") }
                XCTAssertEqual(try? results[1].get(), url)
            }
            done.fulfill()
        })
        wait(for: [done], timeout: 5)
    }

    func testEmptyOrNonFileDropIsNotClaimed() {
        let plain = NSItemProvider(item: "text" as NSString, typeIdentifier: UTType.plainText.identifier)
        for providers in [[], [plain]] {
            XCTAssertFalse(LocalFileDrop.load(providers) { _ in XCTFail("No file provider was accepted") })
        }
    }

    func testURLAndDataRepresentationsPreserveUnicodeAndRejectNonFiles() throws {
        let url = URL(fileURLWithPath: "/tmp/Cover proof — café #1.png")
        XCTAssertEqual(try LocalFileDrop.decode(url as NSURL), url)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.writeObjects([url as NSURL]))
        let payload = try XCTUnwrap(pasteboard.data(forType: .fileURL))
        XCTAssertEqual(try LocalFileDrop.decode(payload as NSData), url)
        XCTAssertThrowsError(try LocalFileDrop.decode(nil))
        XCTAssertThrowsError(try LocalFileDrop.decode("not a URL item" as NSString))
        XCTAssertThrowsError(try LocalFileDrop.decode(URL(string: "https://example.invalid/art.png")! as NSURL))
    }
}
