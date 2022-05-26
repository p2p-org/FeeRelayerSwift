// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

internal enum SwapTransactionBuilder {
    struct BuildContext {
        let feeRelayerContext: FeeRelayerContext
        
        // Configuration
        let network: Network
        let accountStorage: SolanaAccountStorage
        
        let pools: PoolsPair
        let inputAmount: UInt64
        let slippage: Double
        
        let sourceToken: TokenAccount
        let destinationToken: TokenAccount
        let transitTokenMintPubkey: PublicKey
        let transitTokenAccountAddress: PublicKey
        
        let needsCreateDestinationTokenAccount: Bool
        let needsCreateTransitTokenAccount: Bool?
        
        let blockhash: String
        
        // Building vars
        var userSource: PublicKey? = nil
        var sourceWSOLNewAccount: Account? = nil
        
        var destinationNewAccount: Account? = nil
        var userDestinationTokenAccountAddress: PublicKey? = nil
        
        var instructions = [TransactionInstruction]()
        var additionalTransaction: PreparedTransaction? = nil
        
        var signers: [Account] = []
        
        // Building fee
        var accountCreationFee: Lamports = 0
        var additionalPaybackFee: UInt64 = 0
        
        // Quicky access
        var userAuthorityAddress: PublicKey { get throws { try accountStorage.pubkey } }
    }
    
    internal static func prepareSwapTransaction(_ context: inout BuildContext) async throws -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
        context.userSource = context.sourceToken.address
        
        let associatedToken = try PublicKey.associatedTokenAddress(
            walletAddress: context.feeRelayerContext.feePayerAddress,
            tokenMintAddress: context.sourceToken.mint
        )
        guard context.userSource != associatedToken else { throw FeeRelayerError.wrongAddress }

        // check source
        try await checkSource(&context)
    
        // check destination
        try await checkDestination(context: &context)
    
        // build swap data
        try checkSwapData(
                context: &context,
                swapData: try buildSwapData(
                accountStorage: context.accountStorage,
                network: context.network,
                pools: context.pools,
                inputAmount: context.inputAmount,
                minAmountOut: nil,
                slippage: context.slippage,
                transitTokenMintPubkey: context.transitTokenMintPubkey,
                needsCreateTransitTokenAccount: context.needsCreateTransitTokenAccount == true
            )
        )
    
        // closing accounts
        try checkClosingAccount(&context)
        
        // check signers
        try checkSigners(context: &context)
    
        var transactions: [PreparedTransaction] = []
        
        if let additionalTransaction = context.additionalTransaction {
            transactions.append(additionalTransaction)
        }
        
        transactions.append(
            try makeTransaction(
                context.feeRelayerContext,
                instructions: context.instructions,
                signers: context.signers,
                blockhash: context.blockhash,
                accountCreationFee: context.accountCreationFee
            )
        )
        
        return (transactions: transactions, additionalPaybackFee: context.additionalPaybackFee)
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
