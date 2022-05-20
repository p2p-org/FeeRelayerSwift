import XCTest
import FeeRelayerSwift
import RxBlocking
import SolanaSwift

class APIClientTests: XCTestCase {
    
    func testGetFeeRelayerPubkey() async throws {
        let expected = "FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT"
        let feeRelayer = APIClientMock(version: 1)
        let result = try await feeRelayer.getFeePayerPubkey()
        XCTAssertEqual(result.isEmpty, false)
        XCTAssertEqual(result, expected)
    }
    
    func testGetFreeTransactionFeeLimit() async throws {
        let feeRelayer = APIClient(httpClient: MockHTTPClient(), version: 1)
        let result = try await feeRelayer.requestFreeFeeLimits(for: "GZpacnxxvtFDMg16KWSH8q2g8tM7fwJvNMkb2Df34h9N")
        XCTAssertNotNil(result)
    }
    
    func testSendTransaction() async throws {
        let feeRelayer = APIClient(httpClient: MockHTTPClient(), version: 1)
        
        let toPublicKey = "6QuXb6mB6WmRASP2y8AavXh6aabBXEH5ZzrSH5xRrgSm"
        let apiClient = JSONRPCAPIClient(endpoint: .init(address: "https://ya.ru", network: .mainnetBeta))
        let blockchain = BlockchainClient(apiClient: apiClient)
        
        let tx = try await blockchain.prepareSendingNativeSOL(
            from: toPublicKey,
            to: toPublicKey,
            amount: 100,
            feePayer: toPublicKey
        )
        ptx.transaction.recentBlockhash = ""
        
        let txs = try await feeRelayer.sendTransaction(.relayTransaction(
            try .init(preparedTransaction: tx)
        ))
        print(txs)
        XCTAssertNil(txs)
    }
}

class APIClientMock: FeeRelayerAPIClient {
    var version: Int = 1
    
    init(version: Int) {
        self.version = version
    }
    
    func getFeePayerPubkey() async throws -> String {
        "FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT"
    }
    
    func requestFreeFeeLimits(for authority: String) throws -> FeeRelayer.Relay.FeeLimitForAuthorityResponse {
        fatalError()
    }
    
    func sendTransaction(_ requestType: FeeRelayer.RequestType) throws -> String {
        fatalError()
    }
    
    func sendTransaction<T>(_ requestType: FeeRelayer.RequestType) throws -> T where T : Decodable {
        fatalError()
    }

}

class MockHTTPClient: HTTPClient {
    func sendRequest<T>(request: URLRequest, decoder: JSONDecoder) async throws -> T where T : Decodable {
        let json = "{\"authority\":[231],\"limits\":{\"use_free_fee\":true,\"max_amount\":10000000,\"max_count\":100,\"period\":{\"secs\":86400,\"nanos\":0}},\"processed_fee\":{\"total_amount\":0,\"count\":0}}".data(using: .utf8)!
        return try decoder.decode(T.self, from: json)
    }
}
