import Foundation
import XCTest
@testable import FeeRelayerSwift
@testable import SolanaSwift
@testable import OrcaSwapSwift

final class TransitiveSwapTransactionBuilderWithCreatedTransitTokenTests: XCTestCase {
    var swapTransactionBuilder: SwapTransactionBuilderImpl!
    var accountStorage: SolanaAccountStorage!
    
    override func setUp() async throws {
        accountStorage = try await MockAccountStorage()
    }
    
    override func tearDown() async throws {
        swapTransactionBuilder = nil
        accountStorage = nil
    }

    func testBuildTransitiveSwapSOLToNonCreatedSPLToken() async throws {
        swapTransactionBuilder = .init(
            network: .mainnetBeta,
            transitTokenAccountManager: MockTransitTokenAccountManager(testCase: 0),
            destinationManager: MockDestinationFinder(testCase: 0),
            orcaSwap: MockOrcaSwapBase(),
            feePayerAddress: .feePayerAddress,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            lamportsPerSignature: lamportsPerSignature
        )
        
        // SOL -> BTC -> ETH
        let inputAmount: UInt64 = 100000000000
        let slippage: Double = 0.1
        
        let output = try await swapTransactionBuilder.prepareSwapTransaction(
            input: .init(
                userAccount: accountStorage.account!,
                pools: [.solBTC, .btcETH],
                inputAmount: inputAmount,
                slippage: slippage,
                sourceTokenAccount: .init(address: accountStorage.account!.publicKey, mint: .wrappedSOLMint),
                destinationTokenMint: .ethMint,
                destinationTokenAddress: nil,
                blockhash: blockhash
            )
        )
        
        XCTAssertEqual(output.additionalPaybackFee, minimumTokenAccountBalance) // WSOL
        
        XCTAssertEqual(output.transactions.count, 2)
        
        // - Create destination spl token address (ETH)
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
            .writable(publicKey: .ethAssociatedAddress, isSigner: false),
            .readonly(publicKey: .owner, isSigner: false),
            .readonly(publicKey: .ethMint, isSigner: false),
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

        let transitMinAmountOut = try Pool.solBTC.getMinimumAmountOut(inputAmount: inputAmount, slippage: slippage)
        let minAmountOut = try Pool.btcETH.getMinimumAmountOut(inputAmount: transitMinAmountOut!, slippage: slippage)
        let newWSOLAccount = swapTransaction.signers[1]
        let transitTokenPublicKey = try RelayProgram.getTransitTokenAccountAddress(
            user: .owner,
            transitTokenMint: .btcMint,
            network: .mainnetBeta
        )
        XCTAssertEqual(swapTransaction.transaction.instructions[3], .init( // direct swap
            keys: [
                .writable(publicKey: .feePayerAddress, isSigner: true),
                .readonly(publicKey: TokenProgram.id, isSigner: false),
                .readonly(publicKey: .owner, isSigner: true),
                .writable(publicKey: newWSOLAccount.publicKey, isSigner: false),
                .writable(publicKey: transitTokenPublicKey, isSigner: false),
                .writable(publicKey: .ethAssociatedAddress, isSigner: false),
                
                .readonly(publicKey: "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP", isSigner: false),
                .readonly(publicKey: Pool.solBTC.account.publicKey, isSigner: false),
                .readonly(publicKey: Pool.solBTC.authority.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.tokenAccountA.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.tokenAccountB.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.poolTokenMint.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.feeAccount.publicKey, isSigner: false),
                
                .readonly(publicKey: "DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1", isSigner: false),
                .readonly(publicKey: Pool.btcETH.account.publicKey, isSigner: false),
                .readonly(publicKey: Pool.btcETH.authority.publicKey, isSigner: false),
                .writable(publicKey: Pool.btcETH.tokenAccountA.publicKey, isSigner: false),
                .writable(publicKey: Pool.btcETH.tokenAccountB.publicKey, isSigner: false),
                .writable(publicKey: Pool.btcETH.poolTokenMint.publicKey, isSigner: false),
                .writable(publicKey: Pool.btcETH.feeAccount.publicKey, isSigner: false)
            ],
            programId: RelayProgram.id(network: .mainnetBeta),
            data: [RelayProgram.Index.transitiveSwap] + inputAmount.bytes + transitMinAmountOut!.bytes + minAmountOut!.bytes)
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
    
    func testBuildTransitiveSwapSOLToCreatedSPLToken() async throws {
        swapTransactionBuilder = .init(
            network: .mainnetBeta,
            transitTokenAccountManager: MockTransitTokenAccountManager(testCase: 1),
            destinationManager: MockDestinationFinder(testCase: 1),
            orcaSwap: MockOrcaSwapBase(),
            feePayerAddress: .feePayerAddress,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            lamportsPerSignature: lamportsPerSignature
        )
        
        // SOL -> BTC -> ETH
        let inputAmount: UInt64 = 100000000000
        let slippage: Double = 0.1
        
        let output = try await swapTransactionBuilder.prepareSwapTransaction(
            input: .init(
                userAccount: accountStorage.account!,
                pools: [.solBTC, .btcETH],
                inputAmount: inputAmount,
                slippage: slippage,
                sourceTokenAccount: .init(address: accountStorage.account!.publicKey, mint: .wrappedSOLMint),
                destinationTokenMint: .ethMint,
                destinationTokenAddress: .ethAssociatedAddress,
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

        let transitMinAmountOut = try Pool.solBTC.getMinimumAmountOut(inputAmount: inputAmount, slippage: slippage)
        let minAmountOut = try Pool.btcETH.getMinimumAmountOut(inputAmount: transitMinAmountOut!, slippage: slippage)
        let newWSOLAccount = swapTransaction.signers[1]
        let transitTokenPublicKey = try RelayProgram.getTransitTokenAccountAddress(
            user: .owner,
            transitTokenMint: .btcMint,
            network: .mainnetBeta
        )
        XCTAssertEqual(swapTransaction.transaction.instructions[3], .init( // direct swap
            keys: [
                .writable(publicKey: .feePayerAddress, isSigner: true),
                .readonly(publicKey: TokenProgram.id, isSigner: false),
                .readonly(publicKey: .owner, isSigner: true),
                .writable(publicKey: newWSOLAccount.publicKey, isSigner: false),
                .writable(publicKey: transitTokenPublicKey, isSigner: false),
                .writable(publicKey: .ethAssociatedAddress, isSigner: false),
                
                .readonly(publicKey: "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP", isSigner: false),
                .readonly(publicKey: Pool.solBTC.account.publicKey, isSigner: false),
                .readonly(publicKey: Pool.solBTC.authority.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.tokenAccountA.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.tokenAccountB.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.poolTokenMint.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.feeAccount.publicKey, isSigner: false),
                
                .readonly(publicKey: "DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1", isSigner: false),
                .readonly(publicKey: Pool.btcETH.account.publicKey, isSigner: false),
                .readonly(publicKey: Pool.btcETH.authority.publicKey, isSigner: false),
                .writable(publicKey: Pool.btcETH.tokenAccountA.publicKey, isSigner: false),
                .writable(publicKey: Pool.btcETH.tokenAccountB.publicKey, isSigner: false),
                .writable(publicKey: Pool.btcETH.poolTokenMint.publicKey, isSigner: false),
                .writable(publicKey: Pool.btcETH.feeAccount.publicKey, isSigner: false)
            ],
            programId: RelayProgram.id(network: .mainnetBeta),
            data: [RelayProgram.Index.transitiveSwap] + inputAmount.bytes + transitMinAmountOut!.bytes + minAmountOut!.bytes)
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
    
    func testBuildTransitiveSwapSPLToNonCreatedSPLToken() async throws {
        swapTransactionBuilder = .init(
            network: .mainnetBeta,
            transitTokenAccountManager: MockTransitTokenAccountManager(testCase: 2),
            destinationManager: MockDestinationFinder(testCase: 2),
            orcaSwap: MockOrcaSwapBase(),
            feePayerAddress: .feePayerAddress,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            lamportsPerSignature: lamportsPerSignature
        )
        
        // BTC -> SOL -> ETH
        let inputAmount: UInt64 = 100000000000
        let slippage: Double = 0.1
        
        let output = try await swapTransactionBuilder.prepareSwapTransaction(
            input: .init(
                userAccount: accountStorage.account!,
                pools: [.solBTC.reversed, .ethSOL.reversed],
                inputAmount: inputAmount,
                slippage: slippage,
                sourceTokenAccount: .init(address: .btcAssociatedAddress, mint: .btcMint),
                destinationTokenMint: .ethMint,
                destinationTokenAddress: nil,
                blockhash: blockhash
            )
        )
        
        XCTAssertEqual(output.additionalPaybackFee, 0) // No WSOL creation
        
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
        // - - Transitve Swap instruction
        let transitMinAmountOut = try Pool.solBTC.reversed.getMinimumAmountOut(inputAmount: inputAmount, slippage: slippage)
        let minAmountOut = try Pool.ethSOL.reversed.getMinimumAmountOut(inputAmount: transitMinAmountOut!, slippage: slippage)
        let transitTokenPublicKey = try RelayProgram.getTransitTokenAccountAddress(
            user: .owner,
            transitTokenMint: .wrappedSOLMint,
            network: .mainnetBeta
        )
        XCTAssertEqual(swapTransaction.transaction.instructions[1], .init(
            keys: [
                .writable(publicKey: .feePayerAddress, isSigner: true),
                .readonly(publicKey: TokenProgram.id, isSigner: false),
                .readonly(publicKey: .owner, isSigner: true),
                .writable(publicKey: .btcAssociatedAddress, isSigner: false),
                .writable(publicKey: transitTokenPublicKey, isSigner: false),
                .writable(publicKey: .ethAssociatedAddress, isSigner: false),
                
                .readonly(publicKey: "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP", isSigner: false),
                .readonly(publicKey: Pool.solBTC.reversed.account.publicKey, isSigner: false),
                .readonly(publicKey: Pool.solBTC.reversed.authority.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.reversed.tokenAccountA.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.reversed.tokenAccountB.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.reversed.poolTokenMint.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.reversed.feeAccount.publicKey, isSigner: false),
                
                .readonly(publicKey: "DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1", isSigner: false),
                .readonly(publicKey: Pool.ethSOL.reversed.account.publicKey, isSigner: false),
                .readonly(publicKey: Pool.ethSOL.reversed.authority.publicKey, isSigner: false),
                .writable(publicKey: Pool.ethSOL.reversed.tokenAccountA.publicKey, isSigner: false),
                .writable(publicKey: Pool.ethSOL.reversed.tokenAccountB.publicKey, isSigner: false),
                .writable(publicKey: Pool.ethSOL.reversed.poolTokenMint.publicKey, isSigner: false),
                .writable(publicKey: Pool.ethSOL.reversed.feeAccount.publicKey, isSigner: false)
            ],
            programId: RelayProgram.id(network: .mainnetBeta),
            data: [RelayProgram.Index.transitiveSwap] + inputAmount.bytes + transitMinAmountOut!.bytes + minAmountOut!.bytes)
        )
    }
    
    func testBuildTransitiveSwapSPLToCreatedSPLToken() async throws {
        swapTransactionBuilder = .init(
            network: .mainnetBeta,
            transitTokenAccountManager: MockTransitTokenAccountManager(testCase: 3),
            destinationManager: MockDestinationFinder(testCase: 3),
            orcaSwap: MockOrcaSwapBase(),
            feePayerAddress: .feePayerAddress,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            lamportsPerSignature: lamportsPerSignature
        )
        
        // BTC -> SOL -> ETH
        let inputAmount: UInt64 = 100000000000
        let slippage: Double = 0.1
        
        let output = try await swapTransactionBuilder.prepareSwapTransaction(
            input: .init(
                userAccount: accountStorage.account!,
                pools: [.solBTC.reversed, .ethSOL.reversed],
                inputAmount: inputAmount,
                slippage: slippage,
                sourceTokenAccount: .init(address: .btcAssociatedAddress, mint: .btcMint),
                destinationTokenMint: .ethMint,
                destinationTokenAddress: nil,
                blockhash: blockhash
            )
        )
        
        XCTAssertEqual(output.additionalPaybackFee, 0) // No WSOL creation
        
        XCTAssertEqual(output.transactions.count, 1)
        
        // - Swap transaction
        let swapTransaction = output.transactions[0]
        XCTAssertEqual(swapTransaction.signers.count, 1) // owner only
        XCTAssertEqual(swapTransaction.signers[0], accountStorage.account)
        XCTAssertEqual(swapTransaction.expectedFee, .init(transaction: 10000, accountBalances: 0)) // payer's, owner's signatures + SPL account creation fee
        XCTAssertEqual(swapTransaction.transaction.feePayer, .feePayerAddress)
        XCTAssertEqual(swapTransaction.transaction.recentBlockhash, blockhash)
        XCTAssertEqual(swapTransaction.transaction.instructions.count, 1)
        // - - Transitve Swap instruction
        let transitMinAmountOut = try Pool.solBTC.reversed.getMinimumAmountOut(inputAmount: inputAmount, slippage: slippage)
        let minAmountOut = try Pool.ethSOL.reversed.getMinimumAmountOut(inputAmount: transitMinAmountOut!, slippage: slippage)
        let transitTokenPublicKey = try RelayProgram.getTransitTokenAccountAddress(
            user: .owner,
            transitTokenMint: .wrappedSOLMint,
            network: .mainnetBeta
        )
        XCTAssertEqual(swapTransaction.transaction.instructions[0], .init(
            keys: [
                .writable(publicKey: .feePayerAddress, isSigner: true),
                .readonly(publicKey: TokenProgram.id, isSigner: false),
                .readonly(publicKey: .owner, isSigner: true),
                .writable(publicKey: .btcAssociatedAddress, isSigner: false),
                .writable(publicKey: transitTokenPublicKey, isSigner: false),
                .writable(publicKey: .ethAssociatedAddress, isSigner: false),
                
                .readonly(publicKey: "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP", isSigner: false),
                .readonly(publicKey: Pool.solBTC.reversed.account.publicKey, isSigner: false),
                .readonly(publicKey: Pool.solBTC.reversed.authority.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.reversed.tokenAccountA.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.reversed.tokenAccountB.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.reversed.poolTokenMint.publicKey, isSigner: false),
                .writable(publicKey: Pool.solBTC.reversed.feeAccount.publicKey, isSigner: false),
                
                .readonly(publicKey: "DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1", isSigner: false),
                .readonly(publicKey: Pool.ethSOL.reversed.account.publicKey, isSigner: false),
                .readonly(publicKey: Pool.ethSOL.reversed.authority.publicKey, isSigner: false),
                .writable(publicKey: Pool.ethSOL.reversed.tokenAccountA.publicKey, isSigner: false),
                .writable(publicKey: Pool.ethSOL.reversed.tokenAccountB.publicKey, isSigner: false),
                .writable(publicKey: Pool.ethSOL.reversed.poolTokenMint.publicKey, isSigner: false),
                .writable(publicKey: Pool.ethSOL.reversed.feeAccount.publicKey, isSigner: false)
            ],
            programId: RelayProgram.id(network: .mainnetBeta),
            data: [RelayProgram.Index.transitiveSwap] + inputAmount.bytes + transitMinAmountOut!.bytes + minAmountOut!.bytes)
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
        case .ethMint where testCase == 0 || testCase == 2:
            return DestinationFinderResult(
                destination: .init(address: .ethAssociatedAddress, mint: .ethMint),
                destinationOwner: owner,
                needsCreation: true
            )
        case .ethMint where testCase == 1 || testCase == 3:
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
    private let testCase: Int

    init(testCase: Int) {
        self.testCase = testCase
    }
    
    func getTransitToken(pools: OrcaSwapSwift.PoolsPair) throws -> FeeRelayerSwift.TokenAccount? {
        let mint: PublicKey
        switch testCase {
        case 0, 1:
            mint = .btcMint
        case 2, 3:
            mint = .wrappedSOLMint
        default:
            fatalError()
        }
        let address = try RelayProgram.getTransitTokenAccountAddress(
            user: .owner,
            transitTokenMint: mint,
            network: .mainnetBeta
        )
        return .init(address: address, mint: mint)
    }
    
    func checkIfNeedsCreateTransitTokenAccount(transitToken: FeeRelayerSwift.TokenAccount?) async throws -> Bool? {
        false
    }
}
