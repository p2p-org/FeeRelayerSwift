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
        .package(url: "https://github.com/ReactiveX/RxSwift.git", from: "6.2.0"),
        .package(url: "https://github.com/RxSwiftCommunity/RxAlamofire.git",
                             from: "6.1.1"),
        .package(url: "https://github.com/p2p-org/solana-swift.git", from: "1.3.8"),
        .package(url: "https://github.com/p2p-org/OrcaSwapSwift.git", from: "1.0.21")
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
