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
    
    override func tearDownWithError() throws {
        solanaClient = nil
        orcaSwap = nil
        relayService = nil
    }
    
    // MARK: - TopUpAndSwap
    func testTopUpAndSwapToCreatedToken() throws {
        try swap(testInfo: testsInfo.splToCreatedSpl!)
    }
    
    func testTopUpAndSwapToNonCreatedToken() throws {
        try swap(testInfo: testsInfo.splToNonCreatedSpl!)
    }
    
    func testUSDTTransfer() throws {
        try runTransfer(testsInfo.usdtTransfer!)
    }
    
    func testUSDTBackTransfer() throws {
        try runTransfer(testsInfo.usdtBackTransfer!)
    }
    
    // MARK: - Helpers
    private func swap(testInfo: RelaySwapTestInfo) throws {
        try loadWithSwapTest(testInfo)
        
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
    
    private func loadWithSwapTest(_ relayTest: RelaySwapTestInfo) throws {
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
    
    func runTransfer(_ relayTest: RelayTransferTestInfo) throws {
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
        
        let payingToken = FeeRelayer.Relay.TokenInfo(
            address: relayTest.payingTokenAddress,
            mint: relayTest.payingTokenMint
        )
        
        let signature = try relayService.topUpAndSend(
            sourceToken: FeeRelayer.Relay.TokenInfo(
                address: relayTest.sourceTokenAddress,
                mint: relayTest.mint
            ),
            destinationAddress: relayTest.destinationAddress,
            tokenMint: relayTest.mint,
            inputAmount: relayTest.inputAmount,
            payingFeeToken: payingToken
        ).toBlocking().first()
        print(signature ?? "Nothing")
    }
}
