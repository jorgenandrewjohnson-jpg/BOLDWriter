import AppKit
import Foundation

/// Keep an unfinished page number separate from the selected spread. A live
/// numeric binding otherwise rewrites each keystroke to the spread's odd page.
struct BookStudioPageEntry {
    var text = "1"
    func resolvedPage(pageCount: Int) -> Int? {
        guard pageCount > 0, let page = Int(text.trimmingCharacters(in:.whitespacesAndNewlines)) else { return nil }
        return min(pageCount,max(1,page))
    }
    mutating func synchronize(spreadIndex: Int, pageCount: Int) {
        if let page = resolvedPage(pageCount:pageCount), PhysicalBookGeometry.spread(forPage:page,pageCount:pageCount).index == spreadIndex { return }
        let spread = PhysicalBookGeometry.spread(at:spreadIndex,pageCount:pageCount)
        text = String(spread.rightPage ?? spread.leftPage ?? 1)
    }
}

enum BookCoverFinish: String, Codable, CaseIterable, Identifiable {
    case matte = "Matte"
    case satin = "Satin"
    case gloss = "Gloss"
    case uncoated = "Uncoated"
    case cloth = "Cloth"
    var id: String { rawValue }
    var roughness: CGFloat {
        switch self {
        case .matte: 0.83
        case .satin: 0.53
        case .gloss: 0.20
        case .uncoated: 0.96
        case .cloth: 0.91
        }
    }
}

enum BookPaperTone: String, Codable, CaseIterable, Identifiable {
    case white = "White"
    case cream = "Cream"
    case offWhite = "Off-white"
    var id: String { rawValue }
    var surfaceColor: NSColor {
        switch self {
        case .white: NSColor(calibratedRed: 0.975, green: 0.975, blue: 0.965, alpha: 1)
        case .cream: NSColor(calibratedRed: 0.95, green: 0.925, blue: 0.865, alpha: 1)
        case .offWhite: NSColor(calibratedRed: 0.955, green: 0.95, blue: 0.925, alpha: 1)
        }
    }
}

enum BookEnvironmentPreset: String, Codable, CaseIterable, Identifiable {
    case neutral = "Neutral Studio"
    case softbox = "Softbox"
    case warm = "Warm Room"
    case cool = "Cool Studio"
    case dark = "Dark Product"
    case white = "White Seamless"
    var id: String { rawValue }
    var background: NSColor {
        switch self {
        case .neutral: NSColor(calibratedWhite: 0.93, alpha: 1)
        case .softbox: NSColor(calibratedWhite: 0.88, alpha: 1)
        case .warm: NSColor(calibratedRed: 0.91, green: 0.86, blue: 0.79, alpha: 1)
        case .cool: NSColor(calibratedRed: 0.82, green: 0.87, blue: 0.94, alpha: 1)
        case .dark: NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.19, alpha: 1)
        case .white: .white
        }
    }
    var ground: NSColor {
        switch self {
        case .dark: NSColor(calibratedWhite: 0.18, alpha: 1)
        case .warm: NSColor(calibratedRed: 0.83, green: 0.76, blue: 0.66, alpha: 1)
        case .white: .white
        default: NSColor(calibratedWhite: 0.915, alpha: 1)
        }
    }
}

enum BookLightingPreset: String, Codable, CaseIterable, Identifiable {
    case neutral = "Neutral Product"
    case soft = "Soft Editorial"
    case dramatic = "Dramatic"
    case bright = "Bright Marketplace"
    case library = "Warm Library"
    var id: String { rawValue }
    var levels: (ambient: CGFloat, key: CGFloat, fill: CGFloat, rim: CGFloat, temperature: CGFloat) {
        switch self {
        case .neutral: (235, 920, 340, 275, 5500)
        case .soft: (300, 660, 510, 190, 5700)
        case .dramatic: (100, 1200, 125, 470, 5000)
        case .bright: (410, 1020, 680, 180, 6000)
        case .library: (250, 780, 270, 210, 3800)
        }
    }
}

enum BookCameraProjection: String, Codable, CaseIterable, Identifiable {
    case perspective = "Perspective"
    case orthographic = "Orthographic"
    var id: String { rawValue }
}

enum BookRenderQuality: String, Codable, CaseIterable, Identifiable {
    case fast = "Fast"
    case balanced = "Balanced"
    case high = "High"
    case render = "Render"
    var id: String { rawValue }
}

enum BookSceneComponent: String, CaseIterable, Identifiable {
    case book = "Book"
    case front = "Front Cover"
    case spine = "Spine"
    case back = "Back Cover"
    case pages = "Page Block"
    case leftPage = "Left Page"
    case rightPage = "Right Page"
    case environment = "Environment"
    case lights = "Lights"
    case camera = "Camera"
    var id: String { rawValue }

    static func component(for nodeName: String) -> Self? {
        if nodeName.hasPrefix("book-shell.front") { return .front }
        if nodeName.hasPrefix("book-shell.back") { return .back }
        if nodeName.hasPrefix("book-shell.spine") { return .spine }
        if nodeName.hasPrefix("book.left-active") { return .leftPage }
        if nodeName.hasPrefix("book.right-active") { return .rightPage }
        if nodeName.contains("page-block") || nodeName.contains("page-stack") { return .pages }
        if nodeName == "physical-book.root" { return .book }
        if nodeName.hasPrefix("studio-light") { return .lights }
        if nodeName == "studio-ground" { return .environment }
        if nodeName == "preview-camera" { return .camera }
        return nil
    }
}

enum BookGroundPreset: String, Codable, CaseIterable, Identifiable {
    case none = "None"
    case white = "White"
    case gray = "Neutral Gray"
    case dark = "Dark"
    case warm = "Warm"
    var id: String { rawValue }
    var color: NSColor? {
        switch self {
        case .none: nil
        case .white: .white
        case .gray: NSColor(calibratedWhite: 0.915, alpha: 1)
        case .dark: NSColor(calibratedWhite: 0.18, alpha: 1)
        case .warm: NSColor(calibratedRed: 0.83, green: 0.76, blue: 0.66, alpha: 1)
        }
    }
}

struct BookSavedCamera: Codable, Equatable {
    var yaw: Double
    var pitch: Double
    var distance: Double
    var targetX: Double
    var targetY: Double
    var targetZ: Double

    var isValid: Bool {
        [yaw, pitch, distance, targetX, targetY, targetZ].allSatisfy(\.isFinite)
            && distance >= 0.35 && distance <= 30 && abs(pitch) <= 1.52
    }
}

enum BookStudioAnimationExportFormat:
    String,
    CaseIterable,
    Identifiable
{
    case pngSequence = "PNG Sequence"
    case gif = "Animated GIF"

    var id: String {
        rawValue
    }
}

struct BookStudioAnimationExportPlan:
    Equatable
{
    let duration: Double
    let fps: Int
    let frameCount: Int

    init(
        duration: Double,
        fps: Int
    ) {
        let safeDuration =
            duration.isFinite
            ? max(
                0.25,
                duration
            )
            : 6

        let safeFPS =
            min(
                60,
                max(
                    1,
                    fps
                )
            )

        self.duration =
            safeDuration

        self.fps =
            safeFPS

        frameCount =
            BookStudioAnimationMath
            .frameCount(
                duration:
                    safeDuration,
                fps:
                    safeFPS
            )
    }

    var gifFrameDelay: Double {
        1
        / Double(
            fps
        )
    }

    var pngDigitCount: Int {
        max(
            6,
            String(
                frameCount
            )
            .count
        )
    }

    func pngFileName(
        forFrame index: Int
    ) -> String {
        let number =
            min(
                frameCount,
                max(
                    1,
                    index + 1
                )
            )

        return String(
            format:
                "frame-%0*d.png",
            pngDigitCount,
            number
        )
    }

    func time(
        forFrame index: Int
    ) -> Double {
        BookStudioAnimationMath
            .time(
                forFrame:
                    index,
                duration:
                    duration,
                fps:
                    fps
            )
    }
}

struct BookStudioCameraKeyframe:
    Codable,
    Equatable,
    Identifiable
{
    var id: UUID
    var time: Double
    var camera: BookSavedCamera

    init(
        id: UUID = UUID(),
        time: Double,
        camera: BookSavedCamera
    ) {
        self.id = id
        self.time = time
        self.camera = camera
    }

    func normalized(
        duration: Double
    ) -> BookStudioCameraKeyframe {
        var result =
            self

        result.time =
            time.isFinite
            ? min(
                max(
                    0.25,
                    duration
                ),
                max(
                    0,
                    time
                )
            )
            : 0

        return result
    }
}



enum BookTransformMode: String, Codable, CaseIterable, Identifiable {
    case navigate
    case move
    case rotate
    case scale

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .navigate: "Navigate"
        case .move: "Move"
        case .rotate: "Rotate"
        case .scale: "Scale"
        }
    }
}

enum BookTransformSpace: String, Codable, CaseIterable, Identifiable {
    case local
    case world

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: "Local"
        case .world: "World"
        }
    }
}

struct BookModelTransform: Codable, Equatable {
    var positionX: Double
    var positionY: Double
    var positionZ: Double
    var rotationX: Double
    var rotationY: Double
    var rotationZ: Double
    var scaleX: Double
    var scaleY: Double
    var scaleZ: Double

    static let identity = BookModelTransform()

    init(
        positionX: Double = 0,
        positionY: Double = 0,
        positionZ: Double = 0,
        rotationX: Double = 0,
        rotationY: Double = 0,
        rotationZ: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        scaleZ: Double = 1
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.rotationZ = rotationZ
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.scaleZ = scaleZ
    }

    var normalized: BookModelTransform {
        BookModelTransform(
            positionX: Self.sanitize(positionX, fallback: 0, range: -24 ... 24),
            positionY: Self.sanitize(positionY, fallback: 0, range: -24 ... 24),
            positionZ: Self.sanitize(positionZ, fallback: 0, range: -24 ... 24),
            rotationX: Self.sanitize(rotationX, fallback: 0, range: -360 ... 360),
            rotationY: Self.sanitize(rotationY, fallback: 0, range: -360 ... 360),
            rotationZ: Self.sanitize(rotationZ, fallback: 0, range: -360 ... 360),
            scaleX: Self.sanitize(scaleX, fallback: 1, range: 0.1 ... 10),
            scaleY: Self.sanitize(scaleY, fallback: 1, range: 0.1 ... 10),
            scaleZ: Self.sanitize(scaleZ, fallback: 1, range: 0.1 ... 10)
        )
    }

    private static func sanitize(
        _ value: Double,
        fallback: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey {
        case positionX, positionY, positionZ
        case rotationX, rotationY, rotationZ
        case scaleX, scaleY, scaleZ
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            positionX: try values.decodeIfPresent(Double.self, forKey: .positionX) ?? 0,
            positionY: try values.decodeIfPresent(Double.self, forKey: .positionY) ?? 0,
            positionZ: try values.decodeIfPresent(Double.self, forKey: .positionZ) ?? 0,
            rotationX: try values.decodeIfPresent(Double.self, forKey: .rotationX) ?? 0,
            rotationY: try values.decodeIfPresent(Double.self, forKey: .rotationY) ?? 0,
            rotationZ: try values.decodeIfPresent(Double.self, forKey: .rotationZ) ?? 0,
            scaleX: try values.decodeIfPresent(Double.self, forKey: .scaleX) ?? 1,
            scaleY: try values.decodeIfPresent(Double.self, forKey: .scaleY) ?? 1,
            scaleZ: try values.decodeIfPresent(Double.self, forKey: .scaleZ) ?? 1
        )

        self = normalized
    }
}

enum BookStudioAnimationMath {
    static func normalizedTime(
        _ time: Double,
        duration: Double
    ) -> Double {
        let safeDuration =
            duration.isFinite
            ? max(
                0.25,
                duration
            )
            : 6

        guard time.isFinite else {
            return 0
        }

        return min(
            safeDuration,
            max(
                0,
                time
            )
        )
    }

    static func progress(
        time: Double,
        duration: Double
    ) -> Double {
        let safeDuration =
            duration.isFinite
            ? max(
                0.25,
                duration
            )
            : 6

        return normalizedTime(
            time,
            duration:
                safeDuration
        )
        / safeDuration
    }

    static func frameCount(
        duration: Double,
        fps: Int
    ) -> Int {
        let safeDuration =
            duration.isFinite
            ? max(
                0.25,
                duration
            )
            : 6

        let safeFPS =
            min(
                60,
                max(
                    1,
                    fps
                )
            )

        return max(
            2,
            Int(
                floor(
                    safeDuration
                    * Double(
                        safeFPS
                    )
                )
            )
            + 1
        )
    }

    static func time(
        forFrame index: Int,
        duration: Double,
        fps: Int
    ) -> Double {
        let safeDuration =
            duration.isFinite
            ? max(
                0.25,
                duration
            )
            : 6

        let safeFPS =
            min(
                60,
                max(
                    1,
                    fps
                )
            )

        let frameCount =
            self.frameCount(
                duration:
                    safeDuration,
                fps:
                    safeFPS
            )

        let safeIndex =
            min(
                frameCount - 1,
                max(
                    0,
                    index
                )
            )

        return min(
            safeDuration,
            Double(
                safeIndex
            )
            / Double(
                safeFPS
            )
        )
    }

    static func camera(
        at time: Double,
        keyframes: [BookStudioCameraKeyframe],
        duration: Double
    ) -> BookSavedCamera? {
        let frames =
            keyframes
            .filter {
                $0.time.isFinite
                && $0.camera.isValid
            }
            .map {
                $0.normalized(
                    duration:
                        duration
                )
            }
            .sorted {
                if $0.time == $1.time {
                    return $0.id.uuidString
                        < $1.id.uuidString
                }

                return $0.time
                    < $1.time
            }

        guard
            let first =
                frames.first
        else {
            return nil
        }

        guard
            frames.count > 1
        else {
            return first.camera
        }

        let t =
            normalizedTime(
                time,
                duration:
                    duration
            )

        if t <= first.time {
            return first.camera
        }

        if
            let last =
                frames.last,
            t >= last.time
        {
            return last.camera
        }

        for index in 0 ..< frames.count - 1 {
            let left =
                frames[
                    index
                ]

            let right =
                frames[
                    index + 1
                ]

            guard
                t >= left.time,
                t <= right.time
            else {
                continue
            }

            let span =
                max(
                    0.000_001,
                    right.time
                    - left.time
                )

            let amount =
                min(
                    1,
                    max(
                        0,
                        (
                            t
                            - left.time
                        )
                        / span
                    )
                )

            return interpolate(
                from:
                    left.camera,
                to:
                    right.camera,
                amount:
                    amount
            )
        }

        return frames.last?
            .camera
    }

    static func interpolate(
        from start: BookSavedCamera,
        to end: BookSavedCamera,
        amount: Double
    ) -> BookSavedCamera {
        let t =
            min(
                1,
                max(
                    0,
                    amount.isFinite
                    ? amount
                    : 0
                )
            )

        let yawDelta =
            atan2(
                sin(
                    end.yaw
                    - start.yaw
                ),
                cos(
                    end.yaw
                    - start.yaw
                )
            )

        return BookSavedCamera(
            yaw:
                start.yaw
                + yawDelta
                * t,
            pitch:
                mix(
                    start.pitch,
                    end.pitch,
                    t
                ),
            distance:
                mix(
                    start.distance,
                    end.distance,
                    t
                ),
            targetX:
                mix(
                    start.targetX,
                    end.targetX,
                    t
                ),
            targetY:
                mix(
                    start.targetY,
                    end.targetY,
                    t
                ),
            targetZ:
                mix(
                    start.targetZ,
                    end.targetZ,
                    t
                )
        )
    }

    static func turntableTransform(
        base: BookModelTransform,
        time: Double,
        duration: Double,
        enabled: Bool,
        turns: Double,
        clockwise: Bool
    ) -> BookModelTransform {
        guard enabled else {
            return base
        }

        let safeTurns =
            turns.isFinite
            ? min(
                8,
                max(
                    0.25,
                    turns
                )
            )
            : 1

        let direction =
            clockwise
            ? 1.0
            : -1.0

        let angle =
            360
            * safeTurns
            * progress(
                time:
                    time,
                duration:
                    duration
            )
            * direction

        var result =
            base

        result.rotationY =
            wrappedDegrees(
                base.rotationY
                + angle
            )

        return result.normalized
    }

    private static func mix(
        _ start: Double,
        _ end: Double,
        _ amount: Double
    ) -> Double {
        start
        + (
            end
            - start
        )
        * amount
    }

    private static func wrappedDegrees(
        _ value: Double
    ) -> Double {
        guard value.isFinite else {
            return 0
        }

        var result =
            value.truncatingRemainder(
                dividingBy:
                    360
            )

        if result > 180 {
            result -= 360
        }

        if result < -180 {
            result += 360
        }

        return result
    }
}

enum BookStudioCameraKeyframeOrder {
    static func moved(
        _ keyframes: [BookStudioCameraKeyframe],
        id: UUID,
        offset: Int
    ) -> [BookStudioCameraKeyframe] {
        var result =
            keyframes
            .sorted {
                if $0.time == $1.time {
                    return $0.id.uuidString
                        < $1.id.uuidString
                }

                return $0.time
                    < $1.time
            }

        guard
            offset != 0,
            let source =
                result.firstIndex(
                    where: {
                        $0.id == id
                    }
                )
        else {
            return result
        }

        let destination =
            source
            + offset

        guard
            destination >= 0,
            destination
                < result.count
        else {
            return result
        }

        let sourceTime =
            result[
                source
            ]
            .time

        result[
            source
        ]
        .time =
            result[
                destination
            ]
            .time

        result[
            destination
        ]
        .time =
            sourceTime

        return result.sorted {
            if $0.time == $1.time {
                return $0.id.uuidString
                    < $1.id.uuidString
            }

            return $0.time
                < $1.time
        }
    }

    static func canMove(
        _ keyframes: [BookStudioCameraKeyframe],
        id: UUID,
        offset: Int
    ) -> Bool {
        let ordered =
            keyframes.sorted {
                if $0.time == $1.time {
                    return $0.id.uuidString
                        < $1.id.uuidString
                }

                return $0.time
                    < $1.time
            }

        guard
            let source =
                ordered.firstIndex(
                    where: {
                        $0.id == id
                    }
                )
        else {
            return false
        }

        let destination =
            source
            + offset

        return
            destination >= 0
            && destination
                < ordered.count
    }
}



enum BookStudioLightType: String, Codable, CaseIterable, Identifiable {
    case point = "Point"
    case spot = "Spot"

    var id: String {
        rawValue
    }
}

struct BookStudioLight: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var type: BookStudioLightType
    var enabled: Bool
    var intensity: Double
    var colorHex: String
    var range: Double
    var spotInnerAngle: Double
    var spotOuterAngle: Double
    var castsShadow: Bool
    var editorVisible: Bool
    var locked: Bool
    var transform: BookModelTransform

    init(
        id: UUID = UUID(),
        name: String,
        type: BookStudioLightType,
        enabled: Bool = true,
        intensity: Double = 800,
        colorHex: String = "#FFFFFF",
        range: Double = 12,
        spotInnerAngle: Double = 24,
        spotOuterAngle: Double = 42,
        castsShadow: Bool = true,
        editorVisible: Bool = true,
        locked: Bool = false,
        transform: BookModelTransform = .identity
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.enabled = enabled
        self.intensity = intensity
        self.colorHex = colorHex
        self.range = range
        self.spotInnerAngle = spotInnerAngle
        self.spotOuterAngle = spotOuterAngle
        self.castsShadow = castsShadow
        self.editorVisible = editorVisible
        self.locked = locked
        self.transform = transform
    }

    static func point(
        name: String = "Point Light"
    ) -> BookStudioLight {
        var light =
            BookStudioLight(
                name: name,
                type: .point
            )

        light.transform.positionY =
            2.4

        light.transform.positionZ =
            2.2

        return light
    }

    static func spot(
        name: String = "Spot Light"
    ) -> BookStudioLight {
        var light =
            BookStudioLight(
                name: name,
                type: .spot,
                intensity: 1_100
            )

        light.transform.positionY =
            3.2

        light.transform.positionZ =
            3.2

        light.transform.rotationX =
            -35

        return light
    }


    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case enabled
        case intensity
        case colorHex
        case range
        case spotInnerAngle
        case spotOuterAngle
        case castsShadow
        case editorVisible
        case locked
        case transform
    }

    init(from decoder: Decoder) throws {
        let values =
            try decoder.container(
                keyedBy:
                    CodingKeys.self
            )

        id =
            try values.decodeIfPresent(
                UUID.self,
                forKey:
                    .id
            )
            ?? UUID()

        name =
            try values.decodeIfPresent(
                String.self,
                forKey:
                    .name
            )
            ?? "Point Light"

        type =
            try values.decodeIfPresent(
                BookStudioLightType.self,
                forKey:
                    .type
            )
            ?? .point

        enabled =
            try values.decodeIfPresent(
                Bool.self,
                forKey:
                    .enabled
            )
            ?? true

        intensity =
            try values.decodeIfPresent(
                Double.self,
                forKey:
                    .intensity
            )
            ?? 800

        colorHex =
            try values.decodeIfPresent(
                String.self,
                forKey:
                    .colorHex
            )
            ?? "#FFFFFF"

        range =
            try values.decodeIfPresent(
                Double.self,
                forKey:
                    .range
            )
            ?? 12

        spotInnerAngle =
            try values.decodeIfPresent(
                Double.self,
                forKey:
                    .spotInnerAngle
            )
            ?? 24

        spotOuterAngle =
            try values.decodeIfPresent(
                Double.self,
                forKey:
                    .spotOuterAngle
            )
            ?? 42

        castsShadow =
            try values.decodeIfPresent(
                Bool.self,
                forKey:
                    .castsShadow
            )
            ?? true

        editorVisible =
            try values.decodeIfPresent(
                Bool.self,
                forKey:
                    .editorVisible
            )
            ?? true

        locked =
            try values.decodeIfPresent(
                Bool.self,
                forKey:
                    .locked
            )
            ?? false

        transform =
            try values.decodeIfPresent(
                BookModelTransform.self,
                forKey:
                    .transform
            )
            ?? .identity

        self =
            normalized
    }

    var normalized: BookStudioLight {
        var result =
            self

        let trimmed =
            name.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        result.name =
            trimmed.isEmpty
            ? type.rawValue + " Light"
            : trimmed

        result.intensity =
            intensity.isFinite
            ? min(
                10_000,
                max(
                    0,
                    intensity
                )
            )
            : 800

        result.range =
            range.isFinite
            ? min(
                100,
                max(
                    0.1,
                    range
                )
            )
            : 12

        let outer =
            spotOuterAngle.isFinite
            ? min(
                179,
                max(
                    1,
                    spotOuterAngle
                )
            )
            : 42

        let inner =
            spotInnerAngle.isFinite
            ? min(
                outer,
                max(
                    0,
                    spotInnerAngle
                )
            )
            : min(
                24,
                outer
            )

        result.spotOuterAngle =
            outer

        result.spotInnerAngle =
            inner

        result.colorHex =
            Self.normalizedHex(
                colorHex
            )

        result.transform =
            transform.normalized

        return result
    }

    private static func normalizedHex(
        _ value: String
    ) -> String {
        let raw =
            value
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .uppercased()

        let stripped =
            raw.hasPrefix("#")
            ? String(
                raw.dropFirst()
            )
            : raw

        guard
            stripped.count == 6,
            UInt64(
                stripped,
                radix: 16
            ) != nil
        else {
            return "#FFFFFF"
        }

        return "#"
            + stripped
    }
}

enum BookStudioLightOrder {
    static func moved(
        _ lights: [BookStudioLight],
        id: UUID,
        offset: Int
    ) -> [BookStudioLight] {
        guard
            offset != 0,
            let source =
                lights.firstIndex(
                    where: {
                        $0.id == id
                    }
                )
        else {
            return lights
        }

        let destination =
            min(
                lights.count - 1,
                max(
                    0,
                    source + offset
                )
            )

        guard
            destination != source
        else {
            return lights
        }

        var result =
            lights

        let object =
            result.remove(
                at:
                    source
            )

        result.insert(
            object,
            at:
                destination
        )

        return result
    }

    static func canMove(
        _ lights: [BookStudioLight],
        id: UUID,
        offset: Int
    ) -> Bool {
        guard
            let source =
                lights.firstIndex(
                    where: {
                        $0.id == id
                    }
                )
        else {
            return false
        }

        let destination =
            source + offset

        return
            destination >= 0
            && destination
                < lights.count
    }
}


struct BookStudioPresentation: Codable, Equatable {
    /// Shared by the visible slider and persistence; the renderer supports contact at zero.
    static let openingAngleRange = 0.0...180.0
    var binding: BookBinding = .softcover
    var open = false
    var openAngle = 180.0
    var spreadIndex = 0
    var cameraPreset: BookViewPreset = .perspective
    var projection: BookCameraProjection = .perspective
    var finish: BookCoverFinish = .matte
    var paper: BookPaperTone = .offWhite
    var environment: BookEnvironmentPreset = .neutral
    var lighting: BookLightingPreset = .neutral
    var ground: BookGroundPreset = .gray
    var quality: BookRenderQuality = .balanced
    var showMeasurements = false
    var showProductionMargins: Bool? = nil
    var savedCamera: BookSavedCamera?
    var cameraFieldOfView = 34.0
    var environmentIntensity = 1.0
    var lightIntensity = 1.0
    var shadowsEnabled = true
    var exploded = false
    var transformMode: BookTransformMode = .navigate
    var transformSpace: BookTransformSpace = .local
    var modelTransform: BookModelTransform = .identity
    var transformSnapEnabled = false
    var moveSnapStep = 0.25
    var rotateSnapStep = 15.0
    var scaleSnapStep = 0.1
    var customLights: [BookStudioLight] = []
    var cameraEditorVisible = true
    var cameraEditorLocked = false
    var lightGuidesVisible = true
    var bookEditorVisible = true
    var bookTransformLocked = false
    var groundEditorVisible = true
    var groundEditorLocked = false
    var outlinerBookExpanded = true
    var outlinerEnvironmentExpanded = true
    var outlinerLightingExpanded = true
    var outlinerCameraExpanded = true
    var animationDuration = 6.0
    var animationFPS = 30
    var animationLoop = true
    var animationPlayhead = 0.0
    var turntableEnabled = false
    var turntableTurns = 1.0
    var turntableClockwise = true
    var cameraKeyframes: [BookStudioCameraKeyframe] = []

    private enum CodingKeys: String, CodingKey {
        case binding, open, openAngle, spreadIndex, cameraPreset, projection, finish
        case paper, environment, lighting, ground, quality, showMeasurements, savedCamera
        case cameraFieldOfView, environmentIntensity, lightIntensity, shadowsEnabled, exploded, showProductionMargins
        case transformMode, transformSpace, modelTransform
        case transformSnapEnabled, moveSnapStep, rotateSnapStep, scaleSnapStep
        case customLights
        case cameraEditorVisible, cameraEditorLocked, lightGuidesVisible
        case bookEditorVisible, bookTransformLocked
        case groundEditorVisible, groundEditorLocked
        case outlinerBookExpanded, outlinerEnvironmentExpanded
        case outlinerLightingExpanded, outlinerCameraExpanded
        case animationDuration, animationFPS, animationLoop, animationPlayhead
        case turntableEnabled, turntableTurns, turntableClockwise
        case cameraKeyframes
    }

    init(binding: BookBinding = .softcover, open: Bool = false, openAngle: Double = 180,
         spreadIndex: Int = 0, cameraPreset: BookViewPreset = .perspective,
         projection: BookCameraProjection = .perspective, finish: BookCoverFinish = .matte,
         paper: BookPaperTone = .offWhite, environment: BookEnvironmentPreset = .neutral,
         lighting: BookLightingPreset = .neutral, ground: BookGroundPreset = .gray,
         quality: BookRenderQuality = .balanced, showMeasurements: Bool = false,
         savedCamera: BookSavedCamera? = nil, cameraFieldOfView: Double = 34,
         environmentIntensity: Double = 1, lightIntensity: Double = 1,
         shadowsEnabled: Bool = true, exploded: Bool = false) {
        self.binding = binding
        self.open = open
        self.openAngle = openAngle
        self.spreadIndex = spreadIndex
        self.cameraPreset = cameraPreset
        self.projection = projection
        self.finish = finish
        self.paper = paper
        self.environment = environment
        self.lighting = lighting
        self.ground = ground
        self.quality = quality
        self.showMeasurements = showMeasurements
        self.savedCamera = savedCamera
        self.cameraFieldOfView = cameraFieldOfView
        self.environmentIntensity = environmentIntensity
        self.lightIntensity = lightIntensity
        self.shadowsEnabled = shadowsEnabled
        self.exploded = exploded
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        binding = try values.decodeIfPresent(BookBinding.self, forKey: .binding) ?? .softcover
        open = try values.decodeIfPresent(Bool.self, forKey: .open) ?? false
        openAngle = try values.decodeIfPresent(Double.self, forKey: .openAngle) ?? 180
        spreadIndex = try values.decodeIfPresent(Int.self, forKey: .spreadIndex) ?? 0
        cameraPreset = try values.decodeIfPresent(BookViewPreset.self, forKey: .cameraPreset) ?? .perspective
        projection = try values.decodeIfPresent(BookCameraProjection.self, forKey: .projection) ?? .perspective
        finish = try values.decodeIfPresent(BookCoverFinish.self, forKey: .finish) ?? .matte
        paper = try values.decodeIfPresent(BookPaperTone.self, forKey: .paper) ?? .offWhite
        environment = try values.decodeIfPresent(BookEnvironmentPreset.self, forKey: .environment) ?? .neutral
        lighting = try values.decodeIfPresent(BookLightingPreset.self, forKey: .lighting) ?? .neutral
        ground = try values.decodeIfPresent(BookGroundPreset.self, forKey: .ground) ?? .gray
        quality = try values.decodeIfPresent(BookRenderQuality.self, forKey: .quality) ?? .balanced
        showProductionMargins = try values.decodeIfPresent(Bool.self, forKey: .showProductionMargins)
        showMeasurements = try values.decodeIfPresent(Bool.self, forKey: .showMeasurements) ?? false
        savedCamera = try values.decodeIfPresent(BookSavedCamera.self, forKey: .savedCamera)
        cameraFieldOfView = try values.decodeIfPresent(Double.self, forKey: .cameraFieldOfView) ?? 34
        environmentIntensity = try values.decodeIfPresent(Double.self, forKey: .environmentIntensity) ?? 1
        lightIntensity = try values.decodeIfPresent(Double.self, forKey: .lightIntensity) ?? 1
        shadowsEnabled = try values.decodeIfPresent(Bool.self, forKey: .shadowsEnabled) ?? true
        exploded = try values.decodeIfPresent(Bool.self, forKey: .exploded) ?? false
        transformMode = try values.decodeIfPresent(BookTransformMode.self, forKey: .transformMode) ?? .navigate
        transformSpace = try values.decodeIfPresent(BookTransformSpace.self, forKey: .transformSpace) ?? .local
        modelTransform = (try values.decodeIfPresent(BookModelTransform.self, forKey: .modelTransform) ?? .identity).normalized
        transformSnapEnabled = try values.decodeIfPresent(Bool.self, forKey: .transformSnapEnabled) ?? false
        moveSnapStep = try values.decodeIfPresent(Double.self, forKey: .moveSnapStep) ?? 0.25
        rotateSnapStep = try values.decodeIfPresent(Double.self, forKey: .rotateSnapStep) ?? 15
        scaleSnapStep = try values.decodeIfPresent(Double.self, forKey: .scaleSnapStep) ?? 0.1
        customLights = try values.decodeIfPresent([BookStudioLight].self, forKey: .customLights) ?? []
        cameraEditorVisible = try values.decodeIfPresent(Bool.self, forKey: .cameraEditorVisible) ?? true
        cameraEditorLocked = try values.decodeIfPresent(Bool.self, forKey: .cameraEditorLocked) ?? false
        lightGuidesVisible = try values.decodeIfPresent(Bool.self, forKey: .lightGuidesVisible) ?? true
        bookEditorVisible = try values.decodeIfPresent(Bool.self, forKey: .bookEditorVisible) ?? true
        bookTransformLocked = try values.decodeIfPresent(Bool.self, forKey: .bookTransformLocked) ?? false
        groundEditorVisible = try values.decodeIfPresent(Bool.self, forKey: .groundEditorVisible) ?? true
        groundEditorLocked = try values.decodeIfPresent(Bool.self, forKey: .groundEditorLocked) ?? false
        outlinerBookExpanded = try values.decodeIfPresent(Bool.self, forKey: .outlinerBookExpanded) ?? true
        outlinerEnvironmentExpanded = try values.decodeIfPresent(Bool.self, forKey: .outlinerEnvironmentExpanded) ?? true
        outlinerLightingExpanded = try values.decodeIfPresent(Bool.self, forKey: .outlinerLightingExpanded) ?? true
        outlinerCameraExpanded = try values.decodeIfPresent(Bool.self, forKey: .outlinerCameraExpanded) ?? true

        let decodedAnimationDuration =
            try values.decodeIfPresent(
                Double.self,
                forKey:
                    .animationDuration
            )
            ?? 6

        animationDuration =
            decodedAnimationDuration.isFinite
            ? min(
                120,
                max(
                    0.25,
                    decodedAnimationDuration
                )
            )
            : 6

        animationFPS =
            min(
                60,
                max(
                    1,
                    try values.decodeIfPresent(
                        Int.self,
                        forKey:
                            .animationFPS
                    )
                    ?? 30
                )
            )

        animationLoop =
            try values.decodeIfPresent(
                Bool.self,
                forKey:
                    .animationLoop
            )
            ?? true

        let decodedPlayhead =
            try values.decodeIfPresent(
                Double.self,
                forKey:
                    .animationPlayhead
            )
            ?? 0

        animationPlayhead =
            decodedPlayhead.isFinite
            ? min(
                animationDuration,
                max(
                    0,
                    decodedPlayhead
                )
            )
            : 0

        turntableEnabled =
            try values.decodeIfPresent(
                Bool.self,
                forKey:
                    .turntableEnabled
            )
            ?? false

        let decodedTurns =
            try values.decodeIfPresent(
                Double.self,
                forKey:
                    .turntableTurns
            )
            ?? 1

        turntableTurns =
            decodedTurns.isFinite
            ? min(
                8,
                max(
                    0.25,
                    decodedTurns
                )
            )
            : 1

        turntableClockwise =
            try values.decodeIfPresent(
                Bool.self,
                forKey:
                    .turntableClockwise
            )
            ?? true

        cameraKeyframes =
            (
                try values.decodeIfPresent(
                    [BookStudioCameraKeyframe].self,
                    forKey:
                        .cameraKeyframes
                )
                ?? []
            )
            .filter {
                $0.time.isFinite
                && $0.camera.isValid
            }
            .map {
                $0.normalized(
                    duration:
                        animationDuration
                )
            }
            .sorted {
                if $0.time == $1.time {
                    return $0.id.uuidString
                        < $1.id.uuidString
                }

                return $0.time
                    < $1.time
            }
    }

    func normalized(pageCount: Int) -> Self {
        var result = self
        result.openAngle = openAngle.isFinite
            ? min(Self.openingAngleRange.upperBound, max(Self.openingAngleRange.lowerBound, openAngle))
            : Self.openingAngleRange.upperBound

        // BOLD WRITER V8B:
        // A legacy workspace can persist an open physical book while
        // retaining the closed-book Front inspection camera. That leaves
        // the viewer outside the covers and creates the rigid-tent view.
        // Normalize that old combination to the existing Reading camera.
        if result.open,
           result.cameraPreset == .front {

            result.cameraPreset =
                .reading

            if result.openAngle < 125 {
                result.openAngle =
                    160
            }
        }
        result.spreadIndex = min(max(0, spreadIndex), max(0, pageCount / 2))
        if result.savedCamera?.isValid == false { result.savedCamera = nil }
        result.cameraFieldOfView = cameraFieldOfView.isFinite ? min(75, max(20, cameraFieldOfView)) : 34
        result.environmentIntensity = environmentIntensity.isFinite ? min(2, max(0, environmentIntensity)) : 1
        result.lightIntensity = lightIntensity.isFinite ? min(2, max(0, lightIntensity)) : 1
        result.modelTransform = modelTransform.normalized
        result.moveSnapStep = moveSnapStep.isFinite ? min(10, max(0.01, moveSnapStep)) : 0.25
        result.rotateSnapStep = rotateSnapStep.isFinite ? min(180, max(0.5, rotateSnapStep)) : 15
        result.scaleSnapStep = scaleSnapStep.isFinite ? min(5, max(0.01, scaleSnapStep)) : 0.1
        result.customLights = customLights.map { $0.normalized }
        return result
    }
}

extension BookStudioPresentation {
    static var restingOpenPreviewDefault:
        BookStudioPresentation
    {
        BookStudioPreset
            .reading
            .apply(
                to:
                    BookStudioPresentation()
            )
    }
}

// BOLD WRITER — one-click physical book inspection views.
// These modify only Studio presentation, preserving the
// manuscript spread, binding, paper stock and artwork.
// BOLD WRITER — preview-only physical binding comparison.
// Never mutates a CoverProject or its originating artwork template.
enum BookBindingPreviewComparison {
    static func resolve(
        original: BookBinding?,
        comparison: BookBinding?,
        fallback: BookBinding
    ) -> BookBinding {
        comparison ?? original ?? fallback
    }

    static func isMismatch(
        original: BookBinding?,
        displayed: BookBinding
    ) -> Bool {
        guard let original else { return false }
        return original != displayed
    }
}

enum BookStudioQuickView: String, CaseIterable, Identifiable {
    case readableSpread = "Readable Spread"
    case inspectThickness = "Inspect Book Thickness"

    var id: String { rawValue }

    func apply(to source: BookStudioPresentation) -> BookStudioPresentation {
        var result = source

        switch self {
        case .readableSpread:
            result.open = true
            result.openAngle = 180
            result.cameraPreset = .reading
            result.cameraFieldOfView = 34

        case .inspectThickness:
            result.open = true
            result.openAngle = 125
            result.cameraPreset = .perspective
            result.cameraFieldOfView = 34
        }

        result.savedCamera = nil
        result.exploded = false

        return result
    }
}

enum BookStudioPreset: String, CaseIterable, Identifiable {
    case front = "Front Cover Product Shot"
    case back = "Back Cover Product Shot"
    case spine = "Spine Detail"
    case reading = "Open Reading Spread"
    case paperback = "Three-Quarter Paperback"
    case hardcover = "Three-Quarter Hardcover"
    case marketplace = "Marketplace White"
    case editorial = "Editorial Dark"
    case library = "Warm Library"
    var id: String { rawValue }

    func apply(to value: BookStudioPresentation) -> BookStudioPresentation {
        var result = value
        switch self {
        case .front: result.open = false; result.cameraPreset = .front
        case .back: result.open = false; result.cameraPreset = .back
        case .spine: result.open = false; result.cameraPreset = .spine
        case .reading: result.open = true; result.openAngle = 160; result.cameraPreset = .reading; result.cameraFieldOfView = 24
        case .paperback: result.open = false; result.binding = .softcover; result.cameraPreset = .perspective
        case .hardcover: result.open = false; result.binding = .hardcover; result.cameraPreset = .perspective
        case .marketplace:
            result.open = false; result.environment = .white; result.lighting = .bright
            result.ground = .white; result.cameraPreset = .front
        case .editorial:
            result.open = false; result.environment = .dark; result.lighting = .dramatic
            result.ground = .dark; result.cameraPreset = .perspective
        case .library:
            result.open = true; result.openAngle = 160; result.environment = .warm
            result.lighting = .library; result.ground = .warm; result.cameraPreset = .reading
        }
        return result
    }
}

enum BookStudioRenderSize: String, CaseIterable, Identifiable {
    case viewport = "Current Viewport"
    case viewport2x = "Viewport 2×"
    case square1200 = "1200 × 1200"
    case portrait1600 = "1600 × 2000"
    case square2000 = "2000 × 2000"
    case custom = "Custom"
    var id: String { rawValue }
    var pixels: CGSize? {
        switch self {
        case .viewport: nil
        case .viewport2x: nil
        case .square1200: CGSize(width: 1200, height: 1200)
        case .portrait1600: CGSize(width: 1600, height: 2000)
        case .square2000: CGSize(width: 2000, height: 2000)
        case .custom: nil
        }
    }
    func resolvedPixels(viewportSize: CGSize, backingScale: CGFloat,
                        customSize: BookStudioRenderDimensions? = nil) -> CGSize? {
        if self == .viewport2x {
            return CGSize(width: max(1, ceil(viewportSize.width * backingScale * 2)),
                          height: max(1, ceil(viewportSize.height * backingScale * 2)))
        }
        if self == .custom { return customSize?.pixels }
        return pixels
    }
}

struct BookStudioRenderDimensions: Equatable {
    let width: Int
    let height: Int

    init?(width: Int, height: Int) {
        guard (256...6000).contains(width), (256...6000).contains(height),
              width * height <= 24_000_000 else { return nil }
        self.width = width
        self.height = height
    }

    var pixels: CGSize { CGSize(width: width, height: height) }
}
