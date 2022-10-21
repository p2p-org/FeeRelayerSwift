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
    
    func testFindRealDestination() async throws {
        let owner: PublicKey = "6QuXb6mB6WmRASP2y8AavXh6aabBXEH5ZzrSH5xRrgSm"
        let usdcAssociatedAddress: PublicKey = "9GQV3bQP9tv7m6XgGMaixxEeEdxtFhwgABw2cxCFZoch"
        
        // CASE 1: destination is wsol, needs create temporary wsol account
        let destination1 = try await destinationFinder.findRealDestination(
            owner: owner,
            mint: .wrappedSOLMint,
            givenDestination: "13DeafU3s4PoEUoDgyeNYZMqZWmgyN8fn3U5HrYxxXwQ" // anything
        )
        XCTAssertEqual(destination1, .init(
            destination: .init(address: owner, mint: .wrappedSOLMint),
            destinationOwner: owner,
            needsCreation: true)
        )
        
        // CASE 2: given destination is already created spl token address
        let destination2 = try await destinationFinder.findRealDestination(
            owner: owner,
            mint: .usdcMint,
            givenDestination: usdcAssociatedAddress
        )
        XCTAssertEqual(destination2, .init(
            destination: .init(address: usdcAssociatedAddress, mint: .usdcMint),
            destinationOwner: owner,
            needsCreation: false)
        )
        
        // CASE 3: given destination is nil, needs to check weather associated token address has already been created or not
        let destination3 = try await destinationFinder.findRealDestination(
            owner: owner,
            mint: .usdcMint,
            givenDestination: nil
        )
        XCTAssertEqual(destination3, .init(
            destination: .init(address: usdcAssociatedAddress, mint: .usdcMint),
            destinationOwner: owner,
            needsCreation: false)
        )
    }
}
