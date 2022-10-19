import XCTest
@testable import FeeRelayerSwift
@testable import SolanaSwift

final class RelayContextManagerTests: XCTestCase {
    var contextManager: RelayContextManager!
    
    override func setUp() async throws {
        contextManager = RelayContextManagerImpl(
            accountStorage: try await MockAccountStorage(),
            solanaAPIClient: MockSolanaAPIClient(),
            feeRelayerAPIClient: MockFeeRelayerAPIClient()
        )
    }
    
    override func tearDown() async throws {
        contextManager = nil
    }

    func testGetCurrentContext() async throws {
        let context = try await contextManager.getCurrentContext()
        XCTAssertNotNil(context)
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
        case "":
            fatalError("TODO")
        default:
            fatalError()
        }
    }
}

private class MockFeeRelayerAPIClient: MockFeeRelayerAPIClientBase {
    override func getFeePayerPubkey() async throws -> String {
        "HkLNnxTFst1oLrKAJc3w6Pq8uypRnqLMrC68iBP6qUPu"
    }
    
    override func getFreeFeeLimits(for authority: String) async throws -> FeeLimitForAuthorityResponse {
        fatalError("TODO")
    }
}
