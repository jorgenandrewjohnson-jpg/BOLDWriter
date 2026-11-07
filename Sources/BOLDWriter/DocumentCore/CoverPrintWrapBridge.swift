import AppKit
import Foundation

enum CoverPrintWrapBridge {

    static func promote(_ original: CoverProject) -> CoverProject? {
        guard original.type == .ebookFront,
              !original.layers.isEmpty,
              original.canvasWidth.isFinite,
              original.canvasHeight.isFinite,
              original.canvasWidth > 0,
              original.canvasHeight > 0
        else {
            return nil
        }

        var result = original
        result.id = UUID()
        result.name = original.name + " - 3D Print Wrap"
        result.type = .printFullWrap
        result.productionBinding = .softcover
        result.kdpHardcoverLayout = nil
        result.productionTemplate = nil
        result.guidesVisible = true

        let bleed = 0.125

        if let dimensions = measuredTemplate(in: original) {
            let width = dimensions.width
            let height = dimensions.height

            let verticalBleed =
                (original.canvasHeight - height) / 2

            let spine =
                original.canvasWidth
                - 2 * width
                - 2 * verticalBleed

            if verticalBleed >= 0,
               verticalBleed <= 0.5,
               spine >= 0.025,
               spine <= 4.0,
               abs(verticalBleed - bleed) <= 0.125 {

                result.trimWidth = width
                result.backWidth = width
                result.trimHeight = height
                result.bleed = verticalBleed
                result.spineWidth = spine

                // The source wrap gives us a canvas measurement, not the
                // publishing profile that produced it. Do not reverse-engineer
                // a page count from an assumed paper stock and present it as
                // verified geometry.
                result.spinePageCount = original.spinePageCount

                return result
            }
        }

        let hasTemplate = original.layers.contains {
            $0.isReferenceLayer
        }

        // A wide canvas is already laid out as a complete cover.
        // Preserve every imported image at its exact canvas position.
        if original.canvasWidth > original.canvasHeight * 1.20 {
            let estimatedSpine =
                max(
                    0.10,
                    min(
                        1.0,
                        Double(
                            original.spinePageCount ?? 240
                        )
                        * PrintCoverSpecification
                            .kdpBlackAndWhiteWhitePaperCaliper
                    )
                )

            let usableWidth =
                original.canvasWidth
                - 2 * bleed
                - estimatedSpine

            let usableHeight =
                original.canvasHeight
                - 2 * bleed

            guard usableWidth > 2,
                  usableHeight > 2
            else {
                return nil
            }

            result.bleed = bleed
            result.trimWidth = usableWidth / 2
            result.backWidth = usableWidth / 2
            result.trimHeight = usableHeight
            result.spineWidth = estimatedSpine

            return result
        }

        // A conventional eBook front cover needs a separate print canvas.
        // Its original artwork is mapped onto the front panel only.
        let width = original.trimWidth
        let height = original.trimHeight

        guard width > 0,
              height > 0
        else {
            return nil
        }

        // A provisional preview can use a clearly disclosed 240-page width.
        // It must remain unverified until the author supplies final pagination
        // and a print profile with measured trim, bleed and paper caliper.
        let spine =
            max(
                0.10,
                min(
                    2.0,
                    Double(original.spinePageCount ?? 240)
                    * PrintCoverSpecification
                        .kdpBlackAndWhiteWhitePaperCaliper
                )
            )

        result.canvasWidth = 2 * width + spine + 2 * bleed
        result.canvasHeight = height + 2 * bleed
        result.trimWidth = width
        result.backWidth = width
        result.trimHeight = height
        result.spineWidth = spine
        result.bleed = bleed

        let front = CoverWrapGeometry(project: result).frontTrim

        for index in result.layers.indices {
            if result.layers[index].isReferenceLayer {
                continue
            }

            let frame = result.layers[index].frame

            result.layers[index].frame = CoverRect(
                x: front.x + frame.x * front.width,
                y: front.y + frame.y * front.height,
                width: frame.width * front.width,
                height: frame.height * front.height
            )
        }

        if hasTemplate {
            result.layers.removeAll {
                $0.isReferenceLayer
            }
        }

        return result
    }

    private static func measuredTemplate(
        in project: CoverProject
    ) -> (width: Double, height: Double)? {

        // Standard KDP paperback template filenames embed trim dimensions.
        // Example: PAPERBACK_8.500x11.000_535_BW...
        let pattern =
            #"(?i)PAPERBACK[_ -]+([0-9]+(?:\.[0-9]+)?)[xX]([0-9]+(?:\.[0-9]+)?)"#

        guard let expression =
                try? NSRegularExpression(pattern: pattern)
        else {
            return nil
        }

        for layer in project.layers where layer.isReferenceLayer {
            let name = layer.name

            let range = NSRange(
                name.startIndex..<name.endIndex,
                in: name
            )

            guard let match =
                    expression.firstMatch(
                        in: name,
                        range: range
                    ),
                  let widthRange =
                    Range(match.range(at: 1), in: name),
                  let heightRange =
                    Range(match.range(at: 2), in: name),
                  let width = Double(name[widthRange]),
                  let height = Double(name[heightRange]),
                  width >= 3,
                  width <= 15,
                  height >= 4,
                  height <= 20
            else {
                continue
            }

            return (width, height)
        }

        return nil
    }
}
