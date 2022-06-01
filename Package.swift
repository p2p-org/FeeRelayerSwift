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
            targets: ["FeeRelayerSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/p2p-org/solana-swift.git", branch: "refactor/pwn-3297"),
        .package(url: "https://github.com/p2p-org/OrcaSwapSwift.git", branch: "refactor/ui-imlementation"),
        .package(url: "https://github.com/Brightify/Cuckoo.git", .upToNextMajor(from: "1.5.0"))
    ],
    targets: [
        .target(
            name: "FeeRelayerSwift",
            dependencies: [
                .product(name: "SolanaSwift", package: "solana-swift"),
                .product(name: "OrcaSwapSwift", package: "OrcaSwapSwift")
            ]
        ),
        .testTarget(
            name: "FeeRelayerSwiftTests",
            dependencies: ["FeeRelayerSwift", "Cuckoo"]),
    ]
)
