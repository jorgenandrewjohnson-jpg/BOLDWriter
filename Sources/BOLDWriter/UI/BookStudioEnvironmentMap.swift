import AppKit

/// Small, generated cube maps provide broad studio reflections without external
/// HDR assets. Face order follows SceneKit's +X, -X, +Y, -Y, +Z, -Z convention.
enum BookStudioEnvironmentMap {
    private static let maps: [BookEnvironmentPreset: NSArray] = {
        Dictionary(uniqueKeysWithValues: BookEnvironmentPreset.allCases.map { preset in
            (preset, NSArray(array: (0..<6).map { face(preset: preset, direction: $0) }))
        })
    }()

    static func cubeMap(for preset: BookEnvironmentPreset) -> NSArray {
        maps[preset]!
    }

    private static func face(preset: BookEnvironmentPreset, direction: Int) -> NSImage {
        let size = 128
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let base = preset.background.usingColorSpace(.deviceRGB) ?? preset.background
        let warm = preset == .warm
        for y in 0..<size {
            for x in 0..<size {
                let u = (CGFloat(x) + 0.5) / CGFloat(size) * 2 - 1
                let v = (CGFloat(y) + 0.5) / CGFloat(size) * 2 - 1
                let softbox: CGFloat
                switch direction {
                case 0: softbox = panel(u: u, v: v, centerX: 0.2, centerY: 0,
                                        halfWidth: 0.42, halfHeight: 0.72) * 0.57
                case 2: softbox = panel(u: u, v: v, centerX: -0.12, centerY: 0,
                                        halfWidth: 0.84, halfHeight: 0.75) * 0.42
                case 4: softbox = panel(u: u, v: v, centerX: -0.3, centerY: 0.12,
                                        halfWidth: 0.46, halfHeight: 0.66) * 0.80
                default: softbox = 0
                }
                let subdued: CGFloat = preset == .dark ? 0.25 : 0.58
                let highlight = softbox * (preset == .dark ? 0.84 : 1)
                bitmap.setColor(NSColor(calibratedRed: min(1, base.redComponent * subdued + highlight),
                                        green: min(1, base.greenComponent * subdued + highlight * (warm ? 0.91 : 1)),
                                        blue: min(1, base.blueComponent * subdued + highlight * (warm ? 0.76 : 1)),
                                        alpha: 1), atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(bitmap)
        return image
    }

    private static func panel(u: CGFloat, v: CGFloat, centerX: CGFloat, centerY: CGFloat,
                              halfWidth: CGFloat, halfHeight: CGFloat) -> CGFloat {
        let horizontal = min(1, max(0, (halfWidth - abs(u - centerX)) / 0.16))
        let vertical = min(1, max(0, (halfHeight - abs(v - centerY)) / 0.16))
        return horizontal * horizontal * (3 - 2 * horizontal)
             * vertical * vertical * (3 - 2 * vertical)
    }
}
