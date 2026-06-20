// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MundialStreams",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MundialStreams", targets: ["MundialStreams"])
    ],
    targets: [
        .executableTarget(
            name: "MundialStreams",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
