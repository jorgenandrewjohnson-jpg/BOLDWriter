import Foundation
import CoreGraphics
import CoreText
import PDFKit

/// Vector PDF print-layout proof. Visible guides MUST be removed before printing.
enum BOLDPrintCoverProofPDF {
    enum ProofError: Error, CustomStringConvertible {
        case invalidInset
        case destinationExists
        case creationFailed
        case verificationFailed

        var description: String {
            switch self {
            case .invalidInset:
                return "Safe inset must fit within the page trim"
            case .destinationExists:
                return "Destination already exists"
            case .creationFailed:
                return "PDF rendering failed"
            case .verificationFailed:
                return "Generated PDF failed page-geometry verification"
            }
        }
    }

    static func create(
        geometry: BOLDPrintCoverGeometry.Result,
        safeInsetInches: Double = 0.25,
        at destination: URL
    ) throws {
        guard safeInsetInches.isFinite,
              safeInsetInches >= 0,
              safeInsetInches * 2 < geometry.trimWidthInches,
              safeInsetInches * 2 < geometry.trimHeightInches else {
            throw ProofError.invalidInset
        }

        let fm = FileManager.default
        let target = destination.standardizedFileURL

        guard !fm.fileExists(atPath: target.path) else {
            throw ProofError.destinationExists
        }

        let parent = target.deletingLastPathComponent()

        guard fm.fileExists(atPath: parent.path) else {
            throw ProofError.creationFailed
        }

        let temporary = parent.appendingPathComponent(
            ".bold-cover-proof-\(UUID().uuidString).pdf"
        )

        defer {
            try? fm.removeItem(at: temporary)
        }

        let width = geometry.totalCoverWidthInches * 72
        let height = geometry.totalCoverHeightInches * 72

        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: height
        )

        guard let context = CGContext(
            temporary as CFURL,
            mediaBox: &mediaBox,
            nil
        ) else {
            throw ProofError.creationFailed
        }

        // Keep the full wrap visible while giving print workflows
        // explicit finishing coordinates. Quartz requires CGRects encoded
        // as byte-backed CFData values, not as boxed CGRect objects.
        let outsideBleed = CGFloat(geometry.bleedInches * 72)
        var trimBox = mediaBox.insetBy(dx: outsideBleed, dy: outsideBleed)
        var bleedBox = mediaBox
        let pageBoxInfo: [String: NSData] = [
            kCGPDFContextTrimBox as String: NSData(
                bytes: &trimBox,
                length: MemoryLayout<CGRect>.size
            ),
            kCGPDFContextBleedBox as String: NSData(
                bytes: &bleedBox,
                length: MemoryLayout<CGRect>.size
            )
        ]
        context.beginPDFPage(pageBoxInfo as CFDictionary)

        context.setFillColor(
            CGColor(gray: 1, alpha: 1)
        )

        context.fill(mediaBox)

        func outline(
            _ rect: CGRect,
            color: CGColor,
            dash: [CGFloat] = []
        ) {
            context.saveGState()
            context.setStrokeColor(color)
            context.setLineWidth(0.75)
            context.setLineDash(
                phase: 0,
                lengths: dash
            )
            context.stroke(rect)
            context.restoreGState()
        }

        func rect(
            _ panel: BOLDPrintCoverGeometry.Panel
        ) -> CGRect {
            CGRect(
                x: panel.xInches * 72,
                y: panel.yInches * 72,
                width: panel.widthInches * 72,
                height: panel.heightInches * 72
            )
        }

        func label(
            _ text: String,
            x: CGFloat,
            y: CGFloat,
            color: CGColor
        ) {
            let font = CTFontCreateWithName(
                "Helvetica-Bold" as CFString,
                11,
                nil
            )

            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(
                    kCTFontAttributeName as String
                ): font,
                NSAttributedString.Key(
                    kCTForegroundColorAttributeName as String
                ): color
            ]

            let textLine = CTLineCreateWithAttributedString(
                NSAttributedString(
                    string: text,
                    attributes: attributes
                )
            )

            context.textPosition = CGPoint(
                x: x,
                y: y
            )

            CTLineDraw(
                textLine,
                context
            )
        }

        let bleed = CGFloat(
            geometry.bleedInches * 72
        )

        outline(
            mediaBox.insetBy(
                dx: bleed,
                dy: bleed
            ),
            color: CGColor(
                gray: 0.3,
                alpha: 1
            ),
            dash: [5, 3]
        )

        let panels: [
            (
                String,
                BOLDPrintCoverGeometry.Panel,
                CGColor
            )
        ] = [
            (
                "BACK",
                geometry.back,
                CGColor(
                    red: 0.1,
                    green: 0.3,
                    blue: 0.7,
                    alpha: 1
                )
            ),
            (
                "SPINE",
                geometry.spine,
                CGColor(
                    red: 0.6,
                    green: 0.2,
                    blue: 0.6,
                    alpha: 1
                )
            ),
            (
                "FRONT",
                geometry.front,
                CGColor(
                    red: 0.1,
                    green: 0.5,
                    blue: 0.3,
                    alpha: 1
                )
            )
        ]

        for (name, panel, color) in panels {
            let panelRect = rect(panel)

            outline(
                panelRect,
                color: color
            )

            if name != "SPINE" {
                let inset = CGFloat(
                    safeInsetInches * 72
                )

                outline(
                    panelRect.insetBy(
                        dx: inset,
                        dy: inset
                    ),
                    color: color,
                    dash: [3, 3]
                )

                label(
                    name,
                    x: panelRect.midX - 18,
                    y: panelRect.midY,
                    color: color
                )
            }
        }

        label(
            "BOLD WRITER — GUIDE ONLY — REMOVE BEFORE PRINTING",
            x: bleed + 6,
            y: max(2, bleed / 2),
            color: CGColor(
                red: 0.65,
                green: 0.1,
                blue: 0.1,
                alpha: 1
            )
        )

        context.endPDFPage()
        context.closePDF()

        guard let document = PDFDocument(url: temporary),
              document.pageCount == 1,
              let page = document.page(at: 0),
              abs(
                  Double(
                      page.bounds(
                          for: .mediaBox
                      ).width
                  ) - width
              ) < 0.5,
              abs(
                  Double(
                      page.bounds(
                          for: .mediaBox
                      ).height
                  ) - height
              ) < 0.5 else {
            throw ProofError.verificationFailed
        }

        // Reject exports if the printer-facing PDF geometry was lost.
        let finishedTrim = page.bounds(for: .trimBox)
        let finishedBleed = page.bounds(for: .bleedBox)
        guard abs(Double(finishedTrim.minX) - Double(trimBox.minX)) < 0.5,
              abs(Double(finishedTrim.minY) - Double(trimBox.minY)) < 0.5,
              abs(Double(finishedTrim.width) - Double(trimBox.width)) < 0.5,
              abs(Double(finishedTrim.height) - Double(trimBox.height)) < 0.5,
              abs(Double(finishedBleed.width) - Double(mediaBox.width)) < 0.5,
              abs(Double(finishedBleed.height) - Double(mediaBox.height)) < 0.5 else {
            throw ProofError.verificationFailed
        }

        guard !fm.fileExists(atPath: target.path) else {
            throw ProofError.destinationExists
        }

        do {
            try fm.moveItem(
                at: temporary,
                to: target
            )
        } catch {
            throw ProofError.creationFailed
        }
    }
}
