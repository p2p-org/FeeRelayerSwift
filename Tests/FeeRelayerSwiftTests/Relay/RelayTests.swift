import XCTest
import RxBlocking
import SolanaSwift
@testable import FeeRelayerSwift
import RxSwift
import OrcaSwapSwift

class RelayTests: XCTestCase {
    let testsInfo = try! getDataFromJSONTestResourceFile(fileName: "relay-tests", decodedTo: RelayTestsInfo.self)
    
    var solanaClient: SolanaSDK!
    var orcaSwap: OrcaSwapType!
    var relayService: FeeRelayer.Relay!
    
    override func tearDownWithError() throws {
        solanaClient = nil
        orcaSwap = nil
        relayService = nil
    }
    
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
    
    @discardableResult
    func loadTest(_ relayTest: RelayTestType) throws -> FeeRelayerAPIClientType {
        let network = SolanaSDK.Network.mainnetBeta
        let accountStorage = FakeAccountStorage(seedPhrase: relayTest.seedPhrase, network: network)
        let endpoint = SolanaSDK.APIEndPoint(address: relayTest.endpoint, network: network, additionalQuery: relayTest.endpointAdditionalQuery)
        solanaClient = SolanaSDK(endpoint: endpoint, accountStorage: accountStorage)
        orcaSwap = OrcaSwap(
            apiClient: OrcaSwap.APIClient(network: network.cluster),
            solanaClient: solanaClient,
            accountProvider: accountStorage,
            notificationHandler: FakeNotificationHandler()
        )
        
        let apiClient = FeeRelayer.APIClient(version: 1)
        relayService = try FeeRelayer.Relay(
            apiClient: apiClient,
            solanaClient: solanaClient,
            accountStorage: accountStorage,
            orcaSwapClient: orcaSwap
        )
        
        _ = try orcaSwap.load().toBlocking().first()
        _ = try relayService.load().toBlocking().first()
        
        return apiClient
    }
}
