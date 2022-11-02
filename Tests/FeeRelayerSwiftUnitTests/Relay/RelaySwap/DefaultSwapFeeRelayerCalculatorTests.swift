//
//  DefaultSwapFeeRelayerCalculatorTests.swift
//  
//
//  Created by Chung Tran on 02/11/2022.
//

import XCTest
@testable import FeeRelayerSwift
@testable import OrcaSwapSwift
@testable import SolanaSwift

private let owner: PublicKey = "3h1zGmCwsRJnVk5BuRNMLsPaQu1y2aqXqXDWYCgrp5UG"
private let btcMint: PublicKey = "9n4nbM75f5Ui33ZbPYXn59EwSgE8CGsHtAeTH5YFeJ9E"
private let btcAssociatedAddress: PublicKey = "4Vfs3NZ1Bo8agrfBJhMFdesso8tBWyUZAPBGMoWHuNRU"

private let ethMint: PublicKey = "2FPyTwcZLUg1MDrwsyoP4D6s1tM7hAkHYRjkNb5w6Pxk"
private let ethAssociatedAddress: PublicKey = "4Tz8MH5APRfA4rjUNxhRruqGGMNvrgji3KhWYKf54dc7"

final class DefaultSwapFeeRelayerCalculatorTests: XCTestCase {

    var calculator: DefaultSwapFeeRelayerCalculator!
    
    override func tearDown() async throws {
        calculator = nil
    }
    
    // MARK: - Direct Swap

    func testCalculateDirectSwappingFeeFromSOLToNonCreatedSPL() async throws {
        // SOL -> New BTC
        
        calculator = .init(
            solanaApiClient: MockSolanaAPIClient(testCase: 0),
            accountStorage: try await MockAccountStorage()
        )
        
        let fee = try await calculator.calculateSwappingNetworkFees(
            lamportsPerSignature: lamportsPerSignature,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            swapPoolsCount: 1,
            sourceTokenMint: "So11111111111111111111111111111111111111112",
            destinationTokenMint: btcMint, // BTC
            destinationAddress: nil
        )
        
        XCTAssertEqual(
            fee.transaction,
            3 * lamportsPerSignature // feepayer's signature, owner's signature, new wsol's signature
        )
        
        XCTAssertEqual(
            fee.accountBalances,
            minimumTokenAccountBalance // fee for creating SPL Token Account
        )
    }
    
    func testCalculateDirectSwapingFeeFromSOLToCreatedSPL() async throws {
        // SOL -> BTC
        
        calculator = .init(
            solanaApiClient: MockSolanaAPIClient(testCase: 1),
            accountStorage: try await MockAccountStorage()
        )
        
        let fee = try await calculator.calculateSwappingNetworkFees(
            lamportsPerSignature: lamportsPerSignature,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            swapPoolsCount: 1,
            sourceTokenMint: "So11111111111111111111111111111111111111112",
            destinationTokenMint: btcMint, // BTC
            destinationAddress: btcAssociatedAddress
        )
        
        XCTAssertEqual(
            fee.transaction,
            3 * lamportsPerSignature // feepayer's signature, owner's signature, new wsol's signature
        )
        
        XCTAssertEqual(
            fee.accountBalances,
            0 // account has already been created
        )
    }
    
    func testCalculateDirectSwapingFeeFromSPLToNonCreatedSPL() async throws {
        // BTC -> New ETH
        
        calculator = .init(
            solanaApiClient: MockSolanaAPIClient(testCase: 2),
            accountStorage: try await MockAccountStorage()
        )
        
        let fee = try await calculator.calculateSwappingNetworkFees(
            lamportsPerSignature: lamportsPerSignature,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            swapPoolsCount: 1,
            sourceTokenMint: btcMint,
            destinationTokenMint: ethMint, // BTC
            destinationAddress: nil
        )
        
        XCTAssertEqual(
            fee.transaction,
            2 * lamportsPerSignature // feepayer's signature, owner's signature, new wsol's signature
        )
        
        XCTAssertEqual(
            fee.accountBalances,
            minimumTokenAccountBalance // fee for creating SPL Token Account
        )
    }
    
    func testCalculateDirectSwapingFeeFromSPLToCreatedSPL() async throws {
        // BTC -> New ETH
        
        calculator = .init(
            solanaApiClient: MockSolanaAPIClient(testCase: 3),
            accountStorage: try await MockAccountStorage()
        )
        
        let fee = try await calculator.calculateSwappingNetworkFees(
            lamportsPerSignature: lamportsPerSignature,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            swapPoolsCount: 1,
            sourceTokenMint: btcMint,
            destinationTokenMint: ethMint, // BTC
            destinationAddress: ethAssociatedAddress
        )
        
        XCTAssertEqual(
            fee.transaction,
            2 * lamportsPerSignature // feepayer's signature, owner's signature, new wsol's signature
        )
        
        XCTAssertEqual(
            fee.accountBalances,
            0 // account has already been created
        )
    }
    
    func testCalculateDirectSwapingFeeFromSPLToSOL() async throws {
        // BTC -> SOL
        
        calculator = .init(
            solanaApiClient: MockSolanaAPIClient(testCase: 0),
            accountStorage: try await MockAccountStorage()
        )
        
        let fee = try await calculator.calculateSwappingNetworkFees(
            lamportsPerSignature: lamportsPerSignature,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            swapPoolsCount: 1,
            sourceTokenMint: btcMint,
            destinationTokenMint: .wrappedSOLMint, // BTC
            destinationAddress: owner
        )
        
        XCTAssertEqual(
            fee.transaction,
            3 * lamportsPerSignature // feepayer's signature, owner's signature, new wsol's signature
        )
        
        XCTAssertEqual(
            fee.accountBalances,
            0 // deposit fee has already been handled by fee relayer account
        )
    }
    
    // MARK: - Transitive Swap
    
    func testCalculateTransitiveSwappingFeeFromSOLToNonCreatedSPL() async throws {
        // SOL -> New BTC
        
        calculator = .init(
            solanaApiClient: MockSolanaAPIClient(testCase: 4),
            accountStorage: try await MockAccountStorage()
        )
        
        let fee = try await calculator.calculateSwappingNetworkFees(
            lamportsPerSignature: lamportsPerSignature,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            swapPoolsCount: 2,
            sourceTokenMint: "So11111111111111111111111111111111111111112",
            destinationTokenMint: btcMint, // BTC
            destinationAddress: nil
        )
        
        XCTAssertEqual(
            fee.transaction,
            5 * lamportsPerSignature // feepayer's signature, owner's signature, new wsol's signature, extra feepayer's and owner's signatures for additional transaction (2 transactions required)
        )
        
        XCTAssertEqual(
            fee.accountBalances,
            minimumTokenAccountBalance // fee for creating SPL Token Account
        )
    }
    
    func testCalculateTransitiveSwapingFeeFromSOLToCreatedSPL() async throws {
        // SOL -> BTC
        
        calculator = .init(
            solanaApiClient: MockSolanaAPIClient(testCase: 5),
            accountStorage: try await MockAccountStorage()
        )
        
        let fee = try await calculator.calculateSwappingNetworkFees(
            lamportsPerSignature: lamportsPerSignature,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            swapPoolsCount: 2,
            sourceTokenMint: "So11111111111111111111111111111111111111112",
            destinationTokenMint: btcMint, // BTC
            destinationAddress: btcAssociatedAddress
        )
        
        XCTAssertEqual(
            fee.transaction,
            3 * lamportsPerSignature // feepayer's signature, owner's signature, new wsol's signature
        )
        
        XCTAssertEqual(
            fee.accountBalances,
            0 // account has already been created
        )
    }
    
    func testCalculateTransitiveSwapingFeeFromSPLToNonCreatedSPL() async throws {
        // BTC -> New ETH
        
        calculator = .init(
            solanaApiClient: MockSolanaAPIClient(testCase: 6),
            accountStorage: try await MockAccountStorage()
        )
        
        let fee = try await calculator.calculateSwappingNetworkFees(
            lamportsPerSignature: lamportsPerSignature,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            swapPoolsCount: 2,
            sourceTokenMint: btcMint,
            destinationTokenMint: ethMint, // BTC
            destinationAddress: nil
        )
        
        XCTAssertEqual(
            fee.transaction,
            2 * lamportsPerSignature // feepayer's signature, owner's signature, new wsol's signature
        )
        
        XCTAssertEqual(
            fee.accountBalances,
            minimumTokenAccountBalance // fee for creating SPL Token Account
        )
    }
    
    func testCalculateTransitiveSwapingFeeFromSPLToCreatedSPL() async throws {
        // BTC -> New ETH
        
        calculator = .init(
            solanaApiClient: MockSolanaAPIClient(testCase: 7),
            accountStorage: try await MockAccountStorage()
        )
        
        let fee = try await calculator.calculateSwappingNetworkFees(
            lamportsPerSignature: lamportsPerSignature,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            swapPoolsCount: 2,
            sourceTokenMint: btcMint,
            destinationTokenMint: ethMint, // BTC
            destinationAddress: ethAssociatedAddress
        )
        
        XCTAssertEqual(
            fee.transaction,
            2 * lamportsPerSignature // feepayer's signature, owner's signature, new wsol's signature
        )
        
        XCTAssertEqual(
            fee.accountBalances,
            0 // account has already been created
        )
    }
    
    func testCalculateTransitiveSwapingFeeFromSPLToSOL() async throws {
        // BTC -> SOL
        
        calculator = .init(
            solanaApiClient: MockSolanaAPIClient(testCase: 0),
            accountStorage: try await MockAccountStorage()
        )
        
        let fee = try await calculator.calculateSwappingNetworkFees(
            lamportsPerSignature: lamportsPerSignature,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            swapPoolsCount: 2,
            sourceTokenMint: btcMint,
            destinationTokenMint: .wrappedSOLMint, // BTC
            destinationAddress: owner
        )
        
        XCTAssertEqual(
            fee.transaction,
            3 * lamportsPerSignature // feepayer's signature, owner's signature, new wsol's signature
        )
        
        XCTAssertEqual(
            fee.accountBalances,
            0 // deposit fee has already been handled by fee relayer account
        )
    }
}

private class MockSolanaAPIClient: MockSolanaAPIClientBase {
    private let testCase: Int

    init(testCase: Int = 0) {
        self.testCase = testCase
    }

    override func getAccountInfo<T>(account: String) async throws -> BufferInfo<T>? where T : BufferLayout {
        switch account {
        case btcAssociatedAddress.base58EncodedString where testCase == 0 || testCase == 4:
            return nil
        case btcAssociatedAddress.base58EncodedString where testCase == 1 || testCase == 5:
            let info = BufferInfo<AccountInfo>(
                lamports: 0,
                owner: TokenProgram.id.base58EncodedString,
                data: .init(mint: btcMint, owner: SystemProgram.id, lamports: 0, delegateOption: 0, isInitialized: true, isFrozen: true, state: 0, isNativeOption: 0, rentExemptReserve: nil, isNativeRaw: 0, isNative: true, delegatedAmount: 0, closeAuthorityOption: 0),
                executable: false,
                rentEpoch: 0
            )
            return info as? BufferInfo<T>
        case ethAssociatedAddress.base58EncodedString where testCase == 2 || testCase == 6:
            return nil
        case ethAssociatedAddress.base58EncodedString where testCase == 3 || testCase == 7:
            let info = BufferInfo<AccountInfo>(
                lamports: 0,
                owner: TokenProgram.id.base58EncodedString,
                data: .init(mint: btcMint, owner: SystemProgram.id, lamports: 0, delegateOption: 0, isInitialized: true, isFrozen: true, state: 0, isNativeOption: 0, rentExemptReserve: nil, isNativeRaw: 0, isNative: true, delegatedAmount: 0, closeAuthorityOption: 0),
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
