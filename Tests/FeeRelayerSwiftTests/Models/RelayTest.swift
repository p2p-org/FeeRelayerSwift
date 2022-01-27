import Foundation

// MARK: - RelayTests
struct RelayTestsInfo: Codable {
    let splToCreatedSpl: RelaySwapTestInfo?
    let splToNonCreatedSpl: RelaySwapTestInfo?
    let usdtTransfer: RelayTransferTestInfo?
    let usdtBackTransfer: RelayTransferTestInfo?
    let splToSOL: RelaySwapTestInfo?
    let relaySendNativeSOL: RelayTransferNativeSOLTestInfo?
}

// MARK: - SplToCreatedSpl
struct RelaySwapTestInfo: Codable {
    let endpoint: String
    let endpointAdditionalQuery, seedPhrase, fromMint, toMint: String
    let sourceAddress, payingTokenMint, payingTokenAddress: String
    let destinationAddress: String?
    let inputAmount: UInt64
    let slippage: Double
}

struct RelayTransferTestInfo: Codable {
    let endpoint: String
    let endpointAdditionalQuery, seedPhrase, mint: String
    let sourceTokenAddress, destinationAddress: String
    let inputAmount, expectedFee: UInt64
    let payingTokenAddress: String
    let payingTokenMint: String
}

struct RelayTransferNativeSOLTestInfo: Codable {
    let endpoint: String
    let endpointAdditionalQuery, seedPhrase, destination: String
    let inputAmount, expectedFee: UInt64
    let payingTokenAddress, payingTokenMint: String
}
