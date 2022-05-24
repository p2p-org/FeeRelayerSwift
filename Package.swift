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
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", .upToNextMajor(from: "1.4.1")),
        .package(url: "https://github.com/bigearsenal/BufferLayoutSwift.git", .upToNextMajor(from: "0.9.0")),
        .package(name: "secp256k1", url: "https://github.com/Boilertalk/secp256k1.swift.git", from: "0.1.0"),
        .package(name: "TweetNacl", url: "https://github.com/bitmark-inc/tweetnacl-swiftwrap.git", from: "1.0.2"),
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
        .package(url: "https://github.com/p2p-org/solana-swift.git", branch: "refactor/pwn-3297"),
        .package(url: "https://github.com/p2p-org/OrcaSwapSwift.git", branch: "swap-unit-tests")
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
            dependencies: ["FeeRelayerSwift"]),
    ]
)
