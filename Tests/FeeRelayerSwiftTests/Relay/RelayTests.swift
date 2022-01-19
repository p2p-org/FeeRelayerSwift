import XCTest
import RxBlocking
import SolanaSwift
@testable import FeeRelayerSwift
import RxSwift

class RelayTests: XCTestCase {
    private let testsInfo = try! getDataFromJSONTestResourceFile(fileName: "relay-tests", decodedTo: RelayTestsInfo.self)
    
    private var solanaClient: SolanaSDK!
    private var orcaSwap: OrcaSwapType!
    private var relayService: FeeRelayerRelayType!
    
    private func loadWithTest(_ relayTest: RelayTestInfo) throws {
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
        
        relayService = try FeeRelayer.Relay(
            apiClient: FeeRelayer.APIClient(version: 1),
            solanaClient: solanaClient,
            accountStorage: accountStorage,
            orcaSwapClient: orcaSwap
        )
        
        _ = try orcaSwap.load().toBlocking().first()
        _ = try relayService.load().toBlocking().first()
    }

    override func tearDownWithError() throws {
        solanaClient = nil
        orcaSwap = nil
        relayService = nil
    }
    
    // MARK: - TopUpAndSwap
    func testTopUpAndSwapToCreatedToken() throws {
        // load test
        let testInfo = testsInfo.splToCreatedSpl
        try loadWithTest(testInfo)
        
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
        let fee = feeAndTopUpAmount.fee ?? 0
        let topUpAmount = feeAndTopUpAmount.topUpAmount ?? 0
        
        // get relay account balance
        let relayAccountBalance = try relayService.getRelayAccountStatus(reuseCache: false).toBlocking().first()?.balance ?? 0
        
        if fee > relayAccountBalance {
            XCTAssertEqual(topUpAmount, fee - relayAccountBalance)
        } else {
            XCTAssertEqual(topUpAmount, 0)
        }
        
        // send params
        let signatures = try relayService.topUpAndSwap(
            sourceToken: sourceToken,
            destinationTokenMint: testInfo.toMint,
            destinationAddress: testInfo.destinationAddress,
            payingFeeToken: payingToken,
            swapPools: pools,
            inputAmount: testInfo.inputAmount,
            slippage: 0.05
        ).toBlocking().first()!
        
        print(signatures)
        XCTAssertTrue(signatures.count > 0)
        
    }
}
