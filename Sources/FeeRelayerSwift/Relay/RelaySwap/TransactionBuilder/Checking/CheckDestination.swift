// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension  SwapTransactionBuilder {
    internal static func checkDestination(
        solanaAPIClient: SolanaAPIClient,
        owner: SolanaSwift.Account,
        destinationMint: PublicKey,
        destinationAddress: PublicKey?,
        feePayerAddress: PublicKey,
        relayContext: RelayContext,
        recentBlockhash: String,
        env: inout BuildContext.Environment
    ) async throws {
        var destinationNewAccount: Account?
        
        let destinationManager = DestinationFinderImpl(solanaAPIClient: solanaAPIClient)
        
        let destinationInfo = try await destinationManager.findRealDestination(
            owner: owner.publicKey,
            mint: destinationMint,
            givenDestination: destinationAddress
        )
        
        var userDestinationTokenAccountAddress = destinationInfo.destination.address
        
        if destinationInfo.needsCreation {
            if destinationInfo.destination.mint == .wrappedSOLMint {
                // For native solana, create and initialize WSOL
                destinationNewAccount = try await Account(network: solanaAPIClient.endpoint.network)
                env.instructions.append(contentsOf: [
                    SystemProgram.createAccountInstruction(
                        from: feePayerAddress,
                        toNewPubkey: destinationNewAccount!.publicKey,
                        lamports: relayContext.minimumTokenAccountBalance,
                        space: AccountInfo.BUFFER_LENGTH,
                        programId: TokenProgram.id
                    ),
                    TokenProgram.initializeAccountInstruction(
                        account: destinationNewAccount!.publicKey,
                        mint:  destinationInfo.destination.mint,
                        owner: owner.publicKey
                    ),
                ])
                userDestinationTokenAccountAddress = destinationNewAccount!.publicKey
                env.accountCreationFee += relayContext.minimumTokenAccountBalance
            } else {
                // For other token, create associated token address
                let associatedAddress = try PublicKey.associatedTokenAddress(
                    walletAddress: owner.publicKey,
                    tokenMintAddress:  destinationInfo.destination.mint
                )

                let instruction = try AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
                    mint:  destinationInfo.destination.mint,
                    owner: owner.publicKey,
                    payer: feePayerAddress
                )

                // SPECIAL CASE WHEN WE SWAP FROM SOL TO NON-CREATED SPL TOKEN, THEN WE NEEDS ADDITIONAL TRANSACTION BECAUSE TRANSACTION IS TOO LARGE
                if env.sourceWSOLNewAccount != nil {
                    env.additionalTransaction = try makeTransaction(
                        relayContext,
                        instructions: [instruction],
                        signers: [owner],
                        blockhash: recentBlockhash,
                        accountCreationFee: relayContext.minimumTokenAccountBalance
                    )
                } else {
                    env.instructions.append(instruction)
                    env.accountCreationFee += relayContext.minimumTokenAccountBalance
                }
                userDestinationTokenAccountAddress = associatedAddress
            }
        }
        
        env.destinationNewAccount = destinationNewAccount
        env.userDestinationTokenAccountAddress = userDestinationTokenAccountAddress
    }
}
