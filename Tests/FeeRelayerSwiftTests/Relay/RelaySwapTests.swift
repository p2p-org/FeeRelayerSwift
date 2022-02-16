import XCTest
import RxBlocking
import SolanaSwift
@testable import FeeRelayerSwift
import RxSwift
import OrcaSwapSwift

class RelaySwapTests: RelayTests {
    // MARK: - Fee calculator
    func testFeeCalculatorSwapToSOL() throws {
        let swapInfo = try loadSwap(testInfo: testsInfo.splToSOL!)
        
        let swapTransactions = swapInfo.0
        let payingToken = swapInfo.1
        let feePayer = swapInfo.2
        
        let fees = try relayService.calculateFees(swapInfo.0)
        
        print(fees)
        
    }
    
    // MARK: - Swap action
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
    private func loadSwap(testInfo: RelaySwapTestInfo) throws -> ([OrcaSwap.PreparedSwapTransaction], FeeRelayer.Relay.TokenInfo, SolanaSDK.PublicKey?) {
        try loadTest(testInfo)
        
        // get pools pair
        let poolPairs = try orcaSwap.getTradablePoolsPairs(fromMint: testInfo.fromMint, toMint: testInfo.toMint).toBlocking().first()!
        
        // get best pool pair
        let pools = try orcaSwap.findBestPoolsPairForInputAmount(testInfo.inputAmount, from: poolPairs)!
        
        // get fee payer
        let feePayer = try relayService.apiClient.getFeePayerPubkey().map {try SolanaSDK.PublicKey(string: $0)}.toBlocking().first()!
        
        // prepare for swapping
        let swapTransactions = try orcaSwap
            .prepareForSwapping(
                fromWalletPubkey: testInfo.sourceAddress,
                toWalletPubkey: testInfo.destinationAddress,
                bestPoolsPair: pools,
                amount: testInfo.inputAmount.convertToBalance(decimals: pools[0].getTokenADecimals()),
                feePayer: feePayer,
                slippage: testInfo.slippage
            )
            .toBlocking()
            .first()!
            .0
        
        let payingToken = FeeRelayer.Relay.TokenInfo(
            address: testInfo.payingTokenAddress,
            mint: testInfo.payingTokenMint
        )
        return (swapTransactions, payingToken, feePayer)
    }
    
    private func swap(testInfo: RelaySwapTestInfo) throws {
        let swapInfo = try loadSwap(testInfo: testInfo)
        
        let swapTransactions = swapInfo.0
        let payingToken = swapInfo.1
        let feePayer = swapInfo.2
        
        // send
        let signatures = try relayService.topUpAndSwap(
            swapTransactions,
            feePayer: feePayer,
            payingFeeToken: payingToken
        )
            .toBlocking()
            .first()!
        
        
        
//        // calculate fee and needed topup amount
//        let feeAndTopUpAmount = try relayService.calculateFeeAndNeededTopUpAmountForSwapping(
//            sourceToken: sourceToken,
//            destinationTokenMint: testInfo.toMint,
//            destinationAddress: testInfo.destinationAddress,
//            payingFeeToken: payingToken,
//            swapPools: pools
//        ).toBlocking().first()!
//        let fee = feeAndTopUpAmount.feeInSOL?.total ?? 0
//        let topUpAmount = feeAndTopUpAmount.topUpAmountInSOL ?? 0
//
//        // get relay account balance
//        let relayAccountBalance = try relayService.getRelayAccountStatus(reuseCache: false).toBlocking().first()?.balance ?? 0
//
//        if fee > relayAccountBalance {
//            XCTAssertEqual(topUpAmount, fee - relayAccountBalance)
//        } else {
//            XCTAssertEqual(topUpAmount, 0)
//        }
//
//        // prepare transaction
//        let preparedTransaction = try relayService.prepareSwapTransaction(
//            sourceToken: sourceToken,
//            destinationTokenMint: testInfo.toMint,
//            destinationAddress: testInfo.destinationAddress,
//            payingFeeToken: payingToken,
//            swapPools: pools,
//            inputAmount: testInfo.inputAmount,
//            slippage: 0.05
//        ).toBlocking().first()!
//
//        // send to relay service
//        let signatures = try relayService.topUpAndRelayTransaction(
//            preparedTransaction: preparedTransaction,
//            payingFeeToken: payingToken
//        ).toBlocking().first()!
        
        print(signatures)
        XCTAssertTrue(signatures.count > 0)
    }
}
