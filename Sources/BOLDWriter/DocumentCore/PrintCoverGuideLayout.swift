import Foundation

/// Deterministic projection of physical paperback cover geometry into
/// a drawable canvas. All preview coordinates use a top-left origin.
enum BOLDPrintCoverGuideLayout {
    struct Rectangle: Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        var maxX: Double { x + width }
        var maxY: Double { y + height }
        var midX: Double { x + width / 2 }
        var midY: Double { y + height / 2 }
    }

    struct Result: Equatable {
        let sheet: Rectangle
        let trim: Rectangle
        let back: Rectangle
        let spine: Rectangle
        let front: Rectangle
        let backSafe: Rectangle
        let frontSafe: Rectangle
        let scale: Double
    }

    static func calculate(
        geometry: BOLDPrintCoverGeometry.Result,
        safeInsetInches: Double,
        canvasWidth: Double,
        canvasHeight: Double,
        padding: Double = 12
    ) -> Result? {
        let dimensions = [
            safeInsetInches,
            canvasWidth,
            canvasHeight,
            padding,
            geometry.totalCoverWidthInches,
            geometry.totalCoverHeightInches,
            geometry.trimWidthInches,
            geometry.trimHeightInches,
            geometry.spineWidthInches,
            geometry.bleedInches
        ]

        guard dimensions.allSatisfy({ $0.isFinite }),
              canvasWidth > 0,
              canvasHeight > 0,
              padding >= 0,
              safeInsetInches >= 0,
              geometry.totalCoverWidthInches > 0,
              geometry.totalCoverHeightInches > 0,
              geometry.spineWidthInches > 0,
              geometry.trimWidthInches > 0,
              geometry.trimHeightInches > 0,
              geometry.bleedInches >= 0,
              safeInsetInches * 2 < geometry.trimWidthInches,
              safeInsetInches * 2 < geometry.trimHeightInches else {
            return nil
        }

        let availableWidth = canvasWidth - 2 * padding
        let availableHeight = canvasHeight - 2 * padding

        guard availableWidth > 0,
              availableHeight > 0 else {
            return nil
        }

        let scale = min(
            availableWidth / geometry.totalCoverWidthInches,
            availableHeight / geometry.totalCoverHeightInches
        )

        guard scale.isFinite, scale > 0 else {
            return nil
        }

        let sheetWidth = geometry.totalCoverWidthInches * scale
        let sheetHeight = geometry.totalCoverHeightInches * scale

        let left = (canvasWidth - sheetWidth) / 2
        let top = (canvasHeight - sheetHeight) / 2

        let sheet = Rectangle(
            x: left,
            y: top,
            width: sheetWidth,
            height: sheetHeight
        )

        func project(
            _ panel: BOLDPrintCoverGeometry.Panel
        ) -> Rectangle {
            Rectangle(
                x: left + panel.xInches * scale,
                y: top + (
                    geometry.totalCoverHeightInches
                    - panel.yInches
                    - panel.heightInches
                ) * scale,
                width: panel.widthInches * scale,
                height: panel.heightInches * scale
            )
        }

        let back = project(geometry.back)
        let spine = project(geometry.spine)
        let front = project(geometry.front)

        let bleed = geometry.bleedInches * scale
        let safe = safeInsetInches * scale

        let trim = Rectangle(
            x: sheet.x + bleed,
            y: sheet.y + bleed,
            width: sheet.width - 2 * bleed,
            height: sheet.height - 2 * bleed
        )

        func safeRectangle(
            _ rectangle: Rectangle
        ) -> Rectangle {
            Rectangle(
                x: rectangle.x + safe,
                y: rectangle.y + safe,
                width: rectangle.width - 2 * safe,
                height: rectangle.height - 2 * safe
            )
        }

        let result = Result(
            sheet: sheet,
            trim: trim,
            back: back,
            spine: spine,
            front: front,
            backSafe: safeRectangle(back),
            frontSafe: safeRectangle(front),
            scale: scale
        )

        let outputValues = [
            result.sheet.x,
            result.sheet.y,
            result.sheet.width,
            result.sheet.height,
            result.trim.x,
            result.trim.y,
            result.trim.width,
            result.trim.height,
            result.back.width,
            result.spine.width,
            result.front.width,
            result.backSafe.width,
            result.frontSafe.width
        ]

        guard outputValues.allSatisfy({ $0.isFinite }),
              result.trim.width > 0,
              result.trim.height > 0,
              result.backSafe.width > 0,
              result.frontSafe.width > 0 else {
            return nil
        }

        return result
    }
}
