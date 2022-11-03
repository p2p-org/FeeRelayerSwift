//
//  CheckDestinationTests.swift
//  
//
//  Created by Chung Tran on 03/11/2022.
//

import XCTest
@testable import FeeRelayerSwift
@testable import SolanaSwift

final class CheckDestinationTests: XCTestCase {
    private var accountStorage: MockAccountStorage!
    var account: SolanaSwift.Account { accountStorage.account! }
    
    override func setUp() async throws {
        accountStorage = try await .init()
    }
    
    override func tearDown() async throws {
        accountStorage = nil
    }
    
    func testCheckDestinationWhenDestinationIsCreatedSPLToken() async throws {
        let destinationAddress: PublicKey = "2Z2Pbn1bsqN4NSrf1JLC1JRGNchoCVwXqsfeF7zWYTnK"
        
        var env = SwapTransactionBuilder.BuildContext.Environment()
        
        try await SwapTransactionBuilder.checkDestination(
            solanaAPIClient: MockSolanaAPIClient(testCase: 0),
            owner: account,
            destinationMint: .usdcMint,
            destinationAddress: destinationAddress,
            feePayerAddress: .feePayerAddress,
            relayContext: createContext(),
            recentBlockhash: blockhash,
            env: &env
        )
        
        XCTAssertEqual(env.instructions.count, 0)
        XCTAssertEqual(env.accountCreationFee, 0)
        XCTAssertNil(env.additionalTransaction)
        XCTAssertNil(env.destinationNewAccount)
        XCTAssertEqual(env.userDestinationTokenAccountAddress, destinationAddress)
    }
    
    func testCheckDestinationWhenDestinationIsNonCreatedSPLToken() async throws {
        
        var env = SwapTransactionBuilder.BuildContext.Environment()
        
        try await SwapTransactionBuilder.checkDestination(
            solanaAPIClient: MockSolanaAPIClient(testCase: 1),
            owner: account,
            destinationMint: .usdcMint,
            destinationAddress: nil,
            feePayerAddress: .feePayerAddress,
            relayContext: createContext(),
            recentBlockhash: blockhash,
            env: &env
        )
        
        let decodedInstruction = try JSONEncoder().encode(env.instructions)
        let expectedDecodedInstruction = try JSONEncoder().encode([
            AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
                mint:  .usdcMint,
                owner: account.publicKey,
                payer: .feePayerAddress
            )
        ])
        
        XCTAssertEqual(decodedInstruction, expectedDecodedInstruction)
        XCTAssertEqual(env.accountCreationFee, minimumTokenAccountBalance)
        XCTAssertNil(env.additionalTransaction)
        XCTAssertNil(env.destinationNewAccount)
        
        let associatedAddress = try PublicKey.associatedTokenAddress(
            walletAddress: account.publicKey,
            tokenMintAddress: .usdcMint
        )
        XCTAssertEqual(env.userDestinationTokenAccountAddress, associatedAddress)
    }
    
    func testCheckDestinationWhenDestinationIsNativeSOL() async throws {
        
        var env = SwapTransactionBuilder.BuildContext.Environment()
        let relayContext = createContext()
        
        try await SwapTransactionBuilder.checkDestination(
            solanaAPIClient: MockSolanaAPIClient(testCase: 2),
            owner: account,
            destinationMint: .wrappedSOLMint,
            destinationAddress: account.publicKey,
            feePayerAddress: .feePayerAddress,
            relayContext: relayContext,
            recentBlockhash: blockhash,
            env: &env
        )
        
        XCTAssertNotNil(env.destinationNewAccount)
        let decodedInstruction = try JSONEncoder().encode(env.instructions)
        let expectedInstructions = [
            SystemProgram.createAccountInstruction(
                from: .feePayerAddress,
                toNewPubkey: env.destinationNewAccount!.publicKey,
                lamports: relayContext.minimumTokenAccountBalance,
                space: AccountInfo.BUFFER_LENGTH,
                programId: TokenProgram.id
            ),
            TokenProgram.initializeAccountInstruction(
                account: env.destinationNewAccount!.publicKey,
                mint:  .wrappedSOLMint,
                owner: account.publicKey
            )
        ]
        let expectedDecodedInstructions = try JSONEncoder().encode(expectedInstructions)
        
        XCTAssertEqual(decodedInstruction, expectedDecodedInstructions)
        XCTAssertEqual(env.accountCreationFee, minimumTokenAccountBalance)
        XCTAssertNil(env.additionalTransaction)
        XCTAssertEqual(env.userDestinationTokenAccountAddress, env.destinationNewAccount?.publicKey)
    }
    
    // MARK: - Helpers
    
    private func createContext() -> RelayContext {
        .init(
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            minimumRelayAccountBalance: minimumRelayAccountBalance,
            feePayerAddress: .feePayerAddress,
            lamportsPerSignature: lamportsPerSignature,
            relayAccountStatus: .created(balance: 0),
            usageStatus: .init(
                maxUsage: 10000000,
                currentUsage: 0,
                maxAmount: 10000000,
                amountUsed: 0
            )
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
//        case btcAssociatedAddress.base58EncodedString where testCase == 0 || testCase == 4:
//            return nil
//        case btcAssociatedAddress.base58EncodedString where testCase == 1 || testCase == 5:
//            let info = BufferInfo<AccountInfo>(
//                lamports: 0,
//                owner: TokenProgram.id.base58EncodedString,
//                data: .init(mint: btcMint, owner: SystemProgram.id, lamports: 0, delegateOption: 0, isInitialized: true, isFrozen: true, state: 0, isNativeOption: 0, rentExemptReserve: nil, isNativeRaw: 0, isNative: true, delegatedAmount: 0, closeAuthorityOption: 0),
//                executable: false,
//                rentEpoch: 0
//            )
//            return info as? BufferInfo<T>
//        case ethAssociatedAddress.base58EncodedString where testCase == 2 || testCase == 6:
//            return nil
//        case ethAssociatedAddress.base58EncodedString where testCase == 3 || testCase == 7:
//            let info = BufferInfo<AccountInfo>(
//                lamports: 0,
//                owner: TokenProgram.id.base58EncodedString,
//                data: .init(mint: btcMint, owner: SystemProgram.id, lamports: 0, delegateOption: 0, isInitialized: true, isFrozen: true, state: 0, isNativeOption: 0, rentExemptReserve: nil, isNativeRaw: 0, isNative: true, delegatedAmount: 0, closeAuthorityOption: 0),
//                executable: false,
//                rentEpoch: 0
//            )
//            return info as? BufferInfo<T>
        case PublicKey.owner.base58EncodedString:
            let info = BufferInfo<EmptyInfo>(
                lamports: 0,
                owner: SystemProgram.id.base58EncodedString,
                data: .init(),
                executable: false,
                rentEpoch: 0
            )
            return info as? BufferInfo<T>
        case "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3" where testCase == 1:
            return nil
        default:
            return try await super.getAccountInfo(account: account)
        }
    }
}
