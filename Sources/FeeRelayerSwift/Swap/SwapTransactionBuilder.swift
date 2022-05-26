// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

internal enum SwapTransactionBuilder {
    internal static func prepareSwapTransaction(
        _ context: FeeRelayerContext,
        accountStorage: SolanaAccountStorage,
        network: Network,
        sourceToken: TokenAccount,
        destinationToken: TokenAccount,
        userDestinationAccountOwnerAddress _: PublicKey?,

        pools _: PoolsPair,
        inputAmount: UInt64,
        slippage _: Double,

        feeAmount: UInt64,
        blockhash: String,
        minimumTokenAccountBalance: UInt64,
        needsCreateDestinationTokenAccount: Bool,
        feePayerAddress: PublicKey,

        needsCreateTransitTokenAccount _: Bool?,
        transitTokenMintPubkey _: PublicKey?,
        transitTokenAccountAddress _: PublicKey?
    ) async throws -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
        var userSourceTokenAccountAddress = sourceToken.address
        let userAuthorityAddress = try accountStorage.pubkey
        let associatedToken = try PublicKey.associatedTokenAddress(
            walletAddress: feePayerAddress,
            tokenMintAddress: sourceToken.mint
        )

        var additionalTransaction: PreparedTransaction?
        var accountCreationFee: Lamports = 0
        var instructions = [TransactionInstruction]()
        var additionalPaybackFee: UInt64 = 0

        // check source
        var sourceWSOLNewAccount: Account?
        if sourceToken.mint == PublicKey.wrappedSOLMint {
            sourceWSOLNewAccount = try await Account(network: network)
            instructions.append(contentsOf: [
                SystemProgram.transferInstruction(
                    from: userAuthorityAddress,
                    to: feePayerAddress,
                    lamports: inputAmount
                ),
                SystemProgram.createAccountInstruction(
                    from: feePayerAddress,
                    toNewPubkey: sourceWSOLNewAccount!.publicKey,
                    lamports: context.minimumTokenAccountBalance + inputAmount,
                    space: AccountInfo.BUFFER_LENGTH,
                    programId: TokenProgram.id
                ),
                TokenProgram.initializeAccountInstruction(
                    account: sourceWSOLNewAccount!.publicKey,
                    mint: .wrappedSOLMint,
                    owner: userAuthorityAddress
                ),
            ])
            userSourceTokenAccountAddress = sourceWSOLNewAccount!.publicKey
            additionalPaybackFee += context.minimumTokenAccountBalance
        }

        // check destination
        var destinationNewAccount: Account?
        var userDestinationTokenAccountAddress = destinationToken.address
        if needsCreateDestinationTokenAccount {
            if destinationToken.mint == .wrappedSOLMint {
                // For native solana, create and initialize WSOL
                destinationNewAccount = try await Account(network: network)
                instructions.append(contentsOf: [
                    SystemProgram.createAccountInstruction(
                        from: feePayerAddress,
                        toNewPubkey: destinationNewAccount!.publicKey,
                        lamports: context.minimumTokenAccountBalance,
                        space: AccountInfo.BUFFER_LENGTH,
                        programId: TokenProgram.id
                    ),
                    TokenProgram.initializeAccountInstruction(
                        account: destinationNewAccount!.publicKey,
                        mint: destinationToken.mint,
                        owner: userAuthorityAddress
                    ),
                ])
                userDestinationTokenAccountAddress = destinationNewAccount!.publicKey
                accountCreationFee += context.minimumTokenAccountBalance
            } else {
                // For other token, create associated token address
                let associatedAddress = try PublicKey.associatedTokenAddress(
                    walletAddress: userAuthorityAddress,
                    tokenMintAddress: destinationToken.mint
                )

                let instruction = try AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
                    mint: destinationToken.mint,
                    owner: userAuthorityAddress,
                    payer: feePayerAddress
                )

                // SPECIAL CASE WHEN WE SWAP FROM SOL TO NON-CREATED SPL TOKEN, THEN WE NEEDS ADDITIONAL TRANSACTION BECAUSE TRANSACTION IS TOO LARGE
                if sourceWSOLNewAccount != nil {
                    additionalTransaction = try makeTransaction(
                        context,
                        instructions: [instruction],
                        signers: [try accountStorage.signer],
                        blockhash: blockhash,
                        feePayerAddress: feePayerAddress,
                        accountCreationFee: minimumTokenAccountBalance
                    )
                } else {
                    instructions.append(instruction)
                    accountCreationFee += minimumTokenAccountBalance
                }
                userDestinationTokenAccountAddress = associatedAddress
            }
        }
        
        
    }
    
    internal static func makeTransaction(
        _ context: FeeRelayerContext,
        instructions: [TransactionInstruction],
        signers: [Account],
        blockhash: String,
        feePayerAddress: PublicKey,
        accountCreationFee: UInt64
    ) throws -> PreparedTransaction {
        var transaction = Transaction()
        transaction.instructions = instructions
        transaction.recentBlockhash = blockhash
        transaction.feePayer = feePayerAddress
    
        try transaction.sign(signers: signers)
        
        // calculate fee first
        let expectedFee = FeeAmount(
            transaction: try transaction.calculateTransactionFee(lamportsPerSignatures: context.lamportsPerSignature),
            accountBalances: accountCreationFee
        )
        
        return .init(transaction: transaction, signers: signers, expectedFee: expectedFee)
    }
}
