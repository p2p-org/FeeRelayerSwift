import XCTest
import SolanaSwift
@testable import FeeRelayerSwift
import OrcaSwapSwift

class RelaySwapTests: RelayTests {
    // MARK: - DirectSwap
    /// Swap from SOL to SPL
    func testTopUpAndDirectSwapFromSOL() async throws {
        try await swap(testInfo: testsInfo.solToSPL!, isTransitiveSwap: true)
    }
    
    /// Swap from SPL to SOL
    func testTopUpAndDirectSwapToSOL() async throws {
        try await swap(testInfo: testsInfo.splToSOL!, isTransitiveSwap: false)
    }
    
    /// Swap from SPL to SPL
    func testTopUpAndDirectSwapToCreatedToken() async throws {
        try await swap(testInfo: testsInfo.splToCreatedSpl!, isTransitiveSwap: false)
    }
    
    func testTopUpAndDirectSwapToNonCreatedToken() async throws {
        try await swap(testInfo: testsInfo.splToNonCreatedSpl!, isTransitiveSwap: false)
    }
    
    // MARK: - TransitiveSwap
    func testTopUpAndTransitiveSwapToSOL() async throws {
        try await swap(testInfo: testsInfo.splToSOL!, isTransitiveSwap: true)
    }
    
    func testTopUpAndTransitiveSwapToCreatedToken() async throws {
        try await swap(testInfo: testsInfo.splToCreatedSpl!, isTransitiveSwap: true)
    }
    
    func testTopUpAndTransitiveSwapToNonCreatedToken() async throws {
        try await swap(testInfo: testsInfo.splToNonCreatedSpl!, isTransitiveSwap: true)
    }
    
    // MARK: - Helpers
    private func prepareTransaction(testInfo: RelaySwapTestInfo, isTransitiveSwap: Bool?) async throws -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
        // load test
        try await loadTest(testInfo)
        
        // get pools pair
        let poolPairs = try await orcaSwap.getTradablePoolsPairs(fromMint: testInfo.fromMint, toMint: testInfo.toMint)
        
        // get best pool pair
        let pools: PoolsPair
        if let isTransitiveSwap = isTransitiveSwap {
            pools = poolPairs.last(where: {$0.count == (isTransitiveSwap ? 2: 1)})!
        } else {
            pools = try orcaSwap.findBestPoolsPairForInputAmount(testInfo.inputAmount, from: poolPairs)!
        }
        
        
        
        return try feeRelayer.prepareSwapTransaction(
            sourceToken: .init(address: testInfo.sourceAddress, mint: testInfo.fromMint),
            destinationTokenMint: testInfo.toMint,
            destinationAddress: testInfo.destinationAddress,
            payingFeeToken: .init(address: testInfo.payingTokenAddress, mint: testInfo.payingTokenMint),
            swapPools: pools,
            inputAmount: testInfo.inputAmount,
            slippage: testInfo.slippage
        )
    }
    
    private func swap(testInfo: RelaySwapTestInfo, isTransitiveSwap: Bool?) async throws {
        let txs = try await prepareTransaction(testInfo: testInfo, isTransitiveSwap: isTransitiveSwap)
  
        // send to relay service
        let signatures = try await feeRelayer.topUpAndRelayTransactions(
            preparedTransactions: txs.transactions,
            payingFeeToken: .init(address: testInfo.payingTokenAddress, mint: testInfo.payingTokenMint),
            additionalPaybackFee: txs.additionalPaybackFee
        )
        
        print(signatures)
        XCTAssertTrue(signatures.count > 0)
    }
}
