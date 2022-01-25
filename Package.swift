// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FeeRelayerSwift",
    platforms: [
        .macOS(.v10_12),
        .iOS(.v10),
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
        .package(url: "https://github.com/ReactiveX/RxSwift.git", from: "6.2.0"),
        .package(url: "https://github.com/RxSwiftCommunity/RxAlamofire.git",
                             from: "6.1.1"),
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
        .package(url: "https://github.com/p2p-org/solana-swift.git", from: "1.1.9"),
        .package(url: "https://github.com/p2p-org/OrcaSwapSwift.git", from: "1.0.2")
    ],
    targets: [
        .target(
            name: "FeeRelayerSwift",
            dependencies: [
                "RxAlamofire",
                .product(name: "SolanaSwift", package: "solana-swift"),
                .product(name: "OrcaSwapSwift", package: "OrcaSwapSwift")
            ]
        ),
        .testTarget(
            name: "FeeRelayerSwiftTests",
            dependencies: ["FeeRelayerSwift",.product(name: "RxBlocking", package: "RxSwift")]),
    ]
)
