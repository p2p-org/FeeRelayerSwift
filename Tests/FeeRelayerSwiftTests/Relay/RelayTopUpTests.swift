import Foundation
import XCTest
@testable import FeeRelayerSwift

class RelayTopUpTests: RelayTests {
    // MARK: - TopUp
    func testTopUp() throws {
        try topUp(testInfo: testsInfo.topUp!)
    }
    
    // MARK: - Helpers
    private func topUp(testInfo: RelayTopUpTest) throws {
        try loadTest(testInfo)

        // paying token
        let payingToken = FeeRelayer.Relay.TokenInfo(
            address: testInfo.payingTokenAddress,
            mint: testInfo.payingTokenMint
        )

        // prepare params
        let relayAccountStatus = try relayService.getRelayAccountStatus().toBlocking().first()!
        let freeTransactionFeeLimit = try relayService.getFreeTransactionFeeLimit().toBlocking().first()!
        
        let params = try relayService.prepareForTopUp(
            targetAmount: testInfo.amount,
            payingFeeToken: payingToken,
            relayAccountStatus: relayAccountStatus,
            freeTransactionFeeLimit: freeTransactionFeeLimit,
            checkIfBalanceHaveEnoughAmount: false,
            forceUsingTransitiveSwap: true
        ).toBlocking().first()!
        
        let signatures = try relayService.topUp(
            needsCreateUserRelayAddress: relayAccountStatus == .notYetCreated,
            sourceToken: payingToken,
            targetAmount: params!.amount,
            topUpPools: params!.poolsPair,
            expectedFee: params!.expectedFee
        ).toBlocking().first()!

        XCTAssertTrue(signatures.count > 0)
    }
}
