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

final class DefaultDirectSwapFeeRelayerCalculatorTests: XCTestCase {

    var calculator: DefaultSwapFeeRelayerCalculator!
    
    override func tearDown() async throws {
        calculator = nil
    }

    func testCalculateSwappingFeeFromSOLToNonCreatedSPL() async throws {
        calculator = .init(
            solanaApiClient: MockSolanaAPIClient(testCase: 0),
            accountStorage: try await MockAccountStorage()
        )
        
        let fee = try await calculator.calculateSwappingNetworkFees(
            createContext(),
            swapPools: [ btcSOLPool() ],
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
            minimumTokenAccountBalance // fee for create SPL Token Account
        )
    }
    
    func testCalculateSwapingFeeFromSOLToCreatedSPL() async throws {
        calculator = .init(
            solanaApiClient: MockSolanaAPIClient(testCase: 1),
            accountStorage: try await MockAccountStorage()
        )
        
        let fee = try await calculator.calculateSwappingNetworkFees(
            createContext(),
            swapPools: [ btcSOLPool() ],
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
            0 // account has already been created
        )
    }
    
    private func createContext() -> RelayContext {
        .init(
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            minimumRelayAccountBalance: minimumRelayAccountBalance,
            feePayerAddress: "FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT",
            lamportsPerSignature: lamportsPerSignature,
            relayAccountStatus: .created(balance: 0), // not important
            usageStatus: .init(
                maxUsage: 100,
                currentUsage: 0,
                maxAmount: 10000000,
                amountUsed: 0
            )
        )
    }
    
    private func btcSOLPool() -> Pool {
        .init(
            account: "7N2AEJ98qBs4PwEwZ6k5pj8uZBKMkZrKZeiC7A64B47u",
            authority: "GqnLhu3bPQ46nTZYNFDnzhwm31iFoqhi3ntXMtc5DPiT",
            nonce: 255,
            poolTokenMint: "Acxs19v6eUMTEfdvkvWkRB4bwFCHm3XV9jABCy7c1mXe",
            tokenAccountA: "5eqcnUasgU2NRrEAeWxvFVRTTYWJWfAJhsdffvc6nJc2",
            tokenAccountB: "9G5TBPbEUg2iaFxJ29uVAT8ZzxY77esRshyHiLYZKRh8",
            feeAccount: "4yPG4A9jB3ibDMVXEN2aZW4oA1e1xzzA3z5VWjkZd18B",
            hostFeeAccount: nil,
            feeNumerator: 25,
            feeDenominator: 10000,
            ownerTradeFeeNumerator: 5,
            ownerTradeFeeDenominator: 10000,
            ownerWithdrawFeeNumerator: 0,
            ownerWithdrawFeeDenominator: 0,
            hostFeeNumerator: 0,
            hostFeeDenominator: 0,
            tokenAName: "SOL",
            tokenBName: "BTC",
            curveType: "ConstantProduct",
            amp: nil,
            programVersion: 2,
            deprecated: nil,
            tokenABalance: .init(amount: "715874535300", decimals: 9),
            tokenBBalance: .init(amount: "1113617", decimals: 6),
            isStable: nil
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
        case btcAssociatedAddress.base58EncodedString where testCase == 0:
            return nil
        case btcAssociatedAddress.base58EncodedString where testCase == 1:
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
