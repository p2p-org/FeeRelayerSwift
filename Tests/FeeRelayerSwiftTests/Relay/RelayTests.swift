import XCTest
import RxBlocking
import SolanaSwift
@testable import FeeRelayerSwift
import Cuckoo
import OrcaSwapSwift

class RelayTests: XCTestCase {
    let endpoint = APIEndPoint(
        address: "https://api.mainnet-beta.solana.com",
        network: .mainnetBeta
    )
    let testsInfo = try! getDataFromJSONTestResourceFile(fileName: "relay-tests", decodedTo: RelayTestsInfo.self)
    var relayService: FeeRelayerService!
    
    override func tearDownWithError() throws {
        relayService = nil
    }
    
    @discardableResult
    func loadTest(_ relayTest: RelayTestType) throws -> FeeRelayerAPIClient {
        let network = Network.mainnetBeta
        let accountStorage = FakeAccountStorage(seedPhrase: relayTest.seedPhrase, network: network)
        let endpoint = APIEndPoint(address: relayTest.endpoint, network: network, additionalQuery: relayTest.endpointAdditionalQuery)
        let solanaAPIClient = JSONRPCAPIClient(endpoint: endpoint)
        let orcaSwapAPIClient = MockFakeOrcaSwapAPIClient(configsProvider: NetworkConfigsProvider(network: ""))
        let orcaSwap = MockFakeOrcaSwap(
            apiClient: orcaSwapAPIClient,
            solanaClient: solanaAPIClient,
            blockchainClient: MockFakeSolanaBlockchainClient(apiClient: solanaAPIClient),
            accountStorage: FakeAccountStorage(seedPhrase: "", network: .mainnetBeta)
        )

        let apiClient = APIClient(version: 1)
        relayService = FeeRelayerService(
            account: accountStorage.account!,
            orcaSwap: orcaSwap,
//            accountStorage: accountStorage,
            solanaApiClient: solanaAPIClient,
            feeCalculator: DefaultFreeRelayerCalculator(),
            feeRelayerAPIClient: APIClient(version: 1),
            deviceType: .iOS,
            buildNumber: "1"
        )
        return apiClient
    }
}


