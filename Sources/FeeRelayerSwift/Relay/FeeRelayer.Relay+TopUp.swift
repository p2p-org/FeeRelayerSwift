//
//  FeeRelayer.Relay+TopUp.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 07/02/2022.
//

import Foundation
import RxSwift
import SolanaSwift
import OrcaSwapSwift

extension FeeRelayer.Relay {
    /// Submits a signed top up swap transaction to the backend for processing
    func topUp(
        needsCreateUserRelayAddress: Bool,
        sourceToken: TokenInfo,
        targetAmount: UInt64,
        topUpPools: OrcaSwap.PoolsPair,
        expectedFee: UInt64
    ) -> Single<[String]> {
        Single.zip(
            solanaClient.getRecentBlockhash(commitment: nil),
            getFreeTransactionFeeLimit(useCache: false)
        )
            .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
            .flatMap { [weak self] recentBlockhash, freeTransactionFeeLimit in
                guard let self = self else {throw FeeRelayer.Error.unknown}
                guard let cache = self.cache else { throw FeeRelayer.Error.relayInfoMissing }
                
                // STEP 3: prepare for topUp
                let topUpTransaction = try self.prepareForTopUp(
                    network: self.solanaClient.endpoint.network,
                    sourceToken: sourceToken,
                    userAuthorityAddress: self.owner.publicKey,
                    userRelayAddress: self.userRelayAddress,
                    topUpPools: topUpPools,
                    targetAmount: targetAmount,
                    expectedFee: expectedFee,
                    blockhash: recentBlockhash,
                    minimumRelayAccountBalance: cache.minimumRelayAccountBalance,
                    minimumTokenAccountBalance: cache.minimumTokenAccountBalance,
                    needsCreateUserRelayAccount: needsCreateUserRelayAddress,
                    feePayerAddress: cache.feePayerAddress,
                    lamportsPerSignature: cache.lamportsPerSignature,
                    freeTransactionFeeLimit: freeTransactionFeeLimit
                )
                
                // STEP 4: send transaction
                let signatures = topUpTransaction.preparedTransaction.transaction.signatures
                guard signatures.count >= 2 else {throw FeeRelayer.Error.invalidSignature}
                
                // the second signature is the owner's signature
                let ownerSignature = try signatures.getSignature(index: 1)
                
                // the third signature (optional) is the transferAuthority's signature
                let transferAuthoritySignature = try? signatures.getSignature(index: 2)
                
                let topUpSignatures = SwapTransactionSignatures(
                    userAuthoritySignature: ownerSignature,
                    transferAuthoritySignature: transferAuthoritySignature
                )
                
                return self.apiClient.sendTransaction(
                    .relayTopUpWithSwap(
                        .init(
                            userSourceTokenAccountPubkey: sourceToken.address,
                            sourceTokenMintPubkey: sourceToken.mint,
                            userAuthorityPubkey: self.owner.publicKey.base58EncodedString,
                            topUpSwap: .init(topUpTransaction.swapData),
                            feeAmount: expectedFee,
                            signatures: topUpSignatures,
                            blockhash: recentBlockhash
                        )
                    ),
                    decodedTo: [String].self
                )
                    .do(onSuccess: { [weak self] _ in
                        guard let self = self else {return}
                        Logger.log(message: "Top up \(targetAmount) into \(self.userRelayAddress) completed", event: .info)
                    }, onSubscribe: { [weak self] in
                        guard let self = self else {return}
                        Logger.log(message: "Top up \(targetAmount) into \(self.userRelayAddress) processing", event: .info)
                    })
            }
            .observe(on: MainScheduler.instance)
    }
    
    // MARK: - Helpers
    func prepareForTopUp(
        targetAmount: SolanaSDK.Lamports,
        payingFeeToken: TokenInfo,
        relayAccountStatus: RelayAccountStatus,
        freeTransactionFeeLimit: FreeTransactionFeeLimit?,
        checkIfBalanceHaveEnoughAmount: Bool = true
    ) -> Single<TopUpPreparedParams?> {
        // form request
        orcaSwapClient
            .getTradablePoolsPairs(
                fromMint: payingFeeToken.mint,
                toMint: SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString
            )
            .map { [weak self] tradableTopUpPoolsPair in
                guard let self = self else { throw FeeRelayer.Error.unknown }
                
                
                // TOP UP
                if checkIfBalanceHaveEnoughAmount,
                   let relayAccountBalance = relayAccountStatus.balance,
                   relayAccountBalance >= targetAmount
                {
                    return nil
                }
                // STEP 2.2: Else
                else {
                    // Get target amount for topping up
                    var targetAmount = targetAmount
                    if checkIfBalanceHaveEnoughAmount {
                        targetAmount -= (relayAccountStatus.balance ?? 0)
                    }
                    
                    // Get real amounts needed for topping up
                    let amounts = try self.calculateTopUpAmount(targetAmount: targetAmount, relayAccountStatus: relayAccountStatus, freeTransactionFeeLimit: freeTransactionFeeLimit)
                    let topUpAmount = amounts.topUpAmount
                    let expectedFee = amounts.expectedFee
                    
                    // Get pools for topping up
                    // Get pools
                    // TODO: - Temporary solution, prefer direct swap to transitive swap to omit error Non-zero account can only be close if balance zero
                    let topUpPools: OrcaSwap.PoolsPair
                    if let directSwapPools = tradableTopUpPoolsPair.first(where: {$0.count == 1}) {
                        topUpPools = directSwapPools
                    } else if let transitiveSwapPools = try self.orcaSwapClient.findBestPoolsPairForEstimatedAmount(topUpAmount, from: tradableTopUpPoolsPair)
                    {
                        topUpPools = transitiveSwapPools
                    } else {
                        throw FeeRelayer.Error.swapPoolsNotFound
                    }
                    
                    return .init(amount: topUpAmount, expectedFee: expectedFee, poolsPair: topUpPools)
                }
            }
    }
    
    /// Calculate needed fee for topup transaction by forming fake transaction
    func calculateTopUpFee(relayAccountStatus: RelayAccountStatus) throws -> SolanaSDK.FeeAmount {
        guard let cache = cache else {throw FeeRelayer.Error.relayInfoMissing}
        var topUpFee = SolanaSDK.FeeAmount.zero
        
        // transaction fee
        let numberOfSignatures: UInt64 = 2 // feePayer's signature, owner's Signature
//        numberOfSignatures += 1 // transferAuthority
        topUpFee.transaction = numberOfSignatures * cache.lamportsPerSignature
        
        // account creation fee
        if relayAccountStatus == .notYetCreated {
            topUpFee.accountBalances += cache.minimumRelayAccountBalance
        }
        
        // swap fee
        topUpFee.accountBalances += cache.minimumTokenAccountBalance
        
        return topUpFee
    }
    
    func calculateTopUpAmount(
        targetAmount: UInt64,
        relayAccountStatus: RelayAccountStatus,
        freeTransactionFeeLimit: FreeTransactionFeeLimit?
    ) throws -> (topUpAmount: UInt64, expectedFee: UInt64) {
        // get cache
        guard let cache = cache else {throw FeeRelayer.Error.relayInfoMissing}
        
        // current_fee
        var currentFee: UInt64 = 0
        if relayAccountStatus == .notYetCreated {
            currentFee += cache.minimumRelayAccountBalance
        }
        
        let transactionNetworkFee = 2 * cache.lamportsPerSignature // feePayer, owner
        if freeTransactionFeeLimit?.isFreeTransactionFeeAvailable(transactionFee: transactionNetworkFee) == false {
            currentFee += transactionNetworkFee
        }
        
        // swap_amount_out
//        let swapAmountOut = targetAmount + currentFee
        var swapAmountOut = targetAmount
        if relayAccountStatus == .notYetCreated {
            swapAmountOut += getRelayAccountCreationCost() // Temporary solution
        } else {
            swapAmountOut += currentFee
        }
        
        // expected_fee
        let expectedFee = currentFee + cache.minimumTokenAccountBalance
        
        return (topUpAmount: swapAmountOut, expectedFee: expectedFee)
    }
    
    /// Prepare transaction and expected fee for a given relay transaction
    private func prepareForTopUp(
        network: SolanaSDK.Network,
        sourceToken: TokenInfo,
        userAuthorityAddress: SolanaSDK.PublicKey,
        userRelayAddress: SolanaSDK.PublicKey,
        topUpPools: OrcaSwap.PoolsPair,
        targetAmount: UInt64,
        expectedFee: UInt64,
        blockhash: String,
        minimumRelayAccountBalance: UInt64,
        minimumTokenAccountBalance: UInt64,
        needsCreateUserRelayAccount: Bool,
        feePayerAddress: String,
        lamportsPerSignature: UInt64,
        freeTransactionFeeLimit: FreeTransactionFeeLimit?
    ) throws -> (swapData: FeeRelayerRelaySwapType, preparedTransaction: SolanaSDK.PreparedTransaction) {
        // assertion
        guard let userSourceTokenAccountAddress = try? SolanaSDK.PublicKey(string: sourceToken.address),
              let sourceTokenMintAddress = try? SolanaSDK.PublicKey(string: sourceToken.mint),
              let feePayerAddress = try? SolanaSDK.PublicKey(string: feePayerAddress),
              let associatedTokenAddress = try? SolanaSDK.PublicKey.associatedTokenAddress(walletAddress: feePayerAddress, tokenMintAddress: sourceTokenMintAddress),
              userSourceTokenAccountAddress != associatedTokenAddress
        else { throw FeeRelayer.Error.wrongAddress }
        
        // forming transaction and count fees
        var accountCreationFee: UInt64 = 0
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
            accountCreationFee += minimumRelayAccountBalance
        }
        
        // top up swap
        let transitTokenMintPubkey = try getTransitTokenMintPubkey(pools: topUpPools)
        let swap = try prepareSwapData(network: network, pools: topUpPools, inputAmount: nil, minAmountOut: targetAmount, slippage: 0.01, transitTokenMintPubkey: transitTokenMintPubkey)
        let userTransferAuthority = swap.transferAuthorityAccount?.publicKey
        
        switch swap.swapData {
        case let swap as DirectSwapData:
            accountCreationFee += minimumTokenAccountBalance
            // approve
            if let userTransferAuthority = userTransferAuthority {
                instructions.append(
                    SolanaSDK.TokenProgram.approveInstruction(
                        tokenProgramId: .tokenProgramId,
                        account: userSourceTokenAccountAddress,
                        delegate: userTransferAuthority,
                        owner: userAuthorityAddress,
                        amount: swap.amountIn
                    )
                )
            }
            
            // top up
            instructions.append(
                try Program.topUpSwapInstruction(
                    network: network,
                    topUpSwap: swap,
                    userAuthorityAddress: userAuthorityAddress,
                    userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                    feePayerAddress: feePayerAddress
                )
            )
        case let swap as TransitiveSwapData:
            // approve
            if let userTransferAuthority = userTransferAuthority {
                instructions.append(
                    SolanaSDK.TokenProgram.approveInstruction(
                        tokenProgramId: .tokenProgramId,
                        account: userSourceTokenAccountAddress,
                        delegate: userTransferAuthority,
                        owner: userAuthorityAddress,
                        amount: swap.from.amountIn
                    )
                )
            }
            
            // create transit token account
            let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
                user: userAuthorityAddress,
                transitTokenMint: try SolanaSDK.PublicKey(string: swap.transitTokenMintPubkey),
                network: network
            )
            instructions.append(
                try Program.createTransitTokenAccountInstruction(
                    feePayer: feePayerAddress,
                    userAuthority: userAuthorityAddress,
                    transitTokenAccount: transitTokenAccountAddress,
                    transitTokenMint: try SolanaSDK.PublicKey(string: swap.transitTokenMintPubkey),
                    network: network
                )
            )
            
            // Destination WSOL account funding
            accountCreationFee += minimumTokenAccountBalance
            
            // top up
            instructions.append(
                try Program.topUpSwapInstruction(
                    network: network,
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
        default:
            fatalError("unsupported swap type")
        }
        
        // transfer
        instructions.append(
            try Program.transferSolInstruction(
                userAuthorityAddress: userAuthorityAddress,
                recipient: feePayerAddress,
                lamports: expectedFee,
                network: network
            )
        )
        
        var transaction = SolanaSDK.Transaction()
        transaction.instructions = instructions
        transaction.feePayer = feePayerAddress
        transaction.recentBlockhash = blockhash
        
        // calculate fee first
        let expectedFee = SolanaSDK.FeeAmount(
            transaction: try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignature),
            accountBalances: accountCreationFee
        )
        
        // resign transaction
        var signers = [owner]
        if let tranferAuthority = swap.transferAuthorityAccount {
            signers.append(tranferAuthority)
        }
        try transaction.sign(signers: signers)
        
        if let decodedTransaction = transaction.jsonString {
            Logger.log(message: decodedTransaction, event: .info)
        }
        
        return (
            swapData: swap.swapData,
            preparedTransaction: .init(
                transaction: transaction,
                signers: signers,
                expectedFee: expectedFee
            )
        )
    }
}

private extension Array where Element == SolanaSDK.Transaction.Signature {
    func getSignature(index: Int) throws -> String {
        guard count > index else {throw FeeRelayer.Error.invalidSignature}
        guard let data = self[index].signature else {throw FeeRelayer.Error.invalidSignature}
        return Base58.encode(data)
    }
}
