import Foundation
import XCTest
@testable import FeeRelayerSwift
@testable import SolanaSwift
import OrcaSwapSwift

final class DirectSwapTransactionBuilderTests: XCTestCase {
    var swapTransactionBuilder: SwapTransactionBuilderImpl!
    var accountStorage: SolanaAccountStorage!
    
    override func setUp() async throws {
        accountStorage = try await MockAccountStorage()
    }
    
    override func tearDown() async throws {
        swapTransactionBuilder = nil
        accountStorage = nil
    }
    
    // MARK: - Direct swap
    func testBuildDirectSwapSOLToNonCreatedSPL() async throws {
        swapTransactionBuilder = .init(
            network: .mainnetBeta,
            transitTokenAccountManager: MockTransitTokenAccountManager(),
            destinationManager: MockDestinationFinder(testCase: 0),
            orcaSwap: MockOrcaSwapBase(),
            feePayerAddress: .feePayerAddress,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            lamportsPerSignature: lamportsPerSignature
        )
        
        let inputAmount: UInt64 = 1000000
        let slippage: Double = 0.1
        
        let output = try await swapTransactionBuilder.prepareSwapTransaction(
            input: .init(
                userAccount: accountStorage.account!,
                pools: [.solBTC],
                inputAmount: inputAmount,
                slippage: slippage,
                sourceTokenAccount: .init(address: accountStorage.account!.publicKey, mint: .wrappedSOLMint),
                destinationTokenMint: .btcMint,
                destinationTokenAddress: nil,
                blockhash: blockhash
            )
        )
        
        XCTAssertEqual(output.additionalPaybackFee, minimumTokenAccountBalance) // WSOL
        // 2 transactions needed:
        XCTAssertEqual(output.transactions.count, 2)
        
        // - Create destination spl token address // TODO: - Also for direct swap or not???
        let createDestinationSPLTokenTransaction = output.transactions[0]
        XCTAssertEqual(createDestinationSPLTokenTransaction.signers, [accountStorage.account])
        XCTAssertEqual(createDestinationSPLTokenTransaction.expectedFee, .init(transaction: 10000, accountBalances: minimumTokenAccountBalance))
        XCTAssertEqual(createDestinationSPLTokenTransaction.transaction.feePayer, .feePayerAddress)
        XCTAssertEqual(createDestinationSPLTokenTransaction.transaction.recentBlockhash, blockhash)
        XCTAssertEqual(createDestinationSPLTokenTransaction.transaction.instructions.count, 1)
        XCTAssertEqual(createDestinationSPLTokenTransaction.transaction.instructions[0].programId, AssociatedTokenProgram.id)
        XCTAssertEqual(createDestinationSPLTokenTransaction.transaction.instructions[0].data, [])
        XCTAssertEqual(createDestinationSPLTokenTransaction.transaction.instructions[0].keys, [
            .writable(publicKey: .feePayerAddress, isSigner: true),
            .writable(publicKey: .btcAssociatedAddress, isSigner: false),
            .readonly(publicKey: .owner, isSigner: false),
            .readonly(publicKey: .btcMint, isSigner: false),
            .readonly(publicKey: SystemProgram.id, isSigner: false),
            .readonly(publicKey: TokenProgram.id, isSigner: false),
            .readonly(publicKey: .sysvarRent, isSigner: false),
        ])
        
        // - Swap transaction
        let swapTransaction = output.transactions[1]
        XCTAssertEqual(swapTransaction.signers.count, 2) // owner / wsol new account
        XCTAssertEqual(swapTransaction.signers[0], accountStorage.account)
        XCTAssertEqual(swapTransaction.expectedFee, .init(transaction: 15000, accountBalances: 0)) // payer's, owner's, wsol's signatures
        XCTAssertEqual(swapTransaction.transaction.feePayer, .feePayerAddress)
        XCTAssertEqual(swapTransaction.transaction.recentBlockhash, blockhash)
        XCTAssertEqual(swapTransaction.transaction.instructions.count, 5) // transfer
        // - - TransferSOL instruction
        XCTAssertEqual(swapTransaction.transaction.instructions[0], .init( // transfer inputAmount to fee relayer
            keys: [
                .writable(publicKey: .owner, isSigner: true),
                .writable(publicKey: .feePayerAddress, isSigner: false)
            ],
            programId: SystemProgram.id,
            data: SystemProgram.Index.transfer.bytes + inputAmount.bytes)
        )
        XCTAssertEqual(swapTransaction.transaction.instructions[1], .init( // create wsol and transfer input amount + rent exempt
            keys: [
                .writable(publicKey: .feePayerAddress, isSigner: true),
                .writable(publicKey: swapTransaction.signers[1].publicKey, isSigner: true)
            ],
            programId: SystemProgram.id,
            data: SystemProgram.Index.create.bytes + (inputAmount + minimumTokenAccountBalance).bytes + UInt64(165).bytes + TokenProgram.id.bytes)
        )
        XCTAssertEqual(swapTransaction.transaction.instructions[2], .init( // initialize wsol
            keys: [
                .writable(publicKey: swapTransaction.signers[1].publicKey, isSigner: false),
                .readonly(publicKey: .wrappedSOLMint, isSigner: false),
                .readonly(publicKey: .owner, isSigner: false),
                .readonly(publicKey: .sysvarRent, isSigner: false)
            ],
            programId: TokenProgram.id,
            data: TokenProgram.Index.initializeAccount.bytes)
        )
        let minAmountOut = try Pool.solBTC.getMinimumAmountOut(inputAmount: inputAmount, slippage: slippage)
        XCTAssertEqual(swapTransaction.transaction.instructions[3], .init( // direct swap
            keys: [
                .readonly(publicKey: "7N2AEJ98qBs4PwEwZ6k5pj8uZBKMkZrKZeiC7A64B47u", isSigner: false),
                .readonly(publicKey: "GqnLhu3bPQ46nTZYNFDnzhwm31iFoqhi3ntXMtc5DPiT", isSigner: false),
                .readonly(publicKey: .owner, isSigner: true),
                .writable(publicKey: swapTransaction.signers[1].publicKey, isSigner: false),
                .writable(publicKey: "5eqcnUasgU2NRrEAeWxvFVRTTYWJWfAJhsdffvc6nJc2", isSigner: false),
                .writable(publicKey: "9G5TBPbEUg2iaFxJ29uVAT8ZzxY77esRshyHiLYZKRh8", isSigner: false),
                .writable(publicKey: .btcAssociatedAddress, isSigner: false),
                .writable(publicKey: "Acxs19v6eUMTEfdvkvWkRB4bwFCHm3XV9jABCy7c1mXe", isSigner: false),
                .writable(publicKey: "4yPG4A9jB3ibDMVXEN2aZW4oA1e1xzzA3z5VWjkZd18B", isSigner: false),
                .readonly(publicKey: TokenProgram.id, isSigner: false)
            ],
            programId: "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP",
            data: [UInt8(1)] + inputAmount.bytes + minAmountOut!.bytes)
        )
        
        XCTAssertEqual(swapTransaction.transaction.instructions[4], .init( // close wsol
            keys: [
                .writable(publicKey: swapTransaction.signers[1].publicKey, isSigner: false),
                .writable(publicKey: .owner, isSigner: false),
                .readonly(publicKey: .owner, isSigner: false)
            ],
            programId: TokenProgram.id,
            data: TokenProgram.Index.closeAccount.bytes)
        )
    }
    
    func testBuildDirectSwapSOLToCreatedSPL() async throws {
        swapTransactionBuilder = .init(
            network: .mainnetBeta,
            transitTokenAccountManager: MockTransitTokenAccountManager(),
            destinationManager: MockDestinationFinder(testCase: 1),
            orcaSwap: MockOrcaSwapBase(),
            feePayerAddress: .feePayerAddress,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            lamportsPerSignature: lamportsPerSignature
        )
        
        let inputAmount: UInt64 = 1000000
        let slippage: Double = 0.1
        
        let output = try await swapTransactionBuilder.prepareSwapTransaction(
            input: .init(
                userAccount: accountStorage.account!,
                pools: [.solBTC],
                inputAmount: inputAmount,
                slippage: slippage,
                sourceTokenAccount: .init(address: accountStorage.account!.publicKey, mint: .wrappedSOLMint),
                destinationTokenMint: .btcMint,
                destinationTokenAddress: .btcAssociatedAddress,
                blockhash: blockhash
            )
        )
        
        XCTAssertEqual(output.additionalPaybackFee, minimumTokenAccountBalance) // WSOL
        XCTAssertEqual(output.transactions.count, 1)
        // - Swap transaction
        let swapTransaction = output.transactions[0]
        XCTAssertEqual(swapTransaction.signers.count, 2) // owner / wsol new account
        XCTAssertEqual(swapTransaction.signers[0], accountStorage.account)
        XCTAssertEqual(swapTransaction.expectedFee, .init(transaction: 15000, accountBalances: 0)) // payer's, owner's, wsol's signatures
        XCTAssertEqual(swapTransaction.transaction.feePayer, .feePayerAddress)
        XCTAssertEqual(swapTransaction.transaction.recentBlockhash, blockhash)
        XCTAssertEqual(swapTransaction.transaction.instructions.count, 5) // transfer
//        // - - TransferSOL instruction
        XCTAssertEqual(swapTransaction.transaction.instructions[0], .init( // transfer inputAmount to fee relayer
            keys: [
                .writable(publicKey: .owner, isSigner: true),
                .writable(publicKey: .feePayerAddress, isSigner: false)
            ],
            programId: SystemProgram.id,
            data: SystemProgram.Index.transfer.bytes + inputAmount.bytes)
        )
        XCTAssertEqual(swapTransaction.transaction.instructions[1], .init( // create wsol and transfer input amount + rent exempt
            keys: [
                .writable(publicKey: .feePayerAddress, isSigner: true),
                .writable(publicKey: swapTransaction.signers[1].publicKey, isSigner: true)
            ],
            programId: SystemProgram.id,
            data: SystemProgram.Index.create.bytes + (inputAmount + minimumTokenAccountBalance).bytes + UInt64(165).bytes + TokenProgram.id.bytes)
        )
        XCTAssertEqual(swapTransaction.transaction.instructions[2], .init( // initialize wsol
            keys: [
                .writable(publicKey: swapTransaction.signers[1].publicKey, isSigner: false),
                .readonly(publicKey: .wrappedSOLMint, isSigner: false),
                .readonly(publicKey: .owner, isSigner: false),
                .readonly(publicKey: .sysvarRent, isSigner: false)
            ],
            programId: TokenProgram.id,
            data: TokenProgram.Index.initializeAccount.bytes)
        )
        let minAmountOut = try Pool.solBTC.getMinimumAmountOut(inputAmount: inputAmount, slippage: slippage)
        XCTAssertEqual(swapTransaction.transaction.instructions[3], .init( // direct swap
            keys: [
                .readonly(publicKey: "7N2AEJ98qBs4PwEwZ6k5pj8uZBKMkZrKZeiC7A64B47u", isSigner: false),
                .readonly(publicKey: "GqnLhu3bPQ46nTZYNFDnzhwm31iFoqhi3ntXMtc5DPiT", isSigner: false),
                .readonly(publicKey: .owner, isSigner: true),
                .writable(publicKey: swapTransaction.signers[1].publicKey, isSigner: false),
                .writable(publicKey: "5eqcnUasgU2NRrEAeWxvFVRTTYWJWfAJhsdffvc6nJc2", isSigner: false),
                .writable(publicKey: "9G5TBPbEUg2iaFxJ29uVAT8ZzxY77esRshyHiLYZKRh8", isSigner: false),
                .writable(publicKey: .btcAssociatedAddress, isSigner: false),
                .writable(publicKey: "Acxs19v6eUMTEfdvkvWkRB4bwFCHm3XV9jABCy7c1mXe", isSigner: false),
                .writable(publicKey: "4yPG4A9jB3ibDMVXEN2aZW4oA1e1xzzA3z5VWjkZd18B", isSigner: false),
                .readonly(publicKey: TokenProgram.id, isSigner: false)
            ],
            programId: "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP",
            data: [UInt8(1)] + inputAmount.bytes + minAmountOut!.bytes)
        )

        XCTAssertEqual(swapTransaction.transaction.instructions[4], .init( // close wsol
            keys: [
                .writable(publicKey: swapTransaction.signers[1].publicKey, isSigner: false),
                .writable(publicKey: .owner, isSigner: false),
                .readonly(publicKey: .owner, isSigner: false)
            ],
            programId: TokenProgram.id,
            data: TokenProgram.Index.closeAccount.bytes)
        )
    }
    
    func testBuildDirectSwapSPLToNonCreatedSPL() async throws {
        swapTransactionBuilder = .init(
            network: .mainnetBeta,
            transitTokenAccountManager: MockTransitTokenAccountManager(),
            destinationManager: MockDestinationFinder(testCase: 2),
            orcaSwap: MockOrcaSwapBase(),
            feePayerAddress: .feePayerAddress,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            lamportsPerSignature: lamportsPerSignature
        )
        
        let inputAmount: UInt64 = 1000000
        let slippage: Double = 0.1
        
        let output = try await swapTransactionBuilder.prepareSwapTransaction(
            input: .init(
                userAccount: accountStorage.account!,
                pools: [.btcETH],
                inputAmount: inputAmount,
                slippage: slippage,
                sourceTokenAccount: .init(address: .btcAssociatedAddress, mint: .btcMint),
                destinationTokenMint: .ethMint,
                destinationTokenAddress: nil,
                blockhash: blockhash
            )
        )
        
        XCTAssertEqual(output.additionalPaybackFee, 0) // No WSOL created
        XCTAssertEqual(output.transactions.count, 1)
        // - Swap transaction
        let swapTransaction = output.transactions[0]
        XCTAssertEqual(swapTransaction.signers.count, 1) // owner only
        XCTAssertEqual(swapTransaction.signers[0], accountStorage.account)
        XCTAssertEqual(swapTransaction.expectedFee, .init(transaction: 10000, accountBalances: minimumTokenAccountBalance)) // payer's, owner's signatures + SPL account creation fee
        XCTAssertEqual(swapTransaction.transaction.feePayer, .feePayerAddress)
        XCTAssertEqual(swapTransaction.transaction.recentBlockhash, blockhash)
        XCTAssertEqual(swapTransaction.transaction.instructions.count, 2) // transfer
        // - - Create Associated Token Account instruction
        XCTAssertEqual(swapTransaction.transaction.instructions[0], .init(
            keys: [
                .writable(publicKey: .feePayerAddress, isSigner: true),
                .writable(publicKey: .ethAssociatedAddress, isSigner: false),
                .readonly(publicKey: .owner, isSigner: false),
                .readonly(publicKey: .ethMint, isSigner: false),
                .readonly(publicKey: SystemProgram.id, isSigner: false),
                .readonly(publicKey: TokenProgram.id, isSigner: false),
                .readonly(publicKey: .sysvarRent, isSigner: false)
            ],
            programId: AssociatedTokenProgram.id,
            data: [])
        )
        // - - Direct Swap instruction
        let minAmountOut = try Pool.btcETH.getMinimumAmountOut(inputAmount: inputAmount, slippage: slippage)
        XCTAssertEqual(swapTransaction.transaction.instructions[1], .init(
            keys: [
                .readonly(publicKey: try PublicKey(string: Pool.btcETH.account), isSigner: false),
                .readonly(publicKey: try PublicKey(string: Pool.btcETH.authority), isSigner: false),
                .readonly(publicKey: .owner, isSigner: true),
                .writable(publicKey: .btcAssociatedAddress, isSigner: false),
                .writable(publicKey: try PublicKey(string: Pool.btcETH.tokenAccountA), isSigner: false),
                .writable(publicKey: try PublicKey(string: Pool.btcETH.tokenAccountB), isSigner: false),
                .writable(publicKey: .ethAssociatedAddress, isSigner: false),
                .writable(publicKey: try PublicKey(string: Pool.btcETH.poolTokenMint), isSigner: false),
                .writable(publicKey: try PublicKey(string: Pool.btcETH.feeAccount), isSigner: false),
                .readonly(publicKey: TokenProgram.id, isSigner: false)
            ],
            programId: "DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1",
            data: [UInt8(1)] + inputAmount.bytes + minAmountOut!.bytes)
        )
    }
    
    func testBuildDirectSwapSPLToCreatedSPL() async throws {
        swapTransactionBuilder = .init(
            network: .mainnetBeta,
            transitTokenAccountManager: MockTransitTokenAccountManager(),
            destinationManager: MockDestinationFinder(testCase: 3),
            orcaSwap: MockOrcaSwapBase(),
            feePayerAddress: .feePayerAddress,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            lamportsPerSignature: lamportsPerSignature
        )
        
        let inputAmount: UInt64 = 1000000
        let slippage: Double = 0.1
        
        let output = try await swapTransactionBuilder.prepareSwapTransaction(
            input: .init(
                userAccount: accountStorage.account!,
                pools: [.btcETH],
                inputAmount: inputAmount,
                slippage: slippage,
                sourceTokenAccount: .init(address: .btcAssociatedAddress, mint: .btcMint),
                destinationTokenMint: .ethMint,
                destinationTokenAddress: .ethAssociatedAddress,
                blockhash: blockhash
            )
        )
        
        XCTAssertEqual(output.additionalPaybackFee, 0) // No WSOL created
        XCTAssertEqual(output.transactions.count, 1)
        // - Swap transaction
        let swapTransaction = output.transactions[0]
        XCTAssertEqual(swapTransaction.signers.count, 1) // owner only
        XCTAssertEqual(swapTransaction.signers[0], accountStorage.account)
        XCTAssertEqual(swapTransaction.expectedFee, .init(transaction: 10000, accountBalances: 0)) // payer's, owner's signatures
        XCTAssertEqual(swapTransaction.transaction.feePayer, .feePayerAddress)
        XCTAssertEqual(swapTransaction.transaction.recentBlockhash, blockhash)
        XCTAssertEqual(swapTransaction.transaction.instructions.count, 1) // transfer
        // - - Direct Swap instruction
        let minAmountOut = try Pool.btcETH.getMinimumAmountOut(inputAmount: inputAmount, slippage: slippage)
        XCTAssertEqual(swapTransaction.transaction.instructions[0], .init(
            keys: [
                .readonly(publicKey: try PublicKey(string: Pool.btcETH.account), isSigner: false),
                .readonly(publicKey: try PublicKey(string: Pool.btcETH.authority), isSigner: false),
                .readonly(publicKey: .owner, isSigner: true),
                .writable(publicKey: .btcAssociatedAddress, isSigner: false),
                .writable(publicKey: try PublicKey(string: Pool.btcETH.tokenAccountA), isSigner: false),
                .writable(publicKey: try PublicKey(string: Pool.btcETH.tokenAccountB), isSigner: false),
                .writable(publicKey: .ethAssociatedAddress, isSigner: false),
                .writable(publicKey: try PublicKey(string: Pool.btcETH.poolTokenMint), isSigner: false),
                .writable(publicKey: try PublicKey(string: Pool.btcETH.feeAccount), isSigner: false),
                .readonly(publicKey: TokenProgram.id, isSigner: false)
            ],
            programId: "DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1",
            data: [UInt8(1)] + inputAmount.bytes + minAmountOut!.bytes)
        )
    }
    
    func testBuildDirectSwapSPLToCreatedSPLEvenWhenUserDoesNotGiveDestinationSPLTokenAddress() async throws {
        swapTransactionBuilder = .init(
            network: .mainnetBeta,
            transitTokenAccountManager: MockTransitTokenAccountManager(),
            destinationManager: MockDestinationFinder(testCase: 4),
            orcaSwap: MockOrcaSwapBase(),
            feePayerAddress: .feePayerAddress,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            lamportsPerSignature: lamportsPerSignature
        )
        
        let inputAmount: UInt64 = 1000000
        let slippage: Double = 0.1
        
        let output = try await swapTransactionBuilder.prepareSwapTransaction(
            input: .init(
                userAccount: accountStorage.account!,
                pools: [.btcETH],
                inputAmount: inputAmount,
                slippage: slippage,
                sourceTokenAccount: .init(address: .btcAssociatedAddress, mint: .btcMint),
                destinationTokenMint: .ethMint,
                destinationTokenAddress: nil,
                blockhash: blockhash
            )
        )
        
        XCTAssertEqual(output.additionalPaybackFee, 0) // No WSOL created
        XCTAssertEqual(output.transactions.count, 1)
        // - Swap transaction
        let swapTransaction = output.transactions[0]
        XCTAssertEqual(swapTransaction.signers.count, 1) // owner only
        XCTAssertEqual(swapTransaction.signers[0], accountStorage.account)
        XCTAssertEqual(swapTransaction.expectedFee, .init(transaction: 10000, accountBalances: 0)) // payer's, owner's signatures
        XCTAssertEqual(swapTransaction.transaction.feePayer, .feePayerAddress)
        XCTAssertEqual(swapTransaction.transaction.recentBlockhash, blockhash)
        XCTAssertEqual(swapTransaction.transaction.instructions.count, 1) // transfer
        // - - Direct Swap instruction
        let minAmountOut = try Pool.btcETH.getMinimumAmountOut(inputAmount: inputAmount, slippage: slippage)
        XCTAssertEqual(swapTransaction.transaction.instructions[0], .init(
            keys: [
                .readonly(publicKey: try PublicKey(string: Pool.btcETH.account), isSigner: false),
                .readonly(publicKey: try PublicKey(string: Pool.btcETH.authority), isSigner: false),
                .readonly(publicKey: .owner, isSigner: true),
                .writable(publicKey: .btcAssociatedAddress, isSigner: false),
                .writable(publicKey: try PublicKey(string: Pool.btcETH.tokenAccountA), isSigner: false),
                .writable(publicKey: try PublicKey(string: Pool.btcETH.tokenAccountB), isSigner: false),
                .writable(publicKey: .ethAssociatedAddress, isSigner: false),
                .writable(publicKey: try PublicKey(string: Pool.btcETH.poolTokenMint), isSigner: false),
                .writable(publicKey: try PublicKey(string: Pool.btcETH.feeAccount), isSigner: false),
                .readonly(publicKey: TokenProgram.id, isSigner: false)
            ],
            programId: "DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1",
            data: [UInt8(1)] + inputAmount.bytes + minAmountOut!.bytes)
        )
    }
}

private class MockDestinationFinder: DestinationFinder {
    private let testCase: Int

    init(testCase: Int) {
        self.testCase = testCase
    }
    
    func findRealDestination(
        owner: PublicKey,
        mint: PublicKey,
        givenDestination: PublicKey?
    ) async throws -> DestinationFinderResult {
        switch mint {
        // Case 0
        case .btcMint where testCase == 0:
            return DestinationFinderResult(
                destination: .init(address: .btcAssociatedAddress, mint: .btcMint),
                destinationOwner: owner,
                needsCreation: true
            )
        case .btcMint where testCase == 1:
            return DestinationFinderResult(
                destination: .init(address: .btcAssociatedAddress, mint: .btcMint),
                destinationOwner: owner,
                needsCreation: false
            )
        case .ethMint where testCase == 2:
            return DestinationFinderResult(
                destination: .init(address: .ethAssociatedAddress, mint: .ethMint),
                destinationOwner: owner,
                needsCreation: true
            )
        case .ethMint where testCase == 3:
            return DestinationFinderResult(
                destination: .init(address: .ethAssociatedAddress, mint: .ethMint),
                destinationOwner: owner,
                needsCreation: false
            )
        case .ethMint where testCase == 4:
            return DestinationFinderResult(
                destination: .init(address: .ethAssociatedAddress, mint: .ethMint),
                destinationOwner: owner,
                needsCreation: false
            )
        default:
            fatalError()
        }
    }
}

private class MockTransitTokenAccountManager: TransitTokenAccountManager {
    func getTransitToken(pools: OrcaSwapSwift.PoolsPair) throws -> FeeRelayerSwift.TokenAccount? {
        nil
    }
    
    func checkIfNeedsCreateTransitTokenAccount(transitToken: FeeRelayerSwift.TokenAccount?) async throws -> Bool? {
        nil
    }
}
