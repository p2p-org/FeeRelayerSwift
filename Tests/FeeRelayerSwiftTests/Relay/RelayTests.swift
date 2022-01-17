import XCTest
import RxBlocking
import SolanaSwift
import FeeRelayerSwift
import RxSwift

class RelayTests: XCTestCase {
    private var solanaClient: SolanaSDK!
    private var orcaSwap: OrcaSwapType!
    private var relayService: FeeRelayer.Relay!
    
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
        
        relayService = .init(
            apiClient: FeeRelayer.APIClient(),
            solanaClient: solanaClient,
            accountStorage: accountStorage,
            orcaSwapClient: orcaSwap
        )
        
        _ = try orcaSwap.load().toBlocking().first()
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
        
//        let kuroMint = "2Kc38rfQ49DFaKHQaWbijkE7fcymUMLY5guUiUsDmFfn"
//        let slimMint = "xxxxa1sKNGwFtw2kFn8XauW9xq8hBZ5kVtcSesTT9fW"
//
//        let inputAmount: UInt64 = 1000000 // 1 KURO
        
        // get pools pair
        let poolPairs = try orcaSwap.getTradablePoolsPairs(fromMint: testInfo.fromMint, toMint: testInfo.toMint).toBlocking().first()!
        
        // get best pool pair
        let pools = try orcaSwap.findBestPoolsPairForInputAmount(testInfo.inputAmount, from: poolPairs)!
        
        // request
        let request = try relayService.topUpAndSwap(
            apiVersion: 1,
            sourceToken: .init(
                address: testInfo.sourceAddress,
                mint: testInfo.fromMint
            ),
            destinationTokenMint: testInfo.toMint,
            destinationAddress: testInfo.destinationAddress,
            payingFeeToken: .init(
                address: testInfo.payingTokenAddress,
                mint: testInfo.payingTokenMint
            ),
            pools: pools,
            inputAmount: testInfo.inputAmount,
            slippage: 0.05
        ).toBlocking().first()
    }
}

// MARK: - Helpers
private let testsInfo = try! getDataFromJSONTestResourceFile(fileName: "relay-tests", decodedTo: RelayTestsInfo.self)

class FakeAccountStorage: SolanaSDKAccountStorage, OrcaSwapAccountProvider {
    private let seedPhrase: String
    private let network: SolanaSDK.Network
    
    init(seedPhrase: String, network: SolanaSDK.Network) {
        self.seedPhrase = seedPhrase
        self.network = network
    }
    
    func getAccount() -> OrcaSwap.Account? {
        account
    }
    
    func getNativeWalletAddress() -> OrcaSwap.PublicKey? {
        account?.publicKey
    }
    
    var account: SolanaSDK.Account? {
        try! .init(phrase: seedPhrase.components(separatedBy: " "), network: network, derivablePath: .default)
    }
}

private class FakeNotificationHandler: OrcaSwapSignatureConfirmationHandler {
    func waitForConfirmation(signature: String) -> Completable {
        .empty()
    }
}
