import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
enum BOLDPrintCoverGeometryCLI {
    static func usage() -> String {
        "Usage: Scripts/bold cover-geometry --pages N --trim WIDTHxHEIGHT --caliper-mils N --bleed INCHES [--spine-allowance INCHES] [--json]"
    }

    static func run(_ arguments: [String]) -> Int32 {
        if arguments == ["--help"] || arguments == ["-h"] {
            print(usage())
            return 0
        }

        var options: [String: String] = [:]
        var json = false
        var cursor = 0

        while cursor < arguments.count {
            let key = arguments[cursor]

            if key == "--json" {
                if json {
                    fputs(
                        "COVER_GEOMETRY_ERROR=Duplicate --json\n",
                        stderr
                    )
                    return 2
                }

                json = true
                cursor += 1
                continue
            }

            guard [
                "--pages",
                "--trim",
                "--caliper-mils",
                "--bleed",
                "--spine-allowance"
            ].contains(key),
                options[key] == nil,
                cursor + 1 < arguments.count else {
                fputs(
                    "COVER_GEOMETRY_ERROR=Invalid or duplicate argument: \(key)\n",
                    stderr
                )
                fputs(usage() + "\n", stderr)
                return 2
            }

            options[key] = arguments[cursor + 1]
            cursor += 2
        }

        guard let pagesText = options["--pages"],
              let pages = Int(pagesText),
              let trimText = options["--trim"],
              let caliperText = options["--caliper-mils"],
              let caliper = Double(caliperText),
              let bleedText = options["--bleed"],
              let bleed = Double(bleedText),
              let allowance = Double(
                  options["--spine-allowance"] ?? "0"
              ) else {
            fputs(
                "COVER_GEOMETRY_ERROR=Missing or invalid input\n",
                stderr
            )
            fputs(usage() + "\n", stderr)
            return 2
        }

        let dimensions = trimText.lowercased().split(
            separator: "x",
            omittingEmptySubsequences: false
        )

        guard dimensions.count == 2,
              let width = Double(dimensions[0]),
              let height = Double(dimensions[1]) else {
            fputs(
                "COVER_GEOMETRY_ERROR=Trim must be WIDTHxHEIGHT\n",
                stderr
            )
            return 2
        }

        do {
            let geometry = try BOLDPrintCoverGeometry.calculate(
                pageCount: pages,
                trimWidthInches: width,
                trimHeightInches: height,
                sheetCaliperMils: caliper,
                bleedInches: bleed,
                spineAllowanceInches: allowance
            )

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [
                    .prettyPrinted,
                    .sortedKeys
                ]

                let data = try encoder.encode(geometry)

                guard let output = String(
                    data: data,
                    encoding: .utf8
                ) else {
                    fputs(
                        "COVER_GEOMETRY_ERROR=Invalid UTF-8\n",
                        stderr
                    )
                    return 3
                }

                print(output)
            } else {
                print("COVER_GEOMETRY_RESULT=PASS")
                print("BINDING=PAPERBACK_FLAT_WRAP")
                print("PAGE_COUNT=\(geometry.pageCount)")
                print("PHYSICAL_SHEETS=\(geometry.sheetCount)")

                print(String(
                    format: "SPINE_WIDTH_INCHES=%.5f",
                    geometry.spineWidthInches
                ))

                print(String(
                    format: "FULL_COVER_WIDTH_INCHES=%.5f",
                    geometry.totalCoverWidthInches
                ))

                print(String(
                    format: "FULL_COVER_HEIGHT_INCHES=%.5f",
                    geometry.totalCoverHeightInches
                ))

                print(String(
                    format: "BACK_PANEL_X_INCHES=%.5f",
                    geometry.back.xInches
                ))

                print(String(
                    format: "SPINE_PANEL_X_INCHES=%.5f",
                    geometry.spine.xInches
                ))

                print(String(
                    format: "FRONT_PANEL_X_INCHES=%.5f",
                    geometry.front.xInches
                ))

                print(
                    "NOTE=Use paper caliper, bleed, and binding allowances specified by your printer"
                )
            }

            return 0
        } catch {
            fputs(
                "COVER_GEOMETRY_ERROR=\(error)\n",
                stderr
            )
            return 2
        }
    }

    static func main() {
        exit(run(Array(CommandLine.arguments.dropFirst())))
    }
}
