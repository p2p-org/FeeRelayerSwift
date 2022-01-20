import Foundation

// MARK: - RelayTests
struct RelayTestsInfo: Codable {
    let splToCreatedSpl: RelaySwapTestInfo?
    let splToNonCreatedSpl: RelaySwapTestInfo?
    let splToSOL: RelaySwapTestInfo?
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
