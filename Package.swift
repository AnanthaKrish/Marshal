// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Marshal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Marshal", targets: ["Marshal"]),
        .executable(name: "marshal-cli", targets: ["MarshalCLI"]),
        .library(name: "MarshalCore", targets: ["MarshalCore"])
    ],
    targets: [
        .target(
            name: "MarshalCore",
            path: "Sources/MarshalCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "Marshal",
            dependencies: ["MarshalCore"],
            path: "Sources/Marshal",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "MarshalCLI",
            dependencies: ["MarshalCore"],
            path: "Sources/MarshalCLI"
        ),
        .testTarget(
            name: "MarshalTests",
            dependencies: ["Marshal", "MarshalCore"],
            path: "Tests/MarshalTests"
        ),
        .testTarget(
            name: "MarshalCoreTests",
            dependencies: ["MarshalCore"],
            path: "Tests/MarshalCoreTests"
        )
    ]
)
