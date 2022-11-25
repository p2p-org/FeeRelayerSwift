import Foundation
import SolanaSwift
@testable import FeeRelayerSwift

class MockDestinationFinderBase: DestinationFinder {
    func findRealDestination(
        owner: PublicKey,
        mint: PublicKey,
        givenDestination: PublicKey?
    ) async throws -> DestinationFinderResult {
        fatalError()
    }
}
