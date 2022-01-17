import XCTest
@testable import FeeRelayerSwift
import SolanaSwift

class RelaySolanaClientTests: XCTestCase {
    var solanaClient: FeeRelayerRelaySolanaClient!
    override func setUpWithError() throws {
        solanaClient = SolanaSDK(endpoint: .defaultEndpoints.first!, accountStorage: FakeAccountStorage())
    }
    
    func testGetRelayAccountStatusNotYetCreated() throws {
        let relayAccount = try FeeRelayer.Relay.Program.getUserRelayAddress(user: "B4PdyoVU39hoCaiTLPtN9nJxy6rEpbciE3BNPvHkCeE2")
        let result = try solanaClient.getRelayAccountStatus(relayAccount.base58EncodedString).toBlocking().first()!
        XCTAssertEqual(result, .notYetCreated)
    }
    
    func testGetRelayAccountStatusCreated() throws {
        let relayAccount = try FeeRelayer.Relay.Program.getUserRelayAddress(user: "5bYReP8iw5UuLVS5wmnXfEfrYCKdiQ1FFAZQao8JqY7V")
        let result = try solanaClient.getRelayAccountStatus(relayAccount.base58EncodedString).toBlocking().first()!
        XCTAssertNotEqual(result, .notYetCreated)
        XCTAssertNotEqual(result.balance, nil)
    }
}
