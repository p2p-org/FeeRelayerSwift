import XCTest
import RxBlocking
import SolanaSwift
@testable import FeeRelayerSwift
import RxSwift
import OrcaSwapSwift

class RelaySwapTests: RelayTests {
    /// Swap from SOL to SPL
    func testTopUpAndSwapFromSOL() throws {
        try swap(testInfo: testsInfo.solToSPL!)
    }
    
    /// Swap from SPL to SOL
    func testTopUpAndSwapToSOL() throws {
        try swap(testInfo: testsInfo.splToSOL!)
    }
    
    /// Swap from SPL to SPL
    func testTopUpAndSwapToCreatedToken() throws {
        try swap(testInfo: testsInfo.splToCreatedSpl!)
    }
    
    func testTopUpAndSwapToNonCreatedToken() throws {
        try swap(testInfo: testsInfo.splToNonCreatedSpl!)
    }
    
    // MARK: - Helpers
    private func swap(testInfo: RelaySwapTestInfo) throws {
        try loadTest(testInfo)
        
        // get pools pair
        let poolPairs = try orcaSwap.getTradablePoolsPairs(fromMint: testInfo.fromMint, toMint: testInfo.toMint).toBlocking().first()!
        
        // get best pool pair
        let pools = try orcaSwap.findBestPoolsPairForInputAmount(testInfo.inputAmount, from: poolPairs)!
        
        // request
        let sourceToken = FeeRelayer.Relay.TokenInfo(
            address: testInfo.sourceAddress,
            mint: testInfo.fromMint
        )
        
        let payingToken = FeeRelayer.Relay.TokenInfo(
            address: testInfo.payingTokenAddress,
            mint: testInfo.payingTokenMint
        )
        
        // calculate fee and needed topup amount
        let feeAndTopUpAmount = try relayService.calculateFeeAndNeededTopUpAmountForSwapping(
            sourceToken: sourceToken,
            destinationTokenMint: testInfo.toMint,
            destinationAddress: testInfo.destinationAddress,
            payingFeeToken: payingToken,
            swapPools: pools
        ).toBlocking().first()!
        let fee = feeAndTopUpAmount.feeInSOL?.total ?? 0
        let topUpAmount = feeAndTopUpAmount.topUpAmountInSOL ?? 0
        
        // get relay account balance
        let relayAccountBalance = try relayService.getRelayAccountStatus(reuseCache: false).toBlocking().first()?.balance ?? 0
        
        if fee > relayAccountBalance {
            XCTAssertEqual(topUpAmount, fee - relayAccountBalance)
        } else {
            XCTAssertEqual(topUpAmount, 0)
        }
        
        // prepare transaction
        let preparedTransaction = try relayService.prepareSwapTransaction(
            sourceToken: sourceToken,
            destinationTokenMint: testInfo.toMint,
            destinationAddress: testInfo.destinationAddress,
            payingFeeToken: payingToken,
            swapPools: pools,
            inputAmount: testInfo.inputAmount,
            slippage: 0.05
        ).toBlocking().first()!
        
        // send to relay service
        let signatures = try relayService.topUpAndRelayTransaction(
            preparedTransaction: preparedTransaction,
            payingFeeToken: payingToken
        ).toBlocking().first()!
        
        print(signatures)
        XCTAssertTrue(signatures.count > 0)
    }
}
