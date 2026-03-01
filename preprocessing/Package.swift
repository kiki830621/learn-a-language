// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Preprocessing",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "pipeline", targets: ["PipelineCLI"]),
        .library(name: "Pipeline", targets: ["Pipeline"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/vapor/postgres-nio", from: "1.21.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CMeCab",
            pkgConfig: nil,
            providers: [.brew(["mecab"])]
        ),
        .target(
            name: "Pipeline",
            dependencies: [
                "CMeCab",
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ],
            swiftSettings: [
                .unsafeFlags(["-I/opt/homebrew/include"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib", "-lmecab"]),
            ]
        ),
        .executableTarget(
            name: "PipelineCLI",
            dependencies: [
                "Pipeline",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "PipelineTests",
            dependencies: ["Pipeline"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
