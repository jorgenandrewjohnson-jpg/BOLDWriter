import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import BOLDWriter

@MainActor final class CoverSourceImageCacheTests: XCTestCase {
    private func imageData(_ color: NSColor) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:32,pixelsHigh:24,
            bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
        let rgba=try XCTUnwrap(color.usingColorSpace(.deviceRGB))
        let pixels=try XCTUnwrap(bitmap.bitmapData)
        for y in 0..<24 { for x in 0..<32 {
            let offset=y*bitmap.bytesPerRow+x*4
            pixels[offset]=UInt8((rgba.redComponent*255).rounded())
            pixels[offset+1]=UInt8((rgba.greenComponent*255).rounded())
            pixels[offset+2]=UInt8((rgba.blueComponent*255).rounded())
            pixels[offset+3]=255
        } }
        return try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
    }

    func testRepeatedSourceAccessReusesFullResolutionImageAndChangedPixelsInvalidate() throws {
        let red=try imageData(.red), blue=try imageData(.blue)
        let first=try XCTUnwrap(CoverArtwork.sourceImage(data:red))
        XCTAssertTrue(first === CoverArtwork.sourceImage(data:Data(red)))
        let changed=try XCTUnwrap(CoverArtwork.sourceImage(data:blue))
        XCTAssertFalse(first === changed)
        XCTAssertTrue(first === CoverArtwork.sourceImage(data:red),"Undo must recover the original source")
        let bitmap=try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(first.tiffRepresentation)))
        XCTAssertEqual(bitmap.pixelsWide,32); XCTAssertEqual(bitmap.pixelsHigh,24)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x:16,y:12)?.usingColorSpace(.deviceRGB)).redComponent,0.9)
        let replacement=try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(changed.tiffRepresentation)))
        XCTAssertGreaterThan(try XCTUnwrap(replacement.colorAt(x:16,y:12)?.usingColorSpace(.deviceRGB)).blueComponent,0.9)
    }

    func testInvalidSourceDoesNotPoisonSubsequentValidRendering() throws {
        XCTAssertNil(CoverArtwork.sourceImage(data:Data("not an image".utf8)))
        let valid=try XCTUnwrap(CoverArtwork.sourceImage(data:imageData(.green)))
        XCTAssertGreaterThan(valid.size.width,0)
        XCTAssertGreaterThan(valid.size.height,0)
    }

    func testSourceImageCanBeDrawnAfterTemporaryEncodedDataIsReleased() throws {
        func makeImage() throws -> NSImage {
            let encoded = try imageData(.systemTeal)
            return try XCTUnwrap(CoverArtwork.sourceImage(data:encoded))
        }

        let image = try makeImage()
        for _ in 0..<20 {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:160,pixelsHigh:120,
                bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
            image.draw(in:NSRect(x:0,y:0,width:160,height:120),from:.zero,operation:.copy,fraction:1)
            NSGraphicsContext.restoreGraphicsState()
            XCTAssertNotNil(bitmap.colorAt(x:80,y:60))
        }
    }

    func testCachedSourceKeepsAppKitColorAndOrientationRendering() throws {
        let encoded = try imageData(.systemTeal)
        let expected = try XCTUnwrap(NSImage(data:encoded))
        let cached = try XCTUnwrap(CoverArtwork.sourceImage(data:encoded))
        func rendered(_ image: NSImage) throws -> Data {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:128,pixelsHigh:96,
                bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
            image.draw(in:NSRect(x:0,y:0,width:128,height:96),from:.zero,operation:.copy,fraction:1)
            NSGraphicsContext.restoreGraphicsState()
            return Data(bytes:try XCTUnwrap(bitmap.bitmapData),count:bitmap.bytesPerRow*bitmap.pixelsHigh)
        }
        XCTAssertEqual(try rendered(cached),try rendered(expected))
    }

    func testMaterializedSourcePreservesExifOrientation() throws {
        let sourceBitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:64,pixelsHigh:32,
            bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
        let pixels = try XCTUnwrap(sourceBitmap.bitmapData)
        for y in 0..<32 { for x in 0..<64 {
            let offset = y * sourceBitmap.bytesPerRow + x * 4
            let left = x < 32
            pixels[offset] = left ? 255 : 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = left ? 0 : 255
            pixels[offset + 3] = 255
        } }
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            encoded, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(sourceBitmap.cgImage),
                                   [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let expected = try XCTUnwrap(NSImage(data:encoded as Data))
        let cached = try XCTUnwrap(CoverArtwork.sourceImage(data:encoded as Data))
        func rendered(_ image: NSImage) throws -> Data {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:96,pixelsHigh:96,
                bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
            let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep:bitmap))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            image.draw(in:NSRect(x:0,y:0,width:96,height:96),from:NSRect(origin:.zero,size:image.size),operation:.copy,fraction:1)
            NSGraphicsContext.restoreGraphicsState()
            return Data(bytes:try XCTUnwrap(bitmap.bitmapData),count:bitmap.bytesPerRow*bitmap.pixelsHigh)
        }
        XCTAssertEqual(try rendered(cached),try rendered(expected))
        XCTAssertLessThan(cached.size.width, cached.size.height,
                          "EXIF orientation should be applied while materializing the source raster")
    }

    func testReturnedSourceRemainsDrawableAfterCacheEviction() throws {
        let originalData = try imageData(.systemTeal)
        let original = try XCTUnwrap(CoverArtwork.sourceImage(data:originalData))
        for index in 0..<12 {
            let color = NSColor(calibratedRed:CGFloat(index) / 12, green:0.3, blue:0.7, alpha:1)
            _ = try CoverArtwork.sourceImage(data:imageData(color))
        }
        XCTAssertFalse(original === CoverArtwork.sourceImage(data:originalData),
                       "The bounded source cache should have evicted the oldest image")
        for _ in 0..<20 {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:160,pixelsHigh:120,
                bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
            original.draw(in:NSRect(x:0,y:0,width:160,height:120),from:.zero,operation:.copy,fraction:1)
            NSGraphicsContext.restoreGraphicsState()
            XCTAssertNotNil(bitmap.colorAt(x:80,y:60))
        }
    }
}
