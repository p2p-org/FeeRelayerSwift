// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension  SwapTransactionBuilder {
    internal static func checkDestination(context: inout BuildContext) async throws {
        var destinationNewAccount: Account?
        var userDestinationTokenAccountAddress = context.destinationToken.address
        
        if context.needsCreateDestinationTokenAccount {
            if context.destinationToken.mint == .wrappedSOLMint {
                // For native solana, create and initialize WSOL
                destinationNewAccount = try await Account(network: context.network)
                context.instructions.append(contentsOf: [
                    SystemProgram.createAccountInstruction(
                        from: context.feeRelayerContext.feePayerAddress,
                        toNewPubkey: destinationNewAccount!.publicKey,
                        lamports: context.feeRelayerContext.minimumTokenAccountBalance,
                        space: AccountInfo.BUFFER_LENGTH,
                        programId: TokenProgram.id
                    ),
                    TokenProgram.initializeAccountInstruction(
                        account: destinationNewAccount!.publicKey,
                        mint: context.destinationToken.mint,
                        owner: try context.userAuthorityAddress
                    ),
                ])
                userDestinationTokenAccountAddress = destinationNewAccount!.publicKey
                context.accountCreationFee += context.feeRelayerContext.minimumTokenAccountBalance
            } else {
                // For other token, create associated token address
                let associatedAddress = try PublicKey.associatedTokenAddress(
                    walletAddress: try context.accountStorage.pubkey,
                    tokenMintAddress: context.destinationToken.mint
                )

                let instruction = try AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
                    mint: context.destinationToken.mint,
                    owner: try context.accountStorage.pubkey,
                    payer: context.feeRelayerContext.feePayerAddress
                )

                // SPECIAL CASE WHEN WE SWAP FROM SOL TO NON-CREATED SPL TOKEN, THEN WE NEEDS ADDITIONAL TRANSACTION BECAUSE TRANSACTION IS TOO LARGE
                if context.sourceWSOLNewAccount != nil {
                    context.additionalTransaction = try makeTransaction(
                        context.feeRelayerContext,
                        instructions: [instruction],
                        signers: [try context.accountStorage.signer],
                        blockhash: context.blockhash,
                        accountCreationFee: context.feeRelayerContext.minimumTokenAccountBalance
                    )
                } else {
                    context.instructions.append(instruction)
                    context.accountCreationFee += context.feeRelayerContext.minimumTokenAccountBalance
                }
                userDestinationTokenAccountAddress = associatedAddress
            }
        }
        
        context.destinationNewAccount = destinationNewAccount
        context.userDestinationTokenAccountAddress = userDestinationTokenAccountAddress
    }
}