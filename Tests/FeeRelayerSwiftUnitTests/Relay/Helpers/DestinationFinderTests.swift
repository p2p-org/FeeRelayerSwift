import Foundation
@testable import FeeRelayerSwift
import SolanaSwift
import XCTest

class DestinationFinderTests: XCTestCase {
    var destinationFinder: DestinationFinder!
    
    override func setUp() async throws {
        destinationFinder = DestinationFinderImpl(solanaAPIClient: MockSolanaAPIClientBase())
    }
    
    override func tearDown() async throws {
        destinationFinder = nil
    }
    
    func testFindDestination() async throws {
        try await destinationFinder.findRealDestination(owner: <#T##PublicKey#>, mint: <#T##PublicKey#>, givenDestination: <#T##PublicKey?#>)
    }
}
