import XCTest
@testable import FeeRelayerSwift
import SolanaSwift

class RelaySolanaClientTests: XCTestCase {
    var solanaClient: SolanaAPIClient!
    override func setUpWithError() throws {
        solanaClient = RelaySolanaAPIClientMock(endpoint: .defaultEndpoints.first!)
    }
    
    func testGetRelayAccountStatusNotYetCreated() async throws {
        let jsonResp = "{\"context\":{\"slot\":135650658},\"value\":null}"
        (solanaClient as! RelaySolanaAPIClientMock).json = jsonResp
        let relayAccount = try Program.getUserRelayAddress(user: "B4PdyoVU39hoCaiTLPtN9nJxy6rEpbciE3BNPvHkCeE2", network: solanaClient.endpoint.network)
        let result = try await solanaClient.getRelayAccountStatus(relayAccount.base58EncodedString)
        XCTAssertEqual(result, .notYetCreated)
    }
    
    func testGetRelayAccountStatusCreated() async throws {
        let jsonResp = "{\"context\":{\"slot\":135650713},\"value\":{\"data\":[\"\",\"base64\"],\"lamports\":932055,\"owner\":\"11111111111111111111111111111111\",\"executable\":false,\"rentEpoch\":313}}"
        (solanaClient as! RelaySolanaAPIClientMock).json = jsonResp
        let relayAccount = try Program.getUserRelayAddress(user: "5bYReP8iw5UuLVS5wmnXfEfrYCKdiQ1FFAZQao8JqY7V", network: solanaClient.endpoint.network)
        let result = try await solanaClient.getRelayAccountStatus(relayAccount.base58EncodedString)
        XCTAssertNotEqual(result, .notYetCreated)
        XCTAssertNotEqual(result.balance, nil)
    }

}

class RelaySolanaAPIClientMock: SolanaAPIClientMock {
    var json: String!
    
    override func getAccountInfo<T: BufferLayout>(account: String) async throws -> BufferInfo<T>? {
        let res = try JSONDecoder().decode(Rpc<BufferInfo<T>?>.self, from: json.data(using: .utf8)!)
        return res.value
    }
}
