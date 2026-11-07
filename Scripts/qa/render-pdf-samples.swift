import AppKit
import PDFKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: render-pdf-samples.swift input.pdf output-directory\n", stderr)
    exit(2)
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let document = PDFDocument(url: input), document.pageCount > 0 else {
    fputs("could not open PDF or PDF has no pages\n", stderr)
    exit(1)
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let indexes = Array(Set([0, document.pageCount / 2, document.pageCount - 1])).sorted()
for index in indexes {
    guard let page = document.page(at: index) else { continue }
    let bounds = page.bounds(for: .mediaBox)
    let thumbnail = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
    guard let tiff = thumbnail.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("failed to rasterize page \(index + 1)\n", stderr)
        exit(1)
    }
    let destination = output.appendingPathComponent(String(format: "page-%04d.png", index + 1))
    try png.write(to: destination, options: .atomic)
    print("page=\(index + 1) mediaBox=\(bounds) raster=\(destination.path)")
}
