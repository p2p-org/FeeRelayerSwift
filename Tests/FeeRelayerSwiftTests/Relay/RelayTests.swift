import XCTest
import RxBlocking
import SolanaSwift
import FeeRelayerSwift
import RxSwift

class RelayTests: XCTestCase {
    private var relayService: FeeRelayer.Relay!

    override func setUpWithError() throws {
        let accountStorage = FakeAccountStorage()
        let solanaClient = SolanaSDK(
            endpoint: .init(address: "https://api.mainnet-beta.solana.com", network: .mainnetBeta),
            accountStorage: accountStorage
        )
        
        let orcaSwapClient = OrcaSwap(
            apiClient: OrcaSwap.APIClient(network: solanaClient.endpoint.network.cluster),
            solanaClient: solanaClient,
            accountProvider: accountStorage,
            notificationHandler: FakeNotificationHandler()
        )
        
        relayService = .init(
            apiClient: FeeRelayer.APIClient(),
            solanaClient: solanaClient,
            accountStorage: accountStorage,
            orcaSwapClient: orcaSwapClient
        )
    }

    override func tearDownWithError() throws {
        relayService = nil
    }

    // MARK: - TopUpAndSwap
    func testTopUpAndSwap() throws {
        
    }

}

// MARK: - Helpers
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
