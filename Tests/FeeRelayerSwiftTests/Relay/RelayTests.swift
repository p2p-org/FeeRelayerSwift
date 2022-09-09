import XCTest
import SolanaSwift
@testable import FeeRelayerSwift
import OrcaSwapSwift

class RelayTests: XCTestCase {
    var accountStorage: SolanaAccountStorage!
    var solanaAPIClient: SolanaAPIClient!
    var orcaSwap: OrcaSwap!
    var feeRelayer: FeeRelayer!
    var feeRelayerAPIClient: FeeRelayerAPIClient!
    var context: FeeRelayerContext!
    
    override func tearDown() async throws {
        accountStorage = nil
        solanaAPIClient = nil
        orcaSwap = nil
        feeRelayer = nil
        feeRelayerAPIClient = nil
        context = nil
    }
    
    func loadTest(_ relayTest: RelayTestType) async throws {
        // Initialize services
        
        let network = Network.mainnetBeta
        accountStorage = try await MockAccountStorage(seedPhrase: relayTest.seedPhrase, network: network)
        let endpoint = APIEndPoint(address: relayTest.endpoint, network: network, additionalQuery: relayTest.endpointAdditionalQuery)
        
        solanaAPIClient = JSONRPCAPIClient(endpoint: endpoint)
        let blockchainClient = BlockchainClient(apiClient: solanaAPIClient)
        feeRelayerAPIClient = FeeRelayerSwift.APIClient(baseUrlString: testsInfo.baseUrlString, version: 1)
        
        let contextManager = FeeRelayerContextManagerImpl(
            accountStorage: accountStorage,
            solanaAPIClient: solanaAPIClient,
            feeRelayerAPIClient: feeRelayerAPIClient
        )

        orcaSwap = OrcaSwap(
            apiClient: OrcaSwapSwift.APIClient(
                configsProvider: OrcaSwapSwift.NetworkConfigsProvider(
                    network: "mainnet-beta"
                )
            ),
            solanaClient: solanaAPIClient,
            blockchainClient: blockchainClient,
            accountStorage: accountStorage
        )

        feeRelayer = FeeRelayerService(
            orcaSwap: orcaSwap,
            accountStorage: accountStorage,
            solanaApiClient: solanaAPIClient,
            feeCalculator: DefaultFreeRelayerCalculator(),
            feeRelayerAPIClient: feeRelayerAPIClient,
            deviceType: .iOS,
            buildNumber: "UnitTest"
        )
        
        // Load and update services

        let _ = try await (
            orcaSwap.load(),
            contextManager.update()
        )
        
        // Get current context
        
        context = try await contextManager.getCurrentContext()
    }
}

let testsInfo = try! getDataFromJSONTestResourceFile(fileName: "relay-tests", decodedTo: RelayTestsInfo.self)

struct MockAccountStorage: SolanaAccountStorage {
    let account: Account?
    
    init(seedPhrase: String, network: Network) async throws {
        account = try await .init(phrase: seedPhrase.components(separatedBy: " "), network: network)
    }
    
    func save(_ account: Account) throws {
        // ignore
    }
}
