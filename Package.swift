// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FeeRelayerSwift",
    platforms: [
        .macOS(.v12),
        .iOS(.v13),
        .tvOS(.v10),
        .watchOS(.v3)
    ],
    products: [
        .library(
            name: "FeeRelayerSwift",
            targets: ["FeeRelayerSwift"]
        ),
    .executable(
            name: "FeeRelayerCLI",
            targets: ["FeeRelayerCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/p2p-org/solana-swift.git", branch: "feature/universal-add-signature"),
        .package(url: "https://github.com/p2p-org/OrcaSwapSwift.git", from: "2.1.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.1.4"),
    ],
    targets: [
        .executableTarget(
            name: "FeeRelayerCLI",
            dependencies: [
                "FeeRelayerSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "FeeRelayerSwift",
            dependencies: [
                .product(name: "SolanaSwift", package: "solana-swift"),
                .product(name: "OrcaSwapSwift", package: "OrcaSwapSwift")
            ]
        ),
        .testTarget(
            name: "FeeRelayerSwiftTests",
            dependencies: ["FeeRelayerSwift"]),
    ]
)
