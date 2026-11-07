import Foundation

/// Determines whether existing editable cover artwork can be displayed
/// on a calculated physical wrap without silently resizing the design.
enum BOLDPrintCoverArtworkAlignment {
    struct Assessment: Equatable {
        let artworkWidthInches: Double
        let artworkHeightInches: Double
        let targetWidthInches: Double
        let targetHeightInches: Double
        let matches: Bool

        var warning: String? {
            guard !matches else { return nil }

            return String(
                format:
                    "Cover artwork is %.3f × %.3f in, but the calculated print wrap is %.3f × %.3f in. Update the Cover Creator canvas or printer specifications before combining artwork and guides.",
                locale: Locale(identifier: "en_US_POSIX"),
                artworkWidthInches,
                artworkHeightInches,
                targetWidthInches,
                targetHeightInches
            )
        }
    }

    /// The same physical unit convention used by Cover Creator:
    /// inches, millimeters, or pixels at the project's DPI.
    static func evaluate(
        project: CoverProject,
        geometry: BOLDPrintCoverGeometry.Result,
        toleranceInches: Double = 0.0125
    ) -> Assessment? {
        let multiplier: Double

        switch (project.unit ?? "in").lowercased() {
        case "in":
            multiplier = 1
        case "mm":
            multiplier = 1 / 25.4
        case "px":
            guard project.dpi.isFinite,
                  project.dpi > 0 else {
                return nil
            }
            multiplier = 1 / project.dpi
        default:
            return nil
        }

        let width = project.canvasWidth * multiplier
        let height = project.canvasHeight * multiplier

        guard [
            width,
            height,
            toleranceInches,
            geometry.totalCoverWidthInches,
            geometry.totalCoverHeightInches
        ].allSatisfy({ $0.isFinite }),
        width > 0,
        height > 0,
        toleranceInches >= 0,
        geometry.totalCoverWidthInches > 0,
        geometry.totalCoverHeightInches > 0 else {
            return nil
        }

        let matches =
            abs(width - geometry.totalCoverWidthInches)
                <= toleranceInches
            && abs(height - geometry.totalCoverHeightInches)
                <= toleranceInches

        return Assessment(
            artworkWidthInches: width,
            artworkHeightInches: height,
            targetWidthInches: geometry.totalCoverWidthInches,
            targetHeightInches: geometry.totalCoverHeightInches,
            matches: matches
        )
    }
}
