import Foundation
@testable import FeeRelayerSwift
@testable import SolanaSwift
import XCTest

private let owner: PublicKey = "6QuXb6mB6WmRASP2y8AavXh6aabBXEH5ZzrSH5xRrgSm"
private let usdcAssociatedAddress: PublicKey = "9GQV3bQP9tv7m6XgGMaixxEeEdxtFhwgABw2cxCFZoch"

class DestinationFinderTests: XCTestCase {
    var destinationFinder: DestinationFinder!
    
    override func tearDown() async throws {
        destinationFinder = nil
    }
    
    func testFindRealDestinationWithWSOL() async throws {
        destinationFinder = DestinationFinderImpl(solanaAPIClient: MockSolanaAPIClient())
        
        // CASE 1: destination is wsol, needs create temporary wsol account
        let destination = try await destinationFinder.findRealDestination(
            owner: owner,
            mint: .wrappedSOLMint,
            givenDestination: "13DeafU3s4PoEUoDgyeNYZMqZWmgyN8fn3U5HrYxxXwQ" // anything
        )
        XCTAssertEqual(destination, .init(
            destination: .init(address: owner, mint: .wrappedSOLMint),
            destinationOwner: owner,
            needsCreation: true)
        )
    }
    
    func testFindRealDestinationWithCreatedSPLTokenAddress() async throws {
        destinationFinder = DestinationFinderImpl(solanaAPIClient: MockSolanaAPIClient())
        
        // CASE 2: given destination is already a created spl token address
        let destination = try await destinationFinder.findRealDestination(
            owner: owner,
            mint: .usdcMint,
            givenDestination: usdcAssociatedAddress
        )
        XCTAssertEqual(destination, .init(
            destination: .init(address: usdcAssociatedAddress, mint: .usdcMint),
            destinationOwner: owner,
            needsCreation: false)
        )
    }
    
    func testFindRealDestinationWithNonGivenDestination() async throws {
        destinationFinder = DestinationFinderImpl(solanaAPIClient: MockSolanaAPIClient(testCase: 2))
        
        // CASE 3: given destination is nil, need to return associated address and check for it creation
        let destination = try await destinationFinder.findRealDestination(
            owner: owner,
            mint: .usdcMint,
            givenDestination: nil
        )
        
        XCTAssertEqual(destination.destination.address, owner)
        XCTAssertEqual(destination.destinationOwner, nil)
        XCTAssertEqual(destination.needsCreation, false)
    }
    
    func testFindRealDestinationWithNonGivenDestination2() async throws {
        destinationFinder = DestinationFinderImpl(solanaAPIClient: MockSolanaAPIClient(testCase: 3))
        
        // CASE 3: given destination is nil, need to return associated address and check for it creation
        let destination = try await destinationFinder.findRealDestination(
            owner: owner,
            mint: .usdcMint,
            givenDestination: nil
        )
        XCTAssertEqual(destination.destination.address, owner)
        XCTAssertEqual(destination.destinationOwner, nil)
        XCTAssertEqual(destination.needsCreation, true)
    }
}

private class MockSolanaAPIClient: MockSolanaAPIClientBase {
    private let testCase: Int
    
    init(testCase: Int = 0) {
        self.testCase = testCase
    }
    
    override func getAccountInfo<T>(account: String) async throws -> BufferInfo<T>? where T : BufferLayout {
        switch account {
        case usdcAssociatedAddress.base58EncodedString:
            let info = BufferInfo<AccountInfo>(
                lamports: 0,
                owner: testCase > 2 ? SystemProgram.id.base58EncodedString: TokenProgram.id.base58EncodedString,
                data: .init(mint: SystemProgram.id, owner: SystemProgram.id, lamports: 0, delegateOption: 0, isInitialized: true, isFrozen: true, state: 0, isNativeOption: 0, rentExemptReserve: nil, isNativeRaw: 0, isNative: true, delegatedAmount: 0, closeAuthorityOption: 0),
                executable: false,
                rentEpoch: 0
            )
            return info as? BufferInfo<T>
        case owner.base58EncodedString:
            let info = BufferInfo<EmptyInfo>(
                lamports: 0,
                owner: SystemProgram.id.base58EncodedString,
                data: .init(),
                executable: false,
                rentEpoch: 0
            )
            return info as? BufferInfo<T>
        default:
            return try await super.getAccountInfo(account: account)
        }
    }
}
