import AppKit
import PDFKit
import Foundation

func fail(_ message: String) -> Never { fputs("error: \(message)\n", stderr); exit(2) }
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 3, let first = Int(args[1]), let last = Int(args[2]), first >= 1, last >= first else {
    fail("usage: render-pdf-pages.swift INPUT.pdf FIRST_PAGE LAST_PAGE")
}
let input = URL(fileURLWithPath: args[0])
guard let pdf = PDFDocument(url: input) else { fail("could not open PDF: \(input.path)") }
guard last <= pdf.pageCount else { fail("requested page \(last), PDF has \(pdf.pageCount)") }
let output = input.deletingLastPathComponent()
for number in first...last {
    guard let page = pdf.page(at: number - 1) else { fail("missing page \(number)") }
    let bounds = page.bounds(for: .mediaBox)
    let scale: CGFloat = 2
    let pixelsWide = max(1, Int(ceil(bounds.width * scale)))
    let pixelsHigh = max(1, Int(ceil(bounds.height * scale)))
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                        bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fail("could not allocate page bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setFillColor(NSColor.white.cgColor)
    context.cgContext.fill(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
    context.cgContext.scaleBy(x: scale, y: scale)
    context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
    page.draw(with: .mediaBox, to: context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fail("PNG encode failed") }
    let destination = output.appendingPathComponent(String(format: "pdf-page-%04d.png", number))
    do { try data.write(to: destination, options: .atomic) }
    catch { fail("could not write \(destination.path): \(error)") }
    print("\(number)\t\(Int(bounds.width))x\(Int(bounds.height)) pt\t\(destination.path)")
}
print("PDF pages: \(pdf.pageCount)")
