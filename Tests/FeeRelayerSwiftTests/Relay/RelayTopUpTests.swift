import Foundation
import XCTest
@testable import FeeRelayerSwift
import SolanaSwift

class RelayTopUpTests: RelayTests {
    // MARK: - TopUp
    func testTopUp() async throws {
        try await topUp(testInfo: testsInfo.topUp!)
    }
    
    // MARK: - Helpers
    private func topUp(testInfo: RelayTopUpTest) async throws {
        try loadTest(testInfo)

        // paying token
        let payingToken = TokenAccount(
            address: try! PublicKey(string: testInfo.payingTokenAddress),
            mint: try! PublicKey(string: testInfo.payingTokenMint)
        )
        
        // prepare params
        let solanaAPIClient = JSONRPCAPIClient(endpoint: endpoint)
        let feeRelayAPIClient = FeeRelayerSwift.APIClient(httpClient: FeeRelayerHTTPClient(), version: 1)
        let accountStorage = FakeAccountStorage(seedPhrase: testInfo.seedPhrase, network: Network.mainnetBeta)
        
        let contextManager = try FeeRelayerContextManagerImpl(
            accountStorage: accountStorage,
            solanaAPIClient: solanaAPIClient,
            feeRelayerAPIClient: feeRelayAPIClient
        )
        try await contextManager.update()
        let ctx = try await contextManager.getCurrentContext()
        
        let params = try await relayService.prepareForTopUp(
            ctx,
            topUpAmount: testInfo.amount,
            payingFeeToken: payingToken,
            forceUsingTransitiveSwap: true
        )
        
        let signatures = try await relayService.topUp(
            ctx,
            needsCreateUserRelayAddress: ctx.relayAccountStatus == .notYetCreated,
            sourceToken: payingToken,
            targetAmount: params!.amount,
            topUpPools: params!.poolsPair,
            expectedFee: params!.expectedFee
        )
        print(signatures)
        XCTAssertTrue(signatures.count > 0)
        
//        let params = try relayService.prepareForTopUp(
//            targetAmount: testInfo.amount,
//            payingFeeToken: payingToken,
//            relayAccountStatus: relayAccountStatus,
//            freeTransactionFeeLimit: freeTransactionFeeLimit,
//            checkIfBalanceHaveEnoughAmount: false,
//            forceUsingTransitiveSwap: true
//        )//.toBlocking().first()!
        
//        let signatures = try relayService.topUp(
//            needsCreateUserRelayAddress: relayAccountStatus == .notYetCreated,
//            sourceToken: payingToken,
//            targetAmount: params!.amount,
//            topUpPools: params!.poolsPair,
//            expectedFee: params!.expectedFee
//        )

//        XCTAssertTrue(signatures.count > 0)
    }
}


// topUpAndRelay -- integartion
// check and topup -- integration
// prepare for top up
