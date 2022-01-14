import XCTest
import RxBlocking
import SolanaSwift
import FeeRelayerSwift
import RxSwift

class RelayTests: XCTestCase {
    private var orcaSwap: OrcaSwapType!
    private var relayService: FeeRelayer.Relay!

    override func setUpWithError() throws {
        let accountStorage = FakeAccountStorage()
        let solanaClient = SolanaSDK(
            endpoint: endpoint,
            accountStorage: accountStorage
        )
        
        orcaSwap = OrcaSwap(
            apiClient: OrcaSwap.APIClient(network: solanaClient.endpoint.network.cluster),
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
        orcaSwap = nil
        relayService = nil
    }

    // MARK: - TopUpAndSwap
    func testTopUpAndSwapToCreatedToken() throws {
        // Swap KURO to SLIM
        let kuroMint = "2Kc38rfQ49DFaKHQaWbijkE7fcymUMLY5guUiUsDmFfn"
        let slimMint = "xxxxa1sKNGwFtw2kFn8XauW9xq8hBZ5kVtcSesTT9fW"
        
        let inputAmount: UInt64 = 1000000 // 1 KURO
        
        // get pools pair
        let poolPairs = try orcaSwap.getTradablePoolsPairs(fromMint: kuroMint, toMint: slimMint).toBlocking().first()!
        
        // get best pool pair
        let pools = try orcaSwap.findBestPoolsPairForInputAmount(inputAmount, from: poolPairs)!
        
        // request
        let request = try relayService.topUpAndSwap(
            apiVersion: 1,
            sourceToken: .init(
                address: "C5B13tQA4pq1zEVSVkWbWni51xdWB16C2QsC72URq9AJ",
                mint: kuroMint
            ),
            destinationTokenMint: slimMint,
            destinationAddress: "FH58UXMZnj9HTAWusB9zmYCtqUCCLP351ao4S687pxD6",
            payingFeeToken: .init(
                address: "mCZrAFuPfBDPUW45n5BSkasRLpPZpmqpY7vs3XSYE7x",
                mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
            ),
            pools: pools,
            inputAmount: 1,
            slippage: 0.05
        ).toBlocking().first()
    }

}

// MARK: - Helpers
private let endpoint = SolanaSDK.APIEndPoint(address: "https://api.mainnet-beta.solana.com", network: .mainnetBeta)

private class FakeAccountStorage: SolanaSDKAccountStorage, OrcaSwapAccountProvider {
    func getAccount() -> OrcaSwap.Account? {
        account
    }
    
    func getNativeWalletAddress() -> OrcaSwap.PublicKey? {
        account?.publicKey
    }
    
    var account: SolanaSDK.Account? {
        fatalError()
//                .init(phrase: <#T##[String]#>, network: <#T##SolanaSDK.Network#>, derivablePath: <#T##SolanaSDK.DerivablePath?#>)
    }
}

private class FakeNotificationHandler: OrcaSwapSignatureConfirmationHandler {
    func waitForConfirmation(signature: String) -> Completable {
        .empty()
    }
}
