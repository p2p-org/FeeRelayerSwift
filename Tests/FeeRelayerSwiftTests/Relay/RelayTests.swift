import XCTest
import SolanaSwift
@testable import FeeRelayerSwift
import OrcaSwapSwift

class RelayTests: XCTestCase {
    let testsInfo = try! getDataFromJSONTestResourceFile(fileName: "relay-tests", decodedTo: RelayTestsInfo.self)
    
//    var solanaClient: SolanaSDK!
//    var orcaSwap: OrcaSwapType!
//    var relayService: FeeRelayer.Relay!
//    
//    override func tearDownWithError() throws {
//        solanaClient = nil
//        orcaSwap = nil
//        relayService = nil
//    }
    
    @discardableResult
    func loadTest(_ relayTest: RelayTestType) throws -> FeeRelayerAPIClient {
        fatalError()
//        let network = Network.mainnetBeta
//        let accountStorage = FakeAccountStorage(seedPhrase: relayTest.seedPhrase, network: network)
//        let endpoint = SolanaSDK.APIEndPoint(address: relayTest.endpoint, network: network, additionalQuery: relayTest.endpointAdditionalQuery)
//        solanaClient = SolanaSDK(endpoint: endpoint, accountStorage: accountStorage)
//        orcaSwap = OrcaSwap(
//            apiClient: APIClient(network: network.cluster),
//            solanaClient: solanaClient,
//            accountProvider: accountStorage,
//            notificationHandler: FakeNotificationHandler()
//        )
//
//        let apiClient = APIClient(version: 1)
//        relayService = try FeeRelayer.Relay(
//            apiClient: apiClient,
//            solanaClient: solanaClient,
//            accountStorage: accountStorage,
//            orcaSwapClient: orcaSwap
//        )
//
//        _ = try load().toBlocking().first()
//        _ = try relayService.load().toBlocking().first()
//
//        return apiClient
    }
}
