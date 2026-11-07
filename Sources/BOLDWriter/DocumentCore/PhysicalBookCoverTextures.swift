import AppKit

enum PhysicalBookCoverPanel: String, Equatable {
    case front
    case back
}

enum PhysicalBookCoverEdge: String, Equatable {
    case outer
    case top
    case bottom
}

struct PhysicalBookCoverEdgeIssue: Equatable {
    let panel: PhysicalBookCoverPanel
    let edge: PhysicalBookCoverEdge
    let message: String
}

final class PhysicalBookCoverTextures: NSObject {
    let front: NSImage?
    let spine: NSImage?
    let back: NSImage?
    let estimatedMemoryCost: Int
    let edgeIssues: [PhysicalBookCoverEdgeIssue]
    let edgeWarnings: [String]

    struct RenderPlan: Equatable {
        let sourceDPI: Double
        let panelDPI: Double
    }

    /// Budget both the full wrap and its panels, including unusually wide canvases.
    /// Resolution is shared across all surfaces so a narrow spine retains the same scale.
    static func renderPlan(project: CoverProject, previewDPI: Double) -> RenderPlan? {
        guard project.canvasWidth.isFinite, project.canvasHeight.isFinite,
              project.canvasWidth > 0, project.canvasHeight > 0,
              project.canvasWidth <= 100, project.canvasHeight <= 100,
              project.dpi.isFinite, project.dpi > 0,
              previewDPI.isFinite, previewDPI > 0 else { return nil }
        // Leave room for ceil-rounded source dimensions within 16 million pixels.
        let areaDPI = sqrt(15_980_000 / (project.canvasWidth * project.canvasHeight))
        let edgeDPI = 8192 / max(project.canvasWidth, project.canvasHeight)
        let limit = min(360, areaDPI, edgeDPI)
        let panelDPI = min(previewDPI, limit)
        return RenderPlan(sourceDPI: min(max(project.dpi, panelDPI), limit), panelDPI: panelDPI)
    }

    init(project: CoverProject, workingLayers: Bool, previewDPI: Double = 180) {
        let geometry = CoverWrapGeometry(project: project)
        guard let plan = Self.renderPlan(project: project, previewDPI: previewDPI) else {
            front = nil; spine = nil; back = nil; estimatedMemoryCost = 0
            edgeIssues = []; edgeWarnings = ["Cover artwork has invalid preview dimensions or resolution."]
            return
        }
        // Use the production renderer for masks, clipping, adjustments and templates.
        // Keep one CGImage for all three crops rather than serializing the full wrap to TIFF.
        let rendered = try? CoverArtwork.render(project, includeGuides: workingLayers,
            includeTemplate: workingLayers, scale: plan.sourceDPI)
        let raster = rendered?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if workingLayers {
            edgeIssues = []
            edgeWarnings = []
        } else if let rendered {
            let issues =
                Self.inspectTrimBleedIssues(
                    rendered,
                    geometry: geometry,
                    project: project
                )

            edgeIssues = issues
            edgeWarnings = issues.map(\.message)
        } else {
            edgeIssues = []
            edgeWarnings = [
                "Cover artwork could not be rendered for print inspection."
            ]
        }
        front = raster.flatMap { Self.crop($0, region: geometry.frontTrim, project: project, dpi: plan.panelDPI) }
        spine = raster.flatMap { Self.crop($0, region: geometry.spineTrim, project: project, dpi: plan.panelDPI) }
        back = raster.flatMap { Self.crop($0, region: geometry.backTrim, project: project, dpi: plan.panelDPI) }
        estimatedMemoryCost = [front, spine, back].compactMap { image in
            image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }.reduce(0) { $0 + $1.bytesPerRow * $1.height }

    }

    private static func inspectTrimBleedIssues(
        _ image: NSImage,
        geometry: CoverWrapGeometry,
        project: CoverProject
    ) -> [PhysicalBookCoverEdgeIssue] {
        guard project.bleed > 0, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let bleedX = project.bleed / project.canvasWidth
        let bleedY = project.bleed / project.canvasHeight
        func rgb(_ x: Double, _ y: Double) -> (Double, Double, Double)? {
            let px = min(bitmap.pixelsWide - 1, max(0, Int(x * Double(bitmap.pixelsWide))))
            // Bitmap rows and CoverWrapGeometry both start at the top. Flipping
            // here reports a head-edge bleed defect at the foot (and vice versa).
            let py = min(bitmap.pixelsHigh - 1, max(0, Int(y * Double(bitmap.pixelsHigh))))
            guard let color = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB) else { return nil }
            return (Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
        }
        func suspect(_ outer: (Double, Double), _ inner: (Double, Double)) -> Bool {
            guard let a = rgb(outer.0, outer.1), let b = rgb(inner.0, inner.1) else { return false }
            let white = min(a.0, a.1, a.2) > 0.965
            let black = max(a.0, a.1, a.2) < 0.035
            let difference = max(abs(a.0-b.0), abs(a.1-b.1), abs(a.2-b.2))
            return (white || black) && difference > 0.22
        }
        let back = geometry.backTrim, front = geometry.frontTrim
        var issues: [PhysicalBookCoverEdgeIssue] = []
        for (name, panel, isLeft) in [("Back", back, true), ("Front", front, false)] {
            let edge = isLeft ? panel.x : panel.x + panel.width
            let outside = edge + (isLeft ? -bleedX / 2 : bleedX / 2)
            let inside = edge + (isLeft ? bleedX / 2 : -bleedX / 2)
            let hits = (1...9).filter { sample in
                let y = panel.y + panel.height * Double(sample) / 10
                return suspect((outside, y), (inside, y))
            }.count
            if hits >= 3 {
                let panelKind:
                    PhysicalBookCoverPanel =
                        isLeft
                            ? .back
                            : .front

                issues.append(
                    PhysicalBookCoverEdgeIssue(
                        panel: panelKind,
                        edge: .outer,
                        message:
                            "Possible exposed white/black sliver in the \(name.lowercased()) cover outer bleed (\(hits)/9 samples). Extend artwork beyond trim and inspect export."
                    )
                )
            }
            let x = panel.x + panel.width / 2
            for (label, outerY, innerY) in [("top", panel.y - bleedY / 2, panel.y + bleedY / 2), ("bottom", panel.y + panel.height + bleedY / 2, panel.y + panel.height - bleedY / 2)] {
                if suspect(
                    (x, outerY),
                    (x, innerY)
                ) {
                    let panelKind:
                        PhysicalBookCoverPanel =
                            isLeft
                                ? .back
                                : .front

                    let edgeKind:
                        PhysicalBookCoverEdge =
                            label == "top"
                                ? .top
                                : .bottom

                    issues.append(
                        PhysicalBookCoverEdgeIssue(
                            panel: panelKind,
                            edge: edgeKind,
                            message:
                                "Possible exposed white/black sliver in the \(name.lowercased()) cover \(label) bleed. Extend artwork beyond trim."
                        )
                    )
                }
            }
        }
        return issues
    }

    private static func crop(_ cg: CGImage, region: CoverRect, project: CoverProject, dpi: Double) -> NSImage? {
        guard region.x.isFinite, region.y.isFinite, region.width.isFinite, region.height.isFinite,
              region.width > 0, region.height > 0 else { return nil }
        // CoverWrapGeometry uses top-left normalized coordinates, while CGImage
        // cropping starts at the lower-left origin.
        let rect = CGRect(x: region.x * Double(cg.width), y: (1 - region.y - region.height) * Double(cg.height), width: region.width * Double(cg.width), height: region.height * Double(cg.height)).integral
        guard let cropped = cg.cropping(to: rect.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))) else { return nil }
        let pixelWidth = (region.width * project.canvasWidth * dpi).rounded()
        let pixelHeight = (region.height * project.canvasHeight * dpi).rounded()
        guard pixelWidth.isFinite, pixelHeight.isFinite, pixelWidth <= 8192, pixelHeight <= 8192 else { return nil }
        let targetWidth = max(1, Int(pixelWidth))
        let targetHeight = max(1, Int(pixelHeight))
        guard targetWidth <= 8192, targetHeight <= 8192, targetWidth <= 16_000_000 / targetHeight,
              let context = CGContext(data: nil, width: targetWidth, height: targetHeight, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name:CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height)) }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage().map { NSImage(cgImage: $0, size: NSSize(width: targetWidth, height: targetHeight)) }
    }
}
