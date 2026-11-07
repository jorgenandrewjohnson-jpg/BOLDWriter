import Foundation

/// Paperback flat-wrap geometry, measured in inches from the
/// lower-left corner of the complete back–spine–front artwork.
enum BOLDPrintCoverGeometry {
    struct Panel: Codable, Equatable {
        let xInches: Double
        let yInches: Double
        let widthInches: Double
        let heightInches: Double
    }

    struct Result: Codable, Equatable {
        let schemaVersion: Int
        let pageCount: Int
        let sheetCount: Int
        let trimWidthInches: Double
        let trimHeightInches: Double
        let sheetCaliperMils: Double
        let bleedInches: Double
        let spineAllowanceInches: Double
        let spineWidthInches: Double
        let totalCoverWidthInches: Double
        let totalCoverHeightInches: Double
        let back: Panel
        let spine: Panel
        let front: Panel
    }

    enum GeometryError: Error, CustomStringConvertible {
        case invalid(String)

        var description: String {
            switch self {
            case let .invalid(message):
                return message
            }
        }
    }

    static func calculate(
        pageCount: Int,
        trimWidthInches: Double,
        trimHeightInches: Double,
        sheetCaliperMils: Double,
        bleedInches: Double,
        spineAllowanceInches: Double = 0
    ) throws -> Result {
        guard (1...1_000_000).contains(pageCount) else {
            throw GeometryError.invalid(
                "Page count must be 1 through 1000000"
            )
        }

        guard trimWidthInches.isFinite,
              trimHeightInches.isFinite,
              (1...20).contains(trimWidthInches),
              (1...20).contains(trimHeightInches) else {
            throw GeometryError.invalid(
                "Trim width and height must each be 1 through 20 inches"
            )
        }

        guard sheetCaliperMils.isFinite,
              (0.1...30).contains(sheetCaliperMils) else {
            throw GeometryError.invalid(
                "Sheet caliper must be 0.1 through 30 mils"
            )
        }

        guard bleedInches.isFinite,
              (0...1).contains(bleedInches) else {
            throw GeometryError.invalid(
                "Bleed must be 0 through 1 inch"
            )
        }

        guard spineAllowanceInches.isFinite,
              (0...0.5).contains(spineAllowanceInches) else {
            throw GeometryError.invalid(
                "Spine allowance must be 0 through 0.5 inch"
            )
        }

        // One physical sheet has two printed pages.
        // An odd final page requires another physical sheet.
        let sheetCount = (pageCount + 1) / 2

        let spine =
            Double(sheetCount) * sheetCaliperMils / 1000
            + spineAllowanceInches

        let backX = bleedInches
        let spineX = backX + trimWidthInches
        let frontX = spineX + spine
        let y = bleedInches

        let result = Result(
            schemaVersion: 1,
            pageCount: pageCount,
            sheetCount: sheetCount,
            trimWidthInches: trimWidthInches,
            trimHeightInches: trimHeightInches,
            sheetCaliperMils: sheetCaliperMils,
            bleedInches: bleedInches,
            spineAllowanceInches: spineAllowanceInches,
            spineWidthInches: spine,
            totalCoverWidthInches:
                frontX + trimWidthInches + bleedInches,
            totalCoverHeightInches:
                trimHeightInches + 2 * bleedInches,
            back: Panel(
                xInches: backX,
                yInches: y,
                widthInches: trimWidthInches,
                heightInches: trimHeightInches
            ),
            spine: Panel(
                xInches: spineX,
                yInches: y,
                widthInches: spine,
                heightInches: trimHeightInches
            ),
            front: Panel(
                xInches: frontX,
                yInches: y,
                widthInches: trimWidthInches,
                heightInches: trimHeightInches
            )
        )

        guard [
            result.spineWidthInches,
            result.totalCoverWidthInches,
            result.totalCoverHeightInches
        ].allSatisfy({ $0.isFinite }) else {
            throw GeometryError.invalid(
                "Computed geometry is not finite"
            )
        }

        return result
    }
}
