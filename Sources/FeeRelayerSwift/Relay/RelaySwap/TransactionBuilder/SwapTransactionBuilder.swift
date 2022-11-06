// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

internal enum SwapTransactionBuilder {
    internal static func prepareSwapTransaction(
        userAccount: Account,
        sourceTokenAccount: TokenAccount,
        destinationTokenMint: PublicKey,
        destinationAddress: PublicKey?,
        poolsPair: PoolsPair,
        inputAmount: UInt64,
        slippage: Double,
        solanaAPIClient: SolanaAPIClient,
        orcaSwap: OrcaSwapType,
        relayContext: RelayContext,
        blockhash: String,
        env: inout BuildContext.Environment
    ) async throws -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
        env.userSource = sourceTokenAccount.address
        
        let associatedToken = try PublicKey.associatedTokenAddress(
            walletAddress: relayContext.feePayerAddress,
            tokenMintAddress: sourceTokenAccount.mint
        )
        guard env.userSource != associatedToken else { throw FeeRelayerError.wrongAddress }

        // check transit token
        try await checkTransitTokenAccount(
            solanaAPIClient: solanaAPIClient,
            orcaSwap: orcaSwap,
            owner: userAccount.publicKey,
            poolsPair: poolsPair,
            env: &env
        )
        
        // check source
        try await checkSource(
            owner: userAccount.publicKey,
            sourceMint: sourceTokenAccount.mint,
            inputAmount: inputAmount,
            network: solanaAPIClient.endpoint.network,
            feePayer: relayContext.feePayerAddress,
            minimumTokenAccountBalance: relayContext.minimumTokenAccountBalance,
            env: &env
        )
    
        // check destination
        try await checkDestination(
            solanaAPIClient: solanaAPIClient,
            owner: userAccount,
            destinationMint: destinationTokenMint,
            destinationAddress: destinationAddress,
            feePayerAddress: relayContext.feePayerAddress,
            relayContext: relayContext,
            recentBlockhash: blockhash,
            env: &env
        )
    
        // build swap data
        let swapData = try await buildSwapData(
            userAccount: userAccount,
            network: solanaAPIClient.endpoint.network,
            pools: poolsPair,
            inputAmount: inputAmount,
            minAmountOut: nil,
            slippage: slippage,
            transitTokenMintPubkey: env.transitTokenMintPubkey,
            needsCreateTransitTokenAccount: env.needsCreateTransitTokenAccount == true
        )
        
        // check swap data
        try checkSwapData(
            network: solanaAPIClient.endpoint.network,
            owner: userAccount.publicKey,
            feePayerAddress: relayContext.feePayerAddress,
            poolsPair: poolsPair,
            env: &env,
            swapData: swapData
        )
    
        // closing accounts
        try checkClosingAccount(
            owner: userAccount.publicKey,
            feePayer: relayContext.feePayerAddress,
            destinationTokenMint: destinationTokenMint,
            minimumTokenAccountBalance: relayContext.minimumTokenAccountBalance,
            env: &env
        )
        
        // check signers
        checkSigners(
            ownerAccount: userAccount,
            env: &env
        )
    
        var transactions: [PreparedTransaction] = []
        
        // include additional transaciton
        if let additionalTransaction = env.additionalTransaction { transactions.append(additionalTransaction) }
        
        // make primary transaction
        transactions.append(
            try makeTransaction(
                relayContext,
                instructions: env.instructions,
                signers: env.signers,
                blockhash: blockhash,
                accountCreationFee: env.accountCreationFee
            )
        )
        
        return (transactions: transactions, additionalPaybackFee: env.additionalPaybackFee)
    }
    
    internal static func makeTransaction(
        _ context: RelayContext,
        instructions: [TransactionInstruction],
        signers: [Account],
        blockhash: String,
        accountCreationFee: UInt64
    ) throws -> PreparedTransaction {
        var transaction = Transaction()
        transaction.instructions = instructions
        transaction.recentBlockhash = blockhash
        transaction.feePayer = context.feePayerAddress
    
        try transaction.sign(signers: signers)
        
        // calculate fee first
        let expectedFee = FeeAmount(
            transaction: try transaction.calculateTransactionFee(lamportsPerSignatures: context.lamportsPerSignature),
            accountBalances: accountCreationFee
        )
        
        return .init(transaction: transaction, signers: signers, expectedFee: expectedFee)
    }
}
