// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

internal enum SwapTransactionBuilder {
    struct BuildContext {
        let feeRelayerContext: FeeRelayerContext
        
        struct Configuration {
            let solanaApiClient: SolanaAPIClient
            let orcaSwap: OrcaSwap
            
            var network: Network { solanaApiClient.endpoint.network }
            let accountStorage: SolanaAccountStorage
        
            let pools: PoolsPair
            let inputAmount: UInt64
            let slippage: Double
        
            let sourceAccount: TokenAccount
            let destinationTokenMint: PublicKey
            let destinationAddress: PublicKey?
            
            let blockhash: String
            
            // Quicky access
            var userAuthorityAddress: PublicKey { get throws { try accountStorage.pubkey } }
        }
        
        struct Environment {
            var userSource: PublicKey? = nil
            var sourceWSOLNewAccount: Account? = nil
            
            var transitTokenMintPubkey: PublicKey?
            var transitTokenAccountAddress: PublicKey?
            var needsCreateTransitTokenAccount: Bool?
        
            var destinationNewAccount: Account? = nil
            var userDestinationTokenAccountAddress: PublicKey? = nil
        
            var instructions = [TransactionInstruction]()
            var additionalTransaction: PreparedTransaction? = nil
        
            var signers: [Account] = []
        
            // Building fee
            var accountCreationFee: Lamports = 0
            var additionalPaybackFee: UInt64 = 0
        }

        let config: Configuration
        var env: Environment
    }
    
    internal static func prepareSwapTransaction(_ context: inout BuildContext) async throws -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
        context.env.userSource = context.config.sourceAccount.address
        
        let associatedToken = try PublicKey.associatedTokenAddress(
            walletAddress: context.feeRelayerContext.feePayerAddress,
            tokenMintAddress: context.config.sourceAccount.mint
        )
        guard context.env.userSource != associatedToken else { throw FeeRelayerError.wrongAddress }

        // check transit token
        try await checkTransitTokenAccount(&context)
        
        // check source
        try await checkSource(&context)
    
        // check destination
        try await checkDestination(&context)
    
        // build swap data
        try checkSwapData(
            context: &context,
            swapData: try buildSwapData(
                accountStorage: context.config.accountStorage,
                network: context.config.network,
                pools: context.config.pools,
                inputAmount: context.config.inputAmount,
                minAmountOut: nil,
                slippage: context.config.slippage,
                transitTokenMintPubkey: context.env.transitTokenMintPubkey,
                needsCreateTransitTokenAccount: context.env.needsCreateTransitTokenAccount == true
            )
        )
    
        // closing accounts
        try checkClosingAccount(&context)
        
        // check signers
        try checkSigners(&context)
    
        var transactions: [PreparedTransaction] = []
        
        // include additional transaciton
        if let additionalTransaction = context.env.additionalTransaction { transactions.append(additionalTransaction) }
        
        // make primary transaction
        transactions.append(
            try makeTransaction(
                context.feeRelayerContext,
                instructions: context.env.instructions,
                signers: context.env.signers,
                blockhash: context.config.blockhash,
                accountCreationFee: context.env.accountCreationFee
            )
        )
        
        return (transactions: transactions, additionalPaybackFee: context.env.additionalPaybackFee)
    }
    
    internal static func makeTransaction(
        _ context: FeeRelayerContext,
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
