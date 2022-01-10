//
//  File.swift
//  
//
//  Created by Chung Tran on 10/01/2022.
//

import Foundation
import RxSwift
import SolanaSwift

extension FeeRelayer.Relay {
    /// Prepare swap data from topUpPools
    func prepareSwapData(
        topUpPools: OrcaSwap.PoolsPair,
        amount: UInt64,
        transitTokenMintPubkey: SolanaSDK.PublicKey? = nil
    ) throws -> FeeRelayerRelaySwapType {
        // preconditions
        guard topUpPools.count > 0 && topUpPools.count <= 2 else { throw FeeRelayer.Error.swapPoolsNotFound }
        let defaultSlippage = 0.01
        
        // create transferAuthority
        let transferAuthority = try SolanaSDK.Account(network: .mainnetBeta)
        
        // form topUp params
        if topUpPools.count == 1 {
            let pool = topUpPools[0]
            
            guard let amountIn = try pool.getInputAmount(minimumReceiveAmount: amount, slippage: defaultSlippage) else {
                throw FeeRelayer.Error.invalidAmount
            }
            
            let directSwapData = pool.getSwapData(
                transferAuthorityPubkey: transferAuthority.publicKey,
                amountIn: amountIn,
                minAmountOut: amount
            )
            return directSwapData
        } else {
            let firstPool = topUpPools[0]
            let secondPool = topUpPools[1]
            
            guard let transitTokenMintPubkey = transitTokenMintPubkey,
                  let secondPoolAmountIn = try secondPool.getInputAmount(minimumReceiveAmount: amount, slippage: defaultSlippage),
                  let firstPoolAmountIn = try firstPool.getInputAmount(minimumReceiveAmount: secondPoolAmountIn, slippage: defaultSlippage)
            else {
                throw FeeRelayer.Error.transitTokenMintNotFound
            }
            
            let transitiveSwapData = TransitiveSwapData(
                from: firstPool.getSwapData(
                    transferAuthorityPubkey: transferAuthority.publicKey,
                    amountIn: firstPoolAmountIn,
                    minAmountOut: secondPoolAmountIn
                ),
                to: secondPool.getSwapData(
                    transferAuthorityPubkey: transferAuthority.publicKey,
                    amountIn: secondPoolAmountIn,
                    minAmountOut: amount
                ),
                transitTokenMintPubkey: transitTokenMintPubkey.base58EncodedString
            )
            return transitiveSwapData
        }
    }
    
    /// Calculate needed fee for topup transaction by forming fake transaction
    func calculateTopUpFee(
        userSourceTokenAccountAddress: String,
        sourceTokenMintAddress: String,
        userAuthorityAddress: SolanaSDK.PublicKey,
        userRelayAddress: SolanaSDK.PublicKey,
        topUpPools: OrcaSwap.PoolsPair,
        amount: UInt64,
        transitTokenMintPubkey: SolanaSDK.PublicKey? = nil,
        minimumRelayAccountBalance: UInt64,
        minimumTokenAccountBalance: UInt64,
        needsCreateUserRelayAccount: Bool,
        feePayerAddress: String,
        lamportsPerSignature: UInt64
    ) throws -> UInt64 {
        let fee = try prepareForTopUp(
            userSourceTokenAccountAddress: userSourceTokenAccountAddress,
            sourceTokenMintAddress: sourceTokenMintAddress,
            userAuthorityAddress: userAuthorityAddress,
            userRelayAddress: userRelayAddress,
            topUpPools: topUpPools,
            amount: amount,
            transitTokenMintPubkey: transitTokenMintPubkey,
            feeAmount: 0, // fake
            blockhash: "FR1GgH83nmcEdoNXyztnpUL2G13KkUv6iwJPwVfnqEgW", // fake
            minimumRelayAccountBalance: minimumRelayAccountBalance,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            needsCreateUserRelayAccount: needsCreateUserRelayAccount,
            feePayerAddress: feePayerAddress,
            lamportsPerSignature: lamportsPerSignature
        ).1
        return fee.transaction + fee.accountBalances
    }
    
    /// Prepare transaction and expected fee for a given relay transaction
    func prepareForTopUp(
        userSourceTokenAccountAddress: String,
        sourceTokenMintAddress: String,
        userAuthorityAddress: SolanaSDK.PublicKey,
        userRelayAddress: SolanaSDK.PublicKey,
        topUpPools: OrcaSwap.PoolsPair,
        amount: UInt64,
        transitTokenMintPubkey: SolanaSDK.PublicKey? = nil,
        feeAmount: UInt64,
        blockhash: String,
        minimumRelayAccountBalance: UInt64,
        minimumTokenAccountBalance: UInt64,
        needsCreateUserRelayAccount: Bool,
        feePayerAddress: String,
        lamportsPerSignature: UInt64
    ) throws -> (SolanaSDK.Transaction, FeeRelayer.FeeAmount) {
        // assertion
        guard let userSourceTokenAccountAddress = try? SolanaSDK.PublicKey(string: userSourceTokenAccountAddress),
              let sourceTokenMintAddress = try? SolanaSDK.PublicKey(string: sourceTokenMintAddress),
              let feePayerAddress = try? SolanaSDK.PublicKey(string: feePayerAddress),
              let associatedTokenAddress = try? SolanaSDK.PublicKey.associatedTokenAddress(walletAddress: feePayerAddress, tokenMintAddress: sourceTokenMintAddress),
              userSourceTokenAccountAddress != associatedTokenAddress
        else { throw FeeRelayer.Error.wrongAddress }
        
        // forming transaction and count fees
        var expectedFee = FeeRelayer.FeeAmount(transaction: 0, accountBalances: 0)
        var instructions = [SolanaSDK.TransactionInstruction]()
        
        // create user relay account
        if needsCreateUserRelayAccount {
            instructions.append(
                SolanaSDK.SystemProgram.transferInstruction(
                    from: feePayerAddress,
                    to: userRelayAddress,
                    lamports: minimumRelayAccountBalance
                )
            )
            expectedFee.accountBalances += minimumRelayAccountBalance
        }
        
        // top up swap
        let topUpSwap = try prepareSwapData(topUpPools: topUpPools, amount: amount, transitTokenMintPubkey: transitTokenMintPubkey)
        switch topUpSwap {
        case let swap as DirectSwapData:
            expectedFee.accountBalances += minimumTokenAccountBalance
            // approve
            instructions.append(
                SolanaSDK.TokenProgram.approveInstruction(
                    tokenProgramId: .tokenProgramId,
                    account: userSourceTokenAccountAddress,
                    delegate: try SolanaSDK.PublicKey(string: swap.transferAuthorityPubkey),
                    owner: userAuthorityAddress,
                    amount: swap.amountIn
                )
            )
            
            // top up
            instructions.append(
                try Program.topUpSwapInstruction(
                    topUpSwap: swap,
                    userAuthorityAddress: userAuthorityAddress,
                    userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                    feePayerAddress: feePayerAddress
                )
            )
            
            // transfer
            instructions.append(
                try Program.transferSolInstruction(
                    topUpSwap: swap,
                    userAuthorityAddress: userAuthorityAddress,
                    recipient: feePayerAddress,
                    lamports: feeAmount
                )
            )
        case let swap as TransitiveSwapData:
            // approve
            instructions.append(
                SolanaSDK.TokenProgram.approveInstruction(
                    tokenProgramId: .tokenProgramId,
                    account: userSourceTokenAccountAddress,
                    delegate: try SolanaSDK.PublicKey(string: swap.from.transferAuthorityPubkey),
                    owner: userAuthorityAddress,
                    amount: swap.from.amountIn
                )
            )
            // create transit token account
            let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
                user: userAuthorityAddress,
                transitTokenMint: try SolanaSDK.PublicKey(string: swap.transitTokenMintPubkey)
            )
            instructions.append(
                try Program.createTransitTokenAccountInstruction(
                    feePayer: feePayerAddress,
                    userAuthority: userAuthorityAddress,
                    transitTokenAccount: transitTokenAccountAddress,
                    transitTokenMint: try SolanaSDK.PublicKey(string: swap.transitTokenMintPubkey)
                )
            )
            
            // Destination WSOL account funding
            expectedFee.accountBalances += minimumTokenAccountBalance
            
            // top up
            instructions.append(
                try Program.topUpSwapInstruction(
                    topUpSwap: swap,
                    userAuthorityAddress: userAuthorityAddress,
                    userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                    feePayerAddress: feePayerAddress
                )
            )
            
            // close transit token account
            instructions.append(
                SolanaSDK.TokenProgram.closeAccountInstruction(
                    account: transitTokenAccountAddress,
                    destination: feePayerAddress,
                    owner: feePayerAddress
                )
            )
            
            // transfer
            instructions.append(
                try Program.transferSolInstruction(
                    topUpSwap: swap,
                    userAuthorityAddress: userAuthorityAddress,
                    recipient: feePayerAddress,
                    lamports: feeAmount
                )
            )
        default:
            fatalError("unsupported swap type")
        }
        
        var transaction = SolanaSDK.Transaction()
        transaction.instructions = instructions
        transaction.feePayer = feePayerAddress
        transaction.recentBlockhash = blockhash
        let transactionFee = try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignature)
        expectedFee.transaction = transactionFee
        
        return (transaction, expectedFee)
    }
}

private extension OrcaSwap.Pool {
    func getSwapData(
        transferAuthorityPubkey: SolanaSDK.PublicKey,
        amountIn: UInt64,
        minAmountOut: UInt64
    ) -> FeeRelayer.Relay.DirectSwapData {
        .init(
            programId: swapProgramId.base58EncodedString,
            accountPubkey: account,
            authorityPubkey: authority,
            transferAuthorityPubkey: transferAuthorityPubkey.base58EncodedString,
            sourcePubkey: tokenAccountA,
            destinationPubkey: tokenAccountB,
            poolTokenMintPubkey: poolTokenMint,
            poolFeeAccountPubkey: feeAccount,
            amountIn: amountIn,
            minimumAmountOut: minAmountOut
        )
    }
}
