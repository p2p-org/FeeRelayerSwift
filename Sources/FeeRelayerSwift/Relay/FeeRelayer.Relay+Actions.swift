//
//  File.swift
//  
//
//  Created by Chung Tran on 19/01/2022.
//

import Foundation
import SolanaSwift
import RxSwift

extension FeeRelayer.Relay {
    /// Submits a signed top up swap transaction to the backend for processing
    func topUp(
        owner: SolanaSDK.Account,
        needsCreateUserRelayAddress: Bool,
        sourceToken: TokenInfo,
        amount: UInt64,
        topUpPools: OrcaSwap.PoolsPair,
        topUpFee: UInt64
    ) -> Single<[String]> {
        // get recent blockhash
        solanaClient.getRecentBlockhash(commitment: nil)
            .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
            .flatMap { [weak self] recentBlockhash in
                guard let self = self else {throw FeeRelayer.Error.unknown}
                guard let info = self.info else { throw FeeRelayer.Error.relayInfoMissing }
                
                // STEP 3: prepare for topUp
                let topUpTransaction = try self.prepareForTopUp(
                    network: self.solanaClient.endpoint.network,
                    sourceToken: sourceToken,
                    userAuthorityAddress: owner.publicKey,
                    userRelayAddress: self.userRelayAddress,
                    topUpPools: topUpPools,
                    amount: amount,
                    feeAmount: topUpFee,
                    blockhash: recentBlockhash,
                    minimumRelayAccountBalance: info.minimumRelayAccountBalance,
                    minimumTokenAccountBalance: info.minimumTokenAccountBalance,
                    needsCreateUserRelayAccount: needsCreateUserRelayAddress,
                    feePayerAddress: info.feePayerAddress,
                    lamportsPerSignature: info.lamportsPerSignature
                )
                
                // STEP 4: send transaction
                let signatures = try self.getSignatures(
                    transaction: topUpTransaction.transaction,
                    owner: owner,
                    transferAuthorityAccount: topUpTransaction.transferAuthorityAccount
                )
                return self.apiClient.sendTransaction(
                    .relayTopUpWithSwap(
                        .init(
                            userSourceTokenAccountPubkey: sourceToken.address,
                            sourceTokenMintPubkey: sourceToken.mint,
                            userAuthorityPubkey: owner.publicKey.base58EncodedString,
                            topUpSwap: .init(topUpTransaction.swapData),
                            feeAmount: topUpFee,
                            signatures: signatures,
                            blockhash: recentBlockhash
                        )
                    ),
                    decodedTo: [String].self
                )
            }
            .observe(on: MainScheduler.instance)
    }
    
    /// Submits a signed token swap transaction to the backend for processing
    func swap(
        network: SolanaSDK.Network,
        owner: SolanaSDK.Account,
        sourceToken: TokenInfo,
        destinationToken: TokenInfo,
        userDestinationAccountOwnerAddress: String?,
        
        pools: OrcaSwap.PoolsPair,
        inputAmount: UInt64,
        slippage: Double,
        
        feeAmount: UInt64,
        minimumTokenAccountBalance: UInt64,
        needsCreateDestinationTokenAccount: Bool,
        feePayerAddress: String,
        lamportsPerSignature: UInt64
    ) -> Single<[String]> {
        solanaClient.getRecentBlockhash(commitment: nil)
            .flatMap { [weak self] blockhash in
                guard let self = self else {throw FeeRelayer.Error.unknown}
                let swapTransaction = try self.prepareForSwapping(
                    network: self.solanaClient.endpoint.network,
                    sourceToken: sourceToken,
                    destinationToken: destinationToken,
                    userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress,
                    pools: pools,
                    inputAmount: inputAmount,
                    slippage: slippage,
                    feeAmount: feeAmount,
                    blockhash: blockhash,
                    minimumTokenAccountBalance: minimumTokenAccountBalance,
                    needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount,
                    feePayerAddress: feePayerAddress,
                    lamportsPerSignature: lamportsPerSignature
                )
                
                let signatures = try self.getSignatures(
                    transaction: swapTransaction.transaction,
                    owner: owner,
                    transferAuthorityAccount: swapTransaction.transferAuthorityAccount
                )
                
                return self.apiClient.sendTransaction(
                    .relaySwap(.init(
                        userSourceTokenAccountPubkey: sourceToken.address,
                        userDestinationPubkey: destinationToken.address,
                        userDestinationAccountOwner: userDestinationAccountOwnerAddress,
                        sourceTokenMintPubkey: sourceToken.mint,
                        destinationTokenMintPubkey: destinationToken.mint,
                        userAuthorityPubkey: owner.publicKey.base58EncodedString,
                        userSwap: .init(swapTransaction.swapData),
                        feeAmount: feeAmount,
                        signatures: signatures,
                        blockhash: blockhash
                    )),
                    decodedTo: [String].self
                )
            }
    }
    
    /// Get signature from transaction
    private func getSignatures(
        transaction: SolanaSDK.Transaction,
        owner: SolanaSDK.Account,
        transferAuthorityAccount: SolanaSDK.Account
    ) throws -> SwapTransactionSignatures {
        var transaction = transaction
        
        try transaction.sign(signers: [owner, transferAuthorityAccount])
        guard let ownerSignatureData = transaction.findSignature(pubkey: owner.publicKey)?.signature,
              let transferAuthoritySignatureData = transaction.findSignature(pubkey: transferAuthorityAccount.publicKey)?.signature
        else {
            throw FeeRelayer.Error.invalidSignature
        }
        
        if let decodedTransaction = transaction.jsonString {
            Logger.log(message: decodedTransaction, event: .info)
        }
        
        let ownerSignature = Base58.encode(ownerSignatureData.bytes)
        let transferAuthoritySignature = Base58.encode(transferAuthoritySignatureData.bytes)
        
        return .init(userAuthoritySignature: ownerSignature, transferAuthoritySignature: transferAuthoritySignature)
    }
}
