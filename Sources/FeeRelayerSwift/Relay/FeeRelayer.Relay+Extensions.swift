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
    // MARK: - Top up
    /// Prepare swap data from topUpPools
    func prepareSwapData(
        network: SolanaSDK.Network,
        pools: OrcaSwap.PoolsPair,
        amount: UInt64,
        slippage: Double,
        transitTokenMintPubkey: SolanaSDK.PublicKey? = nil
    ) throws -> (swapData: FeeRelayerRelaySwapType, transferAuthorityAccount: SolanaSDK.Account) {
        // preconditions
        guard pools.count > 0 && pools.count <= 2 else { throw FeeRelayer.Error.swapPoolsNotFound }
        
        // create transferAuthority
        let transferAuthority = try SolanaSDK.Account(network: network)
        
        // form topUp params
        if pools.count == 1 {
            let pool = pools[0]
            
            guard let amountIn = try pool.getInputAmount(minimumReceiveAmount: amount, slippage: slippage) else {
                throw FeeRelayer.Error.invalidAmount
            }
            
            let directSwapData = pool.getSwapData(
                transferAuthorityPubkey: transferAuthority.publicKey,
                amountIn: amountIn,
                minAmountOut: amount
            )
            return (swapData: directSwapData, transferAuthorityAccount: transferAuthority)
        } else {
            let firstPool = pools[0]
            let secondPool = pools[1]
            
            guard let transitTokenMintPubkey = transitTokenMintPubkey,
                  let secondPoolAmountIn = try secondPool.getInputAmount(minimumReceiveAmount: amount, slippage: slippage),
                  let firstPoolAmountIn = try firstPool.getInputAmount(minimumReceiveAmount: secondPoolAmountIn, slippage: slippage)
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
            return (swapData: transitiveSwapData, transferAuthorityAccount: transferAuthority)
        }
    }
    
    /// Calculate needed fee for topup transaction by forming fake transaction
    func calculateTopUpFee(
        network: SolanaSDK.Network,
        sourceToken: TokenInfo,
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
            network: network,
            sourceToken: sourceToken,
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
        ).feeAmount
        return fee.transaction + fee.accountBalances
    }
    
    /// Prepare transaction and expected fee for a given relay transaction
    func prepareForTopUp(
        network: SolanaSDK.Network,
        sourceToken: TokenInfo,
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
    ) throws -> PreparedParams {
        // assertion
        guard let userSourceTokenAccountAddress = try? SolanaSDK.PublicKey(string: sourceToken.address),
              let sourceTokenMintAddress = try? SolanaSDK.PublicKey(string: sourceToken.mint),
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
        let topUpSwap = try prepareSwapData(network: network, pools: topUpPools, amount: amount, slippage: 0.01, transitTokenMintPubkey: transitTokenMintPubkey)
        switch topUpSwap.swapData {
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
        
        return .init(
            swapData: topUpSwap.swapData,
            transaction: transaction,
            feeAmount: expectedFee,
            transferAuthorityAccount: topUpSwap.transferAuthorityAccount
        )
    }
    
    // MARK: - Swap
    func calculateSwappingFee(
        network: SolanaSDK.Network,
        sourceToken: TokenInfo,
        destinationToken: TokenInfo,
        userAuthorityAddress: SolanaSDK.PublicKey,
        userDestinationAccountOwnerAddress: String?,
        
        pools: OrcaSwap.PoolsPair,
        inputAmount: UInt64,
        slippage: Double,
        transitTokenMintPubkey: SolanaSDK.PublicKey? = nil,
        
        minimumTokenAccountBalance: UInt64,
        needsCreateDestinationTokenAccount: Bool,
        feePayerAddress: String,
        lamportsPerSignature: UInt64
    ) throws -> UInt64 {
        let fee = try prepareForSwapping(
            network: network,
            sourceToken: sourceToken,
            destinationToken: destinationToken,
            userAuthorityAddress: userAuthorityAddress,
            userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress,
            pools: pools,
            inputAmount: inputAmount,
            slippage: slippage,
            transitTokenMintPubkey: transitTokenMintPubkey,
            feeAmount: 0, // fake
            blockhash: "FR1GgH83nmcEdoNXyztnpUL2G13KkUv6iwJPwVfnqEgW", //fake
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount,
            feePayerAddress: feePayerAddress,
            lamportsPerSignature: lamportsPerSignature
        ).feeAmount
        return fee.transaction + fee.accountBalances
    }
    
    func prepareForSwapping(
        network: SolanaSDK.Network,
        sourceToken: TokenInfo,
        destinationToken: TokenInfo,
        userAuthorityAddress: SolanaSDK.PublicKey,
        userDestinationAccountOwnerAddress: String?,
        
        pools: OrcaSwap.PoolsPair,
        inputAmount: UInt64,
        slippage: Double,
        transitTokenMintPubkey: SolanaSDK.PublicKey? = nil,
        
        feeAmount: UInt64,
        blockhash: String,
        minimumTokenAccountBalance: UInt64,
        needsCreateDestinationTokenAccount: Bool,
        feePayerAddress: String,
        lamportsPerSignature: UInt64
    ) throws -> PreparedParams {
        // assertion
        guard let userSourceTokenAccountAddress = try? SolanaSDK.PublicKey(string: sourceToken.address),
              let sourceTokenMintAddress = try? SolanaSDK.PublicKey(string: sourceToken.mint),
              let feePayerAddress = try? SolanaSDK.PublicKey(string: feePayerAddress),
              let associatedTokenAddress = try? SolanaSDK.PublicKey.associatedTokenAddress(walletAddress: feePayerAddress, tokenMintAddress: sourceTokenMintAddress),
              userSourceTokenAccountAddress != associatedTokenAddress
        else { throw FeeRelayer.Error.wrongAddress }
        let destinationTokenMintAddress = try SolanaSDK.PublicKey(string: destinationToken.mint)
        
        // forming transaction and count fees
        var expectedFee = FeeRelayer.FeeAmount(transaction: 0, accountBalances: 0)
        var instructions = [SolanaSDK.TransactionInstruction]()
        
        // create destination address
        var userDestinationTokenAccountAddress = destinationToken.address
        if needsCreateDestinationTokenAccount {
            let associatedAccount = try SolanaSDK.PublicKey.associatedTokenAddress(
                walletAddress: try SolanaSDK.PublicKey(string: destinationToken.address),
                tokenMintAddress: destinationTokenMintAddress
            )
            instructions.append(
                SolanaSDK.AssociatedTokenProgram
                    .createAssociatedTokenAccountInstruction(
                        mint: destinationTokenMintAddress,
                        associatedAccount: associatedAccount,
                        owner: feePayerAddress,
                        payer: feePayerAddress
                    )
            )
            expectedFee.accountBalances += minimumTokenAccountBalance
            userDestinationTokenAccountAddress = associatedAccount.base58EncodedString
        }
        
        // swap
        let swap = try prepareSwapData(network: network, pools: pools, amount: inputAmount, slippage: slippage, transitTokenMintPubkey: transitTokenMintPubkey)
        let userTransferAuthority = swap.transferAuthorityAccount.publicKey
        
        switch swap.swapData {
        case let swap as DirectSwapData:
            guard let pool = pools.first else {throw FeeRelayer.Error.swapPoolsNotFound}
            
            // approve
            instructions.append(
                SolanaSDK.TokenProgram.approveInstruction(
                    tokenProgramId: .tokenProgramId,
                    account: userSourceTokenAccountAddress,
                    delegate: userTransferAuthority,
                    owner: userAuthorityAddress,
                    amount: swap.amountIn
                )
            )
            
            // swap
            instructions.append(
                try pool.createSwapInstruction(
                    userTransferAuthorityPubkey: userTransferAuthority,
                    sourceTokenAddress: userSourceTokenAccountAddress,
                    destinationTokenAddress: try SolanaSDK.PublicKey(string: userDestinationTokenAccountAddress),
                    amountIn: swap.amountIn,
                    minAmountOut: swap.minimumAmountOut
                )
            )
        case let swap as TransitiveSwapData:
            // approve
            instructions.append(
                SolanaSDK.TokenProgram.approveInstruction(
                    tokenProgramId: .tokenProgramId,
                    account: userSourceTokenAccountAddress,
                    delegate: userTransferAuthority,
                    owner: userAuthorityAddress,
                    amount: swap.from.amountIn
                )
            )
            
            // create transit token account
            let transitTokenMint = try SolanaSDK.PublicKey(string: swap.transitTokenMintPubkey)
            let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
                user: userAuthorityAddress,
                transitTokenMint: transitTokenMint
            )
            
            instructions.append(
                try Program.createTransitTokenAccountInstruction(
                    feePayer: feePayerAddress,
                    userAuthority: userAuthorityAddress,
                    transitTokenAccount: transitTokenAccountAddress,
                    transitTokenMint: transitTokenMint
                )
            )
            
            // relay swap
            instructions.append(
                try Program.createRelaySwapInstruction(
                    transitiveSwap: swap,
                    userAuthorityAddressPubkey: userAuthorityAddress,
                    sourceAddressPubkey: userSourceTokenAccountAddress,
                    transitTokenAccount: transitTokenAccountAddress,
                    destinationAddressPubkey: try SolanaSDK.PublicKey(string: userDestinationTokenAccountAddress),
                    feePayerPubkey: feePayerAddress
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
            
        default:
            fatalError("unsupported swap type")
        }
        
        // IN CASE SWAPPING TO SOL
        if destinationTokenMintAddress == .wrappedSOLMint {
            if let ownerAddress = try? SolanaSDK.PublicKey(string: userDestinationAccountOwnerAddress) {
                instructions.append(
                    SolanaSDK.TokenProgram.closeAccountInstruction(
                        account: try SolanaSDK.PublicKey(string: userDestinationTokenAccountAddress),
                        destination: ownerAddress,
                        owner: ownerAddress
                    )
                )
                
                instructions.append(
                    SolanaSDK.SystemProgram.transferInstruction(
                        from: ownerAddress,
                        to: feePayerAddress,
                        lamports: minimumTokenAccountBalance
                    )
                )
                
                expectedFee.accountBalances -= minimumTokenAccountBalance
            }
        }
        
        // Relay fee
        instructions.append(
            try Program.transferSolInstruction(
                userAuthorityAddress: userAuthorityAddress,
                recipient: feePayerAddress,
                lamports: feeAmount
            )
        )
        
        var transaction = SolanaSDK.Transaction()
        transaction.instructions = instructions
        transaction.feePayer = feePayerAddress
        transaction.recentBlockhash = blockhash
        let transactionFee = try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignature)
        expectedFee.transaction = transactionFee
        
        return .init(
            swapData: swap.swapData,
            transaction: transaction,
            feeAmount: expectedFee,
            transferAuthorityAccount: swap.transferAuthorityAccount
        )
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
