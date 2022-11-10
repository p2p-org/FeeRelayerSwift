import Foundation
import XCTest
@testable import FeeRelayerSwift
@testable import SolanaSwift
import OrcaSwapSwift

final class SwapTransactionBuilderTests: XCTestCase {
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
    func testBuildSwapSOLToNonCreatedSPL() async throws {
        swapTransactionBuilder = .init(
            solanaAPIClient: MockSolanaAPIClient(testCase: 0),
            orcaSwap: MockOrcaSwapBase(),
            relayContextManager: MockRelayContextManager()
        )
        
        let inputAmount: UInt64 = 1000000
        let slippage: Double = 0.1
        
        let output = try await swapTransactionBuilder.prepareSwapTransaction(
            input: .init(
                userAccount: accountStorage.account!,
                pools: [.solBTC],
                inputAmount: inputAmount,
                slippage: 0.1,
                sourceTokenAccount: .init(address: accountStorage.account!.publicKey, mint: .wrappedSOLMint),
                destinationTokenMint: .btcMint,
                destinationTokenAddress: nil,
                blockhash: blockhash
            )
        )
        
        XCTAssertEqual(output.additionalPaybackFee, minimumTokenAccountBalance)
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
}

private class MockSolanaAPIClient: MockSolanaAPIClientBase {
    private let testCase: Int
    
    init(testCase: Int) {
        self.testCase = testCase
        super.init()
    }
    
    override func getAccountInfo<T>(account: String) async throws -> BufferInfo<T>? where T : BufferLayout {
        switch account {
        case PublicKey.btcAssociatedAddress.base58EncodedString where testCase == 0:
            return nil
        case PublicKey.btcAssociatedAddress.base58EncodedString where testCase == 1:
            let info = BufferInfo<AccountInfo>(
                lamports: 0,
                owner: testCase > 2 ? SystemProgram.id.base58EncodedString: TokenProgram.id.base58EncodedString,
                data: .init(mint: SystemProgram.id, owner: SystemProgram.id, lamports: 0, delegateOption: 0, isInitialized: true, isFrozen: true, state: 0, isNativeOption: 0, rentExemptReserve: nil, isNativeRaw: 0, isNative: true, delegatedAmount: 0, closeAuthorityOption: 0),
                executable: false,
                rentEpoch: 0
            )
            return info as? BufferInfo<T>
        case PublicKey.owner.base58EncodedString:
            let info = BufferInfo<EmptyInfo>(
                lamports: 0,
                owner: SystemProgram.id.base58EncodedString,
                data: .init(),
                executable: false,
                rentEpoch: 0
            )
            return info as? BufferInfo<T>
        default:
            fatalError()
        }
    }
}

private class MockRelayContextManager: MockRelayContextManagerBase {
    override func getCurrentContext() async throws -> RelayContext {
        .init(
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            minimumRelayAccountBalance: minimumRelayAccountBalance,
            feePayerAddress: .feePayerAddress,
            lamportsPerSignature: lamportsPerSignature,
            relayAccountStatus: .notYetCreated, // not important
            usageStatus: .init( // not important
                maxUsage: 10000000,
                currentUsage: 0,
                maxAmount: 10000000,
                amountUsed: 0
            )
        )
    }
}
