import AppKit
import CoreGraphics
import SwiftUI

/// Live physical-paperback cover preview.
/// Uses the same BOLDPrintCoverGeometry.Result as SVG and PDF exports.
struct BOLDPrintCoverGuidePreview: View {
    let geometry: BOLDPrintCoverGeometry.Result
    let safeInsetInches: Double
    let artwork: NSImage?

    private let backColor = Color(
        red: 0.13,
        green: 0.40,
        blue: 0.76
    )

    private let spineColor = Color(
        red: 0.59,
        green: 0.30,
        blue: 0.70
    )

    private let frontColor = Color(
        red: 0.14,
        green: 0.51,
        blue: 0.33
    )

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            HStack {
                Text("Live physical cover layout")
                    .font(.caption.weight(.semibold))

                Spacer()

                Text("BACK  •  SPINE  •  FRONT")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Canvas { context, size in
                guard let plan =
                    BOLDPrintCoverGuideLayout.calculate(
                        geometry: geometry,
                        safeInsetInches: safeInsetInches,
                        canvasWidth: Double(size.width),
                        canvasHeight: Double(size.height),
                        padding: 12
                    ) else {
                    return
                }

                func rectangle(
                    _ value: BOLDPrintCoverGuideLayout.Rectangle
                ) -> CGRect {
                    CGRect(
                        x: value.x,
                        y: value.y,
                        width: value.width,
                        height: value.height
                    )
                }

                func stroke(
                    _ value: BOLDPrintCoverGuideLayout.Rectangle,
                    color: Color,
                    lineWidth: CGFloat = 1,
                    dash: [CGFloat] = []
                ) {
                    context.stroke(
                        Path(rectangle(value)),
                        with: .color(color),
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            dash: dash
                        )
                    )
                }

                context.fill(
                    Path(rectangle(plan.sheet)),
                    with: .color(
                        Color(
                            red: 0.87,
                            green: 0.87,
                            blue: 0.87
                        )
                    )
                )

                context.fill(
                    Path(rectangle(plan.trim)),
                    with: .color(.white)
                )

                // Existing editable cover composition, rendered at a
                // bounded resolution by the production CoverArtwork API.
                // The geometry assessment prevents distorted placement.
                if let artwork {
                    context.draw(
                        Image(nsImage: artwork),
                        in: rectangle(plan.sheet)
                    )
                }

                stroke(
                    plan.sheet,
                    color: .gray,
                    lineWidth: 0.8
                )

                stroke(
                    plan.trim,
                    color: .gray,
                    lineWidth: 0.8,
                    dash: [5, 3]
                )

                stroke(
                    plan.back,
                    color: backColor,
                    lineWidth: 1.5
                )

                stroke(
                    plan.spine,
                    color: spineColor,
                    lineWidth: 1.5
                )

                stroke(
                    plan.front,
                    color: frontColor,
                    lineWidth: 1.5
                )

                stroke(
                    plan.backSafe,
                    color: backColor.opacity(0.75),
                    lineWidth: 0.8,
                    dash: [3, 3]
                )

                stroke(
                    plan.frontSafe,
                    color: frontColor.opacity(0.75),
                    lineWidth: 0.8,
                    dash: [3, 3]
                )

                func title(
                    _ label: String,
                    in panel: BOLDPrintCoverGuideLayout.Rectangle,
                    color: Color
                ) {
                    context.draw(
                        Text(label)
                            .font(
                                .system(
                                    size: 12,
                                    weight: .semibold
                                )
                            )
                            .foregroundColor(color),
                        at: CGPoint(
                            x: panel.midX,
                            y: panel.midY
                        )
                    )
                }

                title(
                    "BACK",
                    in: plan.back,
                    color: backColor
                )

                title(
                    "FRONT",
                    in: plan.front,
                    color: frontColor
                )

                if plan.spine.width >= 45 {
                    title(
                        "SPINE",
                        in: plan.spine,
                        color: spineColor
                    )
                } else if plan.spine.width >= 16 {
                    context.draw(
                        Text("S")
                            .font(
                                .system(
                                    size: 11,
                                    weight: .bold
                                )
                            )
                            .foregroundColor(spineColor),
                        at: CGPoint(
                            x: plan.spine.midX,
                            y: plan.spine.midY
                        )
                    )
                }
            }
            .frame(height: 170)
            .background(
                Color(
                    nsColor: .controlBackgroundColor
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 7
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 7
                )
                .strokeBorder(
                    Color.secondary.opacity(0.2),
                    lineWidth: 1
                )
            }
            .accessibilityLabel(
                "Scaled paperback wrap preview with back cover, spine, front cover, bleed, and safe-area guides"
            )

            Text(
                "Gray edge: bleed • dashed boundaries: trim and safe text areas • guides are not final artwork"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
