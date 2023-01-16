import XCTest
@testable import FeeRelayerSwift
@testable import SolanaSwift

final class RelayContextManagerTests: XCTestCase {
    var contextManager: RelayContextManager!
    fileprivate var feeRelayerAPIClient: MockFeeRelayerAPIClient!
    
    override func setUp() async throws {
        feeRelayerAPIClient = MockFeeRelayerAPIClient()
        contextManager = RelayContextManagerImpl(
            accountStorage: try await MockAccountStorage(),
            solanaAPIClient: MockSolanaAPIClient(),
            feeRelayerAPIClient: feeRelayerAPIClient
        )
    }
    
    override func tearDown() async throws {
        contextManager = nil
        feeRelayerAPIClient = nil
    }

    func testGetCurrentContext() async throws {
        let context = try await contextManager.getCurrentContext()
        XCTAssertNotNil(context)
    }
    
    func testUpdate() async throws {
        try await contextManager.update()
    }
    
    func testValidate() async throws {
        feeRelayerAPIClient.testCase = 0
        _ = try await contextManager.getCurrentContext()
        let validation = try await contextManager.validate()
        XCTAssertTrue(validation)
        
        feeRelayerAPIClient.testCase = 1
        let validation2 = try await contextManager.validate()
        XCTAssertFalse(validation2)
        
        try await contextManager.update()
        let validation3 = try await contextManager.validate()
        XCTAssertTrue(validation3)
    }
}

private class MockSolanaAPIClient: MockSolanaAPIClientBase {
    override func getMinimumBalanceForRentExemption(dataLength: UInt64, commitment: Commitment?) async throws -> UInt64 {
        switch dataLength {
        case 165:
            return 2039280
        case 0:
            return 890880
        default:
            fatalError()
        }
    }
    
    override func getFees(commitment: Commitment?) async throws -> Fee {
        .init(feeCalculator: .init(lamportsPerSignature: 5000), feeRateGovernor: nil, blockhash: nil, lastValidSlot: nil)
    }
    
    override func getAccountInfo<T>(account: String) async throws -> BufferInfo<T>? where T : BufferLayout {
        switch account {
        case PublicKey.relayAccount.base58EncodedString:
            return nil
        default:
            fatalError()
        }
    }
}

private class MockFeeRelayerAPIClient: MockFeeRelayerAPIClientBase {
    var testCase = 0
    
    override func getFeePayerPubkey() async throws -> String {
        "HkLNnxTFst1oLrKAJc3w6Pq8uypRnqLMrC68iBP6qUPu"
    }
    
    override func getFreeFeeLimits(for authority: String) async throws -> FeeLimitForAuthorityResponse {
        let string: String
        
        switch authority {
        case PublicKey.owner.base58EncodedString:
            string = #"{"authority":[39,247,185,4,85,137,50,166,147,184,221,75,110,103,16,222,41,94,247,132,43,62,172,243,95,204,190,143,153,16,10,197],"limits":{"use_free_fee":true,"max_amount":10000000,"max_count":100,"period":{"secs":86400,"nanos":0}},"processed_fee":{"total_amount":0,"count":\#(testCase)}}"#
        default:
            fatalError()
        }
        
        let feeLimit = try JSONDecoder().decode(FeeLimitForAuthorityResponse.self, from: string.data(using: .utf8)!)
        return feeLimit
    }
}
