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
    public func topUpAndSend(
        sourceToken: TokenInfo,
        destinationAddress: String,
        tokenMint: String,
        inputAmount: UInt64,
        payingFeeToken: FeeRelayer.Relay.TokenInfo
    ) -> Single<[String]> {
        Single.zip(
            getRelayAccountStatus(reuseCache: false),
            solanaClient.getTokenSupply(pubkey: tokenMint)
        ).flatMap { [weak self] relayAccountStatus, tokenInfo in
            guard let self = self else { throw FeeRelayer.Error.unknown }
            guard let owner = self.accountStorage.account else { return .error(FeeRelayer.Error.unauthorized) }
            guard let info = self.info else { return .error(FeeRelayer.Error.relayInfoMissing) }
            
            return try self.makeTransferTransaction(
                network: self.solanaClient.endpoint.network,
                owner: owner,
                sourceToken: sourceToken,
                recipientPubkey: destinationAddress,
                tokenMintAddress: tokenMint,
                feePayerAddress: info.feePayerAddress,
                lamportsPerSignatures: info.lamportsPerSignature,
                minimumTokenAccountBalance: info.minimumTokenAccountBalance,
                inputAmount: inputAmount,
                decimals: tokenInfo.decimals
            )
                .flatMap { transaction, amount, recipientTokenAccountAddress -> Single<(SolanaSDK.Transaction, SolanaSDK.FeeAmount, SolanaSDK.SPLTokenDestinationAddress, TopUpPreparedParams)> in
                    Single.zip(
                        .just(transaction),
                        .just(amount),
                        .just(recipientTokenAccountAddress),
                        self.prepareForTopUp(amount: amount, payingFeeToken: payingFeeToken, relayAccountStatus: relayAccountStatus)
                    )
                }
                .flatMap { transaction, amount, recipientTokenAccountAddress, params in
                    
                    let transfer: () throws -> Single<[String]> = { [weak self] in
                        guard let self = self else {return .error(FeeRelayer.Error.unknown)}
                        guard let account = self.accountStorage.account else { return .error(FeeRelayer.Error.unauthorized) }
                        
                        var transaction = transaction
                        try transaction.sign(signers: [account])
                        
                        guard let authoritySignature = transaction.findSignature(pubkey: account.publicKey)?.signature else { return .error(FeeRelayer.Error.invalidSignature) }
                        guard let blockhash = transaction.recentBlockhash else { return .error(FeeRelayer.Error.unknown) }

                        return self.apiClient.sendTransaction(
                            .relayTransferSPLTokena(
                                .init(
                                    senderTokenAccountPubkey: sourceToken.address,
                                    recipientPubkey: recipientTokenAccountAddress.isUnregisteredAsocciatedToken ? destinationAddress: recipientTokenAccountAddress.destination.base58EncodedString,
                                    tokenMintPubkey: tokenMint,
                                    authorityPubkey: account.publicKey.base58EncodedString,
                                    amount: inputAmount,
                                    feeAmount: amount.total,
                                    decimals: tokenInfo.decimals,
                                    authoritySignature: Base58.encode(authoritySignature.bytes),
                                    blockhash: blockhash
                                )
                            ),
                            decodedTo: [String].self
                        )
                    }
                    
                    // STEP 2: Check if relay account has already had enough balance to cover swapping fee
                    // STEP 2.1: If relay account has enough balance to cover swapping fee
                    if let topUpFeesAndPools = params.topUpFeesAndPools,
                       let topUpAmount = params.topUpAmount {
                        // STEP 2.2.1: Top up
                        return self.topUp(
                            needsCreateUserRelayAddress: relayAccountStatus == .notYetCreated,
                            sourceToken: payingFeeToken,
                            amount: topUpAmount,
                            topUpPools: topUpFeesAndPools.poolsPair,
                            topUpFee: topUpFeesAndPools.fee
                        )
                            // STEP 2.2.2: Swap
                            .flatMap { _ in try transfer() }
                    } else {
                        return try transfer()
                    }
                }
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
        ).flatMap { [weak self] transaction, feeAmount, recipientTokenAccountAddress -> Single<(SolanaSDK.Transaction, SolanaSDK.FeeAmount, SolanaSDK.SPLTokenDestinationAddress)> in
            guard let self = self else { return .error(FeeRelayer.Error.unknown) }
            guard let account = self.accountStorage.account else { return .error(FeeRelayer.Error.unauthorized) }
            var transaction = transaction
            try transaction.sign(signers: [account])
            return Single.just((transaction, feeAmount, recipientTokenAccountAddress))
        }
        .flatMap { [weak self] transaction, feeAmount, recipientTokenAccountAddress -> Single<[String]> in
            guard let self = self else { return .error(FeeRelayer.Error.unknown) }
            guard let account = self.accountStorage.account else { return .error(FeeRelayer.Error.unauthorized) }
            guard let authoritySignature = transaction.findSignature(pubkey: account.publicKey)?.signature else { return .error(FeeRelayer.Error.invalidSignature) }
            guard let blockhash = transaction.recentBlockhash else { return .error(FeeRelayer.Error.unknown) }
            
            return self.apiClient.sendTransaction(
                .relayTransferSPLTokena(
                    .init(
                        senderTokenAccountPubkey: sourceToken.address,
                        recipientPubkey: recipientTokenAccountAddress.isUnregisteredAsocciatedToken ? recipientPubkey: recipientTokenAccountAddress.destination.base58EncodedString,
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
    ) throws -> Single<(SolanaSDK.Transaction, SolanaSDK.FeeAmount, SolanaSDK.SPLTokenDestinationAddress)> {
        let makeTransactionWrapper: (UInt64, SolanaSDK.SPLTokenDestinationAddress?) throws -> Single<(SolanaSDK.Transaction, SolanaSDK.FeeAmount, SolanaSDK.SPLTokenDestinationAddress)> = { feeAmount, recipientTokenAccountAddress in
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
                decimals: decimals,
                recipientTokenAccountAddress: recipientTokenAccountAddress
            )
        }
        
        return try makeTransactionWrapper(0, nil)
            .flatMap { transaction, feeAmount, recipientTokenAccountAddress in try makeTransactionWrapper(feeAmount.total, recipientTokenAccountAddress) }
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
        decimals: SolanaSDK.Decimals,
        recipientTokenAccountAddress: SolanaSDK.SPLTokenDestinationAddress? = nil
    ) throws -> Single<(SolanaSDK.Transaction, SolanaSDK.FeeAmount, SolanaSDK.SPLTokenDestinationAddress)> {
        let recipientRequest: Single<SolanaSDK.SPLTokenDestinationAddress>
        
        if let recipientTokenAccountAddress = recipientTokenAccountAddress {
            recipientRequest = .just(recipientTokenAccountAddress)
        } else {
            recipientRequest = solanaClient.findSPLTokenDestinationAddress(
                mintAddress: tokenMintAddress,
                destinationAddress: recipientPubkey
            )
        }
        
        return Single.zip(
                // Get recent blockhash
                solanaClient.getRecentBlockhash(),
                // Should recipient token account be created?
                recipientRequest
            )
            .flatMap { blockhash, recipientTokenAccountAddress in
                // Calculate fee
                var expectedFee = SolanaSDK.FeeAmount(transaction: 0, accountBalances: 0)
                
                var instructions = [SolanaSDK.TransactionInstruction]()
                
                if recipientTokenAccountAddress.isUnregisteredAsocciatedToken {
                    instructions.append(
                        SolanaSDK.AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
                            mint: try SolanaSDK.PublicKey(string: tokenMintAddress),
                            associatedAccount: recipientTokenAccountAddress.destination,
                            owner: try SolanaSDK.PublicKey(string: recipientPubkey),
                            payer: try SolanaSDK.PublicKey(string: feePayerAddress)
                        )
                    )
                    expectedFee.accountBalances += minimumTokenAccountBalance
                }
                
                instructions.append(
                    SolanaSDK.TokenProgram.transferCheckedInstruction(
                        programId: .tokenProgramId,
                        source: try SolanaSDK.PublicKey(string: sourceToken.address),
                        mint: try SolanaSDK.PublicKey(string: tokenMintAddress),
                        destination: recipientTokenAccountAddress.destination,
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
                return .just((transaction, expectedFee, recipientTokenAccountAddress))
            }
    }
}
