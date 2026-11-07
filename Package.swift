// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BOLDWriter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BOLDWriter", targets: ["BOLDWriter"])
    ],
    targets: [
        .executableTarget(
            name: "BOLDWriter",
            dependencies: ["LAMEEncoder"],
            path: "Sources/BOLDWriter",
            exclude: ["AudioProduction/LAME"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "LAMEEncoder",
            path: "Sources/BOLDWriter/AudioProduction/LAME",
            publicHeadersPath: "include",
            cSettings: [
                .define("HAVE_CONFIG_H"),
                .headerSearchPath("include"),
                .headerSearchPath("libmp3lame")
            ]
        ),
        .testTarget(
            name: "BOLDWriterTests",
            dependencies: ["BOLDWriter"],
            path: "Tests/BOLDWriterTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
