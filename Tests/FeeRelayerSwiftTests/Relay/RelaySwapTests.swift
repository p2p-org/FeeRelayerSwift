//import XCTest
//import RxBlocking
//import SolanaSwift
//@testable import FeeRelayerSwift
//import OrcaSwapSwift
//
//class RelaySwapTests: RelayTests {
//    // MARK: - DirectSwap
//    /// Swap from SOL to SPL
//    func testTopUpAndDirectSwapFromSOL() throws {
//        try swap(testInfo: testsInfo.solToSPL!, isTransitiveSwap: true)
//    }
//
//    /// Swap from SPL to SOL
//    func testTopUpAndDirectSwapToSOL() throws {
//        try swap(testInfo: testsInfo.splToSOL!, isTransitiveSwap: false)
//    }
//
//    /// Swap from SPL to SPL
//    func testTopUpAndDirectSwapToCreatedToken() throws {
//        try swap(testInfo: testsInfo.splToCreatedSpl!, isTransitiveSwap: false)
//    }
//
//    func testTopUpAndDirectSwapToNonCreatedToken() throws {
//        try swap(testInfo: testsInfo.splToNonCreatedSpl!, isTransitiveSwap: false)
//    }
//
//    // MARK: - TransitiveSwap
//    func testTopUpAndTransitiveSwapToSOL() throws {
//        try swap(testInfo: testsInfo.splToSOL!, isTransitiveSwap: true)
//    }
//
//    func testTopUpAndTransitiveSwapToCreatedToken() throws {
//        try swap(testInfo: testsInfo.splToCreatedSpl!, isTransitiveSwap: true)
//    }
//
//    func testTopUpAndTransitiveSwapToNonCreatedToken() throws {
//        try swap(testInfo: testsInfo.splToNonCreatedSpl!, isTransitiveSwap: true)
//    }
//
//    // MARK: - Helpers
//    private func prepareTransaction(testInfo: RelaySwapTestInfo, isTransitiveSwap: Bool?) throws -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
//        try loadTest(testInfo)
//        let solanaAPIClient = SolanaAPIClientMock(endpoint: .init(address: <#T##String#>, network: <#T##Network#>))
//        let orcaSwap = OrcaSwap(apiClient: OrcaSwapSwift.APIClient(configsProvider: MockConfigsProvider()),
//                                solanaClient: solanaAPIClient,
//                                blockchainClient: BlockchainClient(apiClient: <#T##SolanaAPIClient#>),
//                                accountStorage: <#T##SolanaAccountStorage#>)
//        // get pools pair
//        let poolPairs = try await getTradablePoolsPairs(fromMint: testInfo.fromMint, toMint: testInfo.toMint)
//
//        // get best pool pair
//        let pools: PoolsPair
//        if let isTransitiveSwap = isTransitiveSwap {
//            pools = poolPairs.last(where: {$0.count == (isTransitiveSwap ? 2: 1)})!
//        } else {
//            pools = try await findBestPoolsPairForInputAmount(testInfo.inputAmount, from: poolPairs)!
//        }
//
//        return try relayService.prepareSwapTransaction(
//            sourceToken: .init(address: testInfo.sourceAddress, mint: testInfo.fromMint),
//            destinationTokenMint: testInfo.toMint,
//            destinationAddress: testInfo.destinationAddress,
//            payingFeeToken: .init(address: testInfo.payingTokenAddress, mint: testInfo.payingTokenMint),
//            swapPools: pools,
//            inputAmount: testInfo.inputAmount,
//            slippage: testInfo.slippage
//        ).toBlocking().first()!
//    }
//
//    private func swap(testInfo: RelaySwapTestInfo, isTransitiveSwap: Bool?) throws {
//        let txs = try prepareTransaction(testInfo: testInfo, isTransitiveSwap: isTransitiveSwap)
//
//        // send to relay service
//        let signatures = try relayService.topUpAndRelayTransactions(
//            preparedTransactions: txs.transactions,
//            payingFeeToken: .init(address: testInfo.payingTokenAddress, mint: testInfo.payingTokenMint),
//            additionalPaybackFee: txs.additionalPaybackFee
//        ).toBlocking().first()!
//
//        print(signatures)
//        XCTAssertTrue(signatures.count > 0)
//    }
//}
//
import Foundation
import OrcaSwapSwift

class MockConfigsProvider: OrcaSwapConfigsProvider {
    func getData(reload: Bool) async throws -> Data {
        let thisSourceFile = URL(fileURLWithPath: #file)
        let thisDirectory = thisSourceFile.deletingLastPathComponent()
        let resourceURL = thisDirectory.appendingPathComponent("../../Resources/orcaconfigs-mainnet.json")
        let data = try! Data(contentsOf: resourceURL)
        return data
    }
}
