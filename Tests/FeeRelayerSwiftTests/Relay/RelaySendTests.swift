import XCTest
import SolanaSwift
@testable import FeeRelayerSwift
import OrcaSwapSwift

class RelaySendTests: RelayTests {
    
    var account: SolanaAccountStorage!
    let feeRelayerAPIClient = MockFakeFeeRelayerAPIClient()
    lazy var solanaAPIClient = MockFakeJSONRPCAPIClient(endpoint: self.endpoint)
    let orcaSwapAPIClient = MockFakeOrcaSwapAPIClient(configsProvider: MockConfigsProvider())
    
    override func setUp() async throws {
        account = FakeAccountStorage(
            seedPhrase: "miracle pizza supply useful steak border same again youth silver access hundred",
            network: .mainnetBeta
        )
    }
    
//    func testRelaySendNativeSOL() async throws {
//        try await runRelaySendNativeSOL(testsInfo.relaySendNativeSOL!)
//    }

//    func testUSDTTransfer() async throws {
//        try await runRelaySendSPLToken(testsInfo.usdtTransfer!)
//    }
//
//    func testUSDTBackTransfer() async throws {
//        try await runRelaySendSPLToken(testsInfo.usdtBackTransfer!)
//    }
//
//    func testUSDTTransferToNonCreatedToken() async throws {
//        try await runRelaySendSPLToken(testsInfo.usdtTransferToNonCreatedToken!)
//    }

    // MARK: - Helpers
    private func runRelaySendNativeSOL(_ test: RelayTransferNativeSOLTestInfo) async throws {
        let feeRelayerAPIClient = try loadTest(test)
        let payingToken = TokenAccount(
            address: try! PublicKey(string: test.payingTokenAddress),
            mint: try! PublicKey(string: test.payingTokenMint)
        )
        
        let apiClient = SolanaAPIClientMock(endpoint: endpoint)
//        let feePayer = try await feeRelayerAPIClient.getFeePayerPubkey()

        let blockchain = BlockchainClient(apiClient: apiClient)
        
        let tx = try await blockchain.prepareSendingNativeSOL(
            from: account.account!,
            to: test.destination,
            amount: 1,
            feePayer: account.account!.publicKey
        )

        XCTAssertEqual(tx.expectedFee.total, test.expectedFee)
        
        let context = try await FeeRelayerContextManagerImpl(
            accountStorage: account,
            solanaAPIClient: solanaAPIClient,
            feeRelayerAPIClient: feeRelayerAPIClient
        ).getCurrentContext()
        
        let signature = try await relayService.topUpAndRelayTransaction(
            context,
            tx,
            fee: payingToken,
            config:  .init(operationType: .topUp)
        )

//        let signature = try await relayService.topUpAndRelayTransaction(
//            tx,
//            fee: payingToken,
//            config: .init(operationType: .topUp)
//        )
        print(signature ?? "Nothing")
        
    }

//    private func runRelaySendSPLToken(_ test: RelayTransferTestInfo) async throws {
//        let feeRelayerAPIClient = try loadTest(test)
//
//        let payingToken = FeeRelayer.Relay.TokenInfo(
//            address: test.payingTokenAddress,
//            mint: test.payingTokenMint
//        )
//
//        let feePayer = try await feeRelayerAPIClient.getFeePayerPubkey()//.toBlocking().first()!
//
//        let preparedTransaction = try solanaClient.prepareSendingSPLTokens(
//            mintAddress: test.mint,
//            decimals: 6,
//            from: test.sourceTokenAddress,
//            to: test.destinationAddress,
//            amount: 100,
//            feePayer: try PublicKey(string: feePayer),
//            transferChecked: true
//        ).toBlocking().first()!.preparedTransaction
//
//        XCTAssertEqual(preparedTransaction.expectedFee.total, test.expectedFee)
//
//        let signature = try relayService.topUpAndRelayTransaction(
//            preparedTransaction: preparedTransaction,
//            payingFeeToken: payingToken
//        ).toBlocking().first()
//        print(signature ?? "Nothing")
//    }
}


extension PublicKey {
    init?(stringLiteral value: String) {
        try? self.init(string: value)
    }
}


//swap calculator,
