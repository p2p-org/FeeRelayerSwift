import Foundation
import FeeRelayerSwift

class MockFeeRelayerAPIClientBase: FeeRelayerAPIClient {
    func feeTokenData(mint: String) async throws -> FeeRelayerSwift.FeeTokenData {
        fatalError()
    }
    
    var version: Int = 0
    
    func getFeePayerPubkey() async throws -> String {
        "FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT"
    }
    
    func getFreeFeeLimits(for authority: String) async throws -> FeeRelayerSwift.FeeLimitForAuthorityResponse {
        fatalError()
    }
    
    func requestFreeFeeLimits(for authority: String) async throws -> FeeRelayerSwift.FeeLimitForAuthorityResponse {
        try await getFreeFeeLimits(for: authority)
    }
    
    func sendTransaction(_ requestType: FeeRelayerSwift.RequestType) async throws -> String {
        fatalError()
    }
}
