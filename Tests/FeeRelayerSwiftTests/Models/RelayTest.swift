import Foundation

// MARK: - RelayTests
struct RelayTestsInfo: Codable {
    let splToCreatedSpl: RelayTestInfo
}

// MARK: - SplToCreatedSpl
struct RelayTestInfo: Codable {
    let endpoint: String
    let endpointAdditionalQuery, seedPhrase, fromMint, toMint: String
    let sourceAddress, destinationAddress, payingTokenMint, payingTokenAddress: String
    let inputAmount: UInt64
    let slippage: Double
}
