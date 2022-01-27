//
//  File.swift
//  
//
//  Created by Chung Tran on 19/01/2022.
//

import Foundation
import SolanaSwift
import RxSwift
import OrcaSwapSwift

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
    
    /// Submits a signed transfer token transaction to the backend for processing
    func transfer(
        network: SolanaSDK.Network,
        owner: SolanaSDK.Account,
        sourceToken: TokenInfo,
        recipientPubkey: String,
        tokenMintAddress: String,
        feePayerAddress: String,
        minimumTokenAccountBalance: UInt64,
        inputAmount: UInt64,
        decimals: SolanaSDK.Decimals,
        slippage: Double,
        lamportsPerSignature: UInt64
    ) throws -> Single<[String]> {
        try makeTransferTransaction(
            network: network,
            owner: owner,
            sourceToken: sourceToken,
            recipientPubkey: recipientPubkey,
            tokenMintAddress: tokenMintAddress,
            feePayerAddress: feePayerAddress,
            lamportsPerSignatures: lamportsPerSignature,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            inputAmount: inputAmount,
            decimals: decimals
        ).flatMap { [weak self] transaction, feeAmount -> Single<(SolanaSDK.Transaction, SolanaSDK.FeeAmount)> in
            guard let self = self else { return .error(FeeRelayer.Error.unknown) }
            guard let account = self.accountStorage.account else { return .error(FeeRelayer.Error.unauthorized) }
            var transaction = transaction
            try transaction.sign(signers: [account])
            return Single.just((transaction, feeAmount))
        }
        .flatMap { [weak self] transaction, feeAmount -> Single<[String]> in
            guard let self = self else { return .error(FeeRelayer.Error.unknown) }
            guard let account = self.accountStorage.account else { return .error(FeeRelayer.Error.unauthorized) }
            guard let authoritySignature = transaction.findSignature(pubkey: account.publicKey)?.signature else { return .error(FeeRelayer.Error.invalidSignature) }
            guard let blockhash = transaction.recentBlockhash else { return .error(FeeRelayer.Error.unknown) }
            
            return self.apiClient.sendTransaction(
                .relayTransferSPLTokena(
                    .init(
                        senderTokenAccountPubkey: sourceToken.address,
                        recipientPubkey: recipientPubkey,
                        tokenMintPubkey: tokenMintAddress,
                        authorityPubkey: account.publicKey.base58EncodedString,
                        amount: inputAmount,
                        feeAmount: feeAmount.total,
                        decimals: decimals,
                        authoritySignature: Base58.encode(authoritySignature.bytes),
                        blockhash: blockhash
                    )
                ),
                decodedTo: [String].self
            )
        }
    }
    
    /// Generate transfer transaction
    func makeTransferTransaction(
        network: SolanaSDK.Network,
        owner: SolanaSDK.Account,
        sourceToken: TokenInfo,
        recipientPubkey: String,
        tokenMintAddress: String,
        feePayerAddress: String,
        lamportsPerSignatures: UInt64,
        minimumTokenAccountBalance: UInt64,
        inputAmount: UInt64,
        decimals: SolanaSDK.Decimals
    ) throws -> Single<(SolanaSDK.Transaction, SolanaSDK.FeeAmount)> {
        let makeTransactionWrapper: (UInt64) throws -> Single<(SolanaSDK.Transaction, SolanaSDK.FeeAmount)> = { feeAmount in
            try self._createTransferTransaction(
                network: network,
                owner: owner,
                sourceToken: sourceToken,
                recipientPubkey: recipientPubkey,
                tokenMintAddress: tokenMintAddress,
                feePayerAddress: feePayerAddress,
                feeAmount: feeAmount,
                lamportsPerSignatures: lamportsPerSignatures,
                minimumTokenAccountBalance: minimumTokenAccountBalance,
                inputAmount: inputAmount,
                decimals: decimals
            )
        }
        
        return try makeTransactionWrapper(0)
            .flatMap { transaction, feeAmount in try makeTransactionWrapper(feeAmount.total) }
    }
    
    private func _createTransferTransaction(
        network: SolanaSDK.Network,
        owner: SolanaSDK.Account,
        sourceToken: TokenInfo,
        recipientPubkey: String,
        tokenMintAddress: String,
        feePayerAddress: String,
        feeAmount: UInt64,
        lamportsPerSignatures: UInt64,
        minimumTokenAccountBalance: UInt64,
        inputAmount: UInt64,
        decimals: SolanaSDK.Decimals
    ) throws -> Single<(SolanaSDK.Transaction, SolanaSDK.FeeAmount)> {
        Single.zip(
                // Get recent blockhash
                solanaClient.getRecentBlockhash(),
                // Should recipient token account be created?
                solanaClient.getAccountInfo(account: recipientPubkey, decodedTo: SolanaSDK.EmptyInfo.self)
                    .flatMap { info -> Single<Bool> in
                        switch info.owner {
                        case SolanaSDK.PublicKey.programId.base58EncodedString:
                            return .just(true)
                        case SolanaSDK.PublicKey.tokenProgramId.base58EncodedString:
                            // TODO: validate_token_account(recipient_address.clone(), token_mint_address.to_string(), None)
                            return .just(false)
                        default:
                            return .just(true)
                        }
                    }
            )
            .flatMap { blockhash, needsCreateRecipientTokenAccount in
                // Calculate fee
                var expectedFee = SolanaSDK.FeeAmount(transaction: 0, accountBalances: 0)
                
                var instructions = [SolanaSDK.TransactionInstruction]()
                
                let recipientTokenAccountAddress = try { () -> String in
                    if needsCreateRecipientTokenAccount {
                        let associatedAccount = try SolanaSDK.PublicKey.associatedTokenAddress(
                            walletAddress: try SolanaSDK.PublicKey(string: recipientPubkey),
                            tokenMintAddress: try SolanaSDK.PublicKey(string: tokenMintAddress)
                        )
                        instructions.append(
                            SolanaSDK.AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
                                mint: try SolanaSDK.PublicKey(string: tokenMintAddress),
                                associatedAccount: associatedAccount,
                                owner: try SolanaSDK.PublicKey(string: recipientPubkey),
                                payer: try SolanaSDK.PublicKey(string: feePayerAddress)
                            )
                        )
                        expectedFee.accountBalances += minimumTokenAccountBalance
                        return associatedAccount.base58EncodedString
                    } else {
                        return recipientPubkey
                    }
                }()
                
                instructions.append(
                    SolanaSDK.TokenProgram.transferCheckedInstruction(
                        programId: .tokenProgramId,
                        source: try SolanaSDK.PublicKey(string: sourceToken.address),
                        mint: try SolanaSDK.PublicKey(string: tokenMintAddress),
                        destination: try SolanaSDK.PublicKey(string: recipientTokenAccountAddress),
                        owner: owner.publicKey,
                        multiSigners: [],
                        amount: inputAmount,
                        decimals: decimals
                    )
                )
                
                // Relay fee
                instructions.append(
                    try Program.transferSolInstruction(
                        userAuthorityAddress: owner.publicKey,
                        recipient: try SolanaSDK.PublicKey(string: feePayerAddress),
                        lamports: feeAmount,
                        network: network
                    )
                )
                
                var transaction = SolanaSDK.Transaction()
                transaction.instructions = instructions
                transaction.feePayer = try SolanaSDK.PublicKey(string: feePayerAddress)
                transaction.recentBlockhash = blockhash
                
                expectedFee.transaction += try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignatures)
                
                print(expectedFee.total)
                return .just((transaction, expectedFee))
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
