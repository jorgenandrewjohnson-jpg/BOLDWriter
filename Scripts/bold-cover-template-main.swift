import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
enum BOLDCoverTemplateCLI {
    static func run(_ arguments: [String]) -> Int32 {
        if arguments == ["--help"] || arguments == ["-h"] {
            print(
                "Usage: Scripts/bold cover-template --pages N --trim WIDTHxHEIGHT --caliper-mils N --bleed INCHES --output FILE.svg [--safe-inset INCHES] [--spine-allowance INCHES] [--json]"
            )
            return 0
        }

        var values: [String: String] = [:]
        var json = false
        var offset = 0

        let allowed = Set([
            "--pages",
            "--trim",
            "--caliper-mils",
            "--bleed",
            "--output",
            "--safe-inset",
            "--spine-allowance"
        ])

        while offset < arguments.count {
            let key = arguments[offset]

            if key == "--json" && !json {
                json = true
                offset += 1
                continue
            }

            guard allowed.contains(key),
                  values[key] == nil,
                  offset + 1 < arguments.count else {
                fputs(
                    "COVER_TEMPLATE_ERROR=Invalid or duplicate argument: \(key)\n",
                    stderr
                )
                return 2
            }

            values[key] = arguments[offset + 1]
            offset += 2
        }

        guard let pageText = values["--pages"],
              let pageCount = Int(pageText),
              let trimText = values["--trim"],
              let caliperText = values["--caliper-mils"],
              let caliper = Double(caliperText),
              let bleedText = values["--bleed"],
              let bleed = Double(bleedText),
              let outputText = values["--output"],
              !outputText.isEmpty,
              let safeInset = Double(
                  values["--safe-inset"] ?? "0.25"
              ),
              let allowance = Double(
                  values["--spine-allowance"] ?? "0"
              ) else {
            fputs(
                "COVER_TEMPLATE_ERROR=Required or numeric argument missing\n",
                stderr
            )
            return 2
        }

        let parts = trimText.lowercased().split(
            separator: "x",
            omittingEmptySubsequences: false
        )

        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]) else {
            fputs(
                "COVER_TEMPLATE_ERROR=Trim must be WIDTHxHEIGHT\n",
                stderr
            )
            return 2
        }

        let outputURL = URL(
            fileURLWithPath: outputText
        ).standardizedFileURL

        guard outputURL.pathExtension.lowercased() == "svg" else {
            fputs(
                "COVER_TEMPLATE_ERROR=Output must have .svg extension\n",
                stderr
            )
            return 2
        }

        do {
            let geometry = try BOLDPrintCoverGeometry.calculate(
                pageCount: pageCount,
                trimWidthInches: width,
                trimHeightInches: height,
                sheetCaliperMils: caliper,
                bleedInches: bleed,
                spineAllowanceInches: allowance
            )

            let content = try BOLDPrintCoverTemplateSVG.render(
                geometry: geometry,
                safeInsetInches: safeInset
            )

            do {
                try Data(content.utf8).write(
                    to: outputURL,
                    options: [.withoutOverwriting]
                )
            } catch {
                fputs(
                    "COVER_TEMPLATE_ERROR=Could not create SVG without overwriting: \(error)\n",
                    stderr
                )
                return 3
            }

            if json {
                struct Export: Encodable {
                    let schemaVersion: Int
                    let outputSVG: String
                    let safeInsetInches: Double
                    let geometry: BOLDPrintCoverGeometry.Result
                }

                let result = Export(
                    schemaVersion: 1,
                    outputSVG: outputURL.path,
                    safeInsetInches: safeInset,
                    geometry: geometry
                )

                let encoder = JSONEncoder()
                encoder.outputFormatting = [
                    .prettyPrinted,
                    .sortedKeys
                ]

                let encoded = try encoder.encode(result)

                guard let string = String(
                    data: encoded,
                    encoding: .utf8
                ) else {
                    fputs(
                        "COVER_TEMPLATE_ERROR=Cannot encode JSON\n",
                        stderr
                    )
                    return 3
                }

                print(string)
            } else {
                print("COVER_TEMPLATE_RESULT=PASS")
                print("COVER_TEMPLATE_FILE=\(outputURL.path)")
                print(
                    "COVER_TEMPLATE_SPINE_INCHES=\(geometry.spineWidthInches)"
                )
                print(
                    "COVER_TEMPLATE_GUIDE_ONLY=REMOVE_BEFORE_PRINT"
                )
            }

            return 0
        } catch {
            fputs(
                "COVER_TEMPLATE_ERROR=\(error)\n",
                stderr
            )
            return 2
        }
    }

    static func main() {
        exit(
            run(Array(CommandLine.arguments.dropFirst()))
        )
    }
}
