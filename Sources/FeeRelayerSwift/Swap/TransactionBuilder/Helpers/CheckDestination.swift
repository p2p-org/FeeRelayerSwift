// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension  SwapTransactionBuilder {
    internal static func checkDestination(context: inout BuildContext) async throws {
        var destinationNewAccount: Account?
        var userDestinationTokenAccountAddress = context.config.destinationAccount.address
        
        if context.config.needsCreateDestinationTokenAccount {
            if context.config.destinationAccount.mint == .wrappedSOLMint {
                // For native solana, create and initialize WSOL
                destinationNewAccount = try await Account(network: context.config.network)
                context.env.instructions.append(contentsOf: [
                    SystemProgram.createAccountInstruction(
                        from: context.feeRelayerContext.feePayerAddress,
                        toNewPubkey: destinationNewAccount!.publicKey,
                        lamports: context.feeRelayerContext.minimumTokenAccountBalance,
                        space: AccountInfo.BUFFER_LENGTH,
                        programId: TokenProgram.id
                    ),
                    TokenProgram.initializeAccountInstruction(
                        account: destinationNewAccount!.publicKey,
                        mint: context.config.destinationAccount.mint,
                        owner: try context.config.userAuthorityAddress
                    ),
                ])
                userDestinationTokenAccountAddress = destinationNewAccount!.publicKey
                context.env.accountCreationFee += context.feeRelayerContext.minimumTokenAccountBalance
            } else {
                // For other token, create associated token address
                let associatedAddress = try PublicKey.associatedTokenAddress(
                    walletAddress: try context.config.accountStorage.pubkey,
                    tokenMintAddress: context.config.destinationAccount.mint
                )

                let instruction = try AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
                    mint: context.config.destinationAccount.mint,
                    owner: try context.config.accountStorage.pubkey,
                    payer: context.feeRelayerContext.feePayerAddress
                )

                // SPECIAL CASE WHEN WE SWAP FROM SOL TO NON-CREATED SPL TOKEN, THEN WE NEEDS ADDITIONAL TRANSACTION BECAUSE TRANSACTION IS TOO LARGE
                if context.env.sourceWSOLNewAccount != nil {
                    context.env.additionalTransaction = try makeTransaction(
                        context.feeRelayerContext,
                        instructions: [instruction],
                        signers: [try context.config.accountStorage.signer],
                        blockhash: context.config.blockhash,
                        accountCreationFee: context.feeRelayerContext.minimumTokenAccountBalance
                    )
                } else {
                    context.env.instructions.append(instruction)
                    context.env.accountCreationFee += context.feeRelayerContext.minimumTokenAccountBalance
                }
                userDestinationTokenAccountAddress = associatedAddress
            }
        }
        
        context.env.destinationNewAccount = destinationNewAccount
        context.env.userDestinationTokenAccountAddress = userDestinationTokenAccountAddress
    }
}