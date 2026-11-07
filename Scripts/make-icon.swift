import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: make-icon.swift output.png\n", stderr)
    exit(2)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()
let tile = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 218, yRadius: 218)
let gradient = NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.34, blue: 0.85, alpha: 1), ending: NSColor(calibratedRed: 0.49, green: 0.17, blue: 0.75, alpha: 1))!
gradient.draw(in: tile, angle: -45)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
shadow.shadowBlurRadius = 22
shadow.shadowOffset = NSSize(width: 0, height: -14)
NSGraphicsContext.saveGraphicsState()
shadow.set()
let paper = NSBezierPath(roundedRect: NSRect(x: 270, y: 188, width: 490, height: 650), xRadius: 24, yRadius: 24)
NSColor.white.setFill()
paper.fill()
NSGraphicsContext.restoreGraphicsState()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 420, weight: .heavy),
    .foregroundColor: NSColor(calibratedRed: 0.29, green: 0.23, blue: 0.65, alpha: 1),
    .paragraphStyle: paragraph
]
("B" as NSString).draw(in: NSRect(x: 268, y: 236, width: 490, height: 530), withAttributes: attributes)
let line = NSBezierPath()
line.move(to: NSPoint(x: 362, y: 254))
line.line(to: NSPoint(x: 666, y: 254))
line.lineWidth = 12
line.lineCapStyle = .round
NSColor(calibratedRed: 0.75, green: 0.74, blue: 0.90, alpha: 1).setStroke()
line.stroke()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let png = representation.representation(using: .png, properties: [:]) else { exit(2) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
