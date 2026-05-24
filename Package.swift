// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexUsage",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexUsage", targets: ["CodexUsageApp"]),
        .library(name: "CodexUsageCore", targets: ["CodexUsageCore"])
    ],
    targets: [
        .target(name: "CodexUsageCore"),
        .executableTarget(
            name: "CodexUsageApp",
            dependencies: ["CodexUsageCore"]
        ),
        .testTarget(
            name: "CodexUsageCoreTests",
            dependencies: ["CodexUsageCore"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
