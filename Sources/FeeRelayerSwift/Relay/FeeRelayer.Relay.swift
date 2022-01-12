//
//  FeeRelayer+Relay.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 29/12/2021.
//

import Foundation
import RxSwift
import SolanaSwift

public protocol FeeRelayerRelayType {}

extension FeeRelayer {
    public class Relay {
        // MARK: - Properties
        private let apiClient: FeeRelayerAPIClientType
        private let solanaClient: FeeRelayerRelaySolanaClient
        private let accountStorage: SolanaSDKAccountStorage
        private let orcaSwapClient: OrcaSwapType
        
        // MARK: - Initializers
        public init(
            apiClient: FeeRelayerAPIClientType,
            solanaClient: FeeRelayerRelaySolanaClient,
            accountStorage: SolanaSDKAccountStorage,
            orcaSwapClient: OrcaSwapType
        ) {
            self.apiClient = apiClient
            self.solanaClient = solanaClient
            self.accountStorage = accountStorage
            self.orcaSwapClient = orcaSwapClient
        }
        
        // MARK: - Methods
        public func topUpAndSwap(
            userSourceTokenAccountAddress: String,
            sourceTokenMintAddress: String,
            destinationTokenAddress: String?,
            destinationTokenMintAddress: String,
            inputAmount: UInt64
        ) -> Single<[String]> {
            // get owner
            guard let owner = accountStorage.account else {
                return .error(FeeRelayer.Error.unauthorized)
            }
            
            // get relay account
            guard let userRelayAddress = try? Program.getUserRelayAddress(user: owner.publicKey) else {
                return .error(FeeRelayer.Error.wrongAddress)
            }
            
            // request needed infos
            return Single.zip(
                // get minimum token account balance
                solanaClient.getMinimumBalanceForRentExemption(span: 165),
                // get fee payer address
                apiClient.getFeePayerPubkey(),
                // get lamportsPerSignature
                solanaClient.getLamportsPerSignature(),
                // get topup pools
                orcaSwapClient
                    .getTradablePoolsPairs(
                        fromMint: sourceTokenMintAddress,
                        toMint: destinationTokenMintAddress
                    ),
                // get relayAccount's status
                checkRelayAccountStatus(relayAccountAddress: userRelayAddress)
            )
                .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
                .flatMap { [weak self] minimumTokenAccountBalance, feePayerAddress, lamportsPerSignature, availableSwapPools, relayAccountStatus in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    
                    // Get best poolpairs for swapping
                    guard let pools = try self.orcaSwapClient.findBestPoolsPairForInputAmount(inputAmount, from: availableSwapPools)
                    else { throw FeeRelayer.Error.swapPoolsNotFound }
                    
                    let transitTokenMintPubkey: SolanaSDK.PublicKey?
                    if pools.count == 2 {
                        let interTokenName = pools[0].tokenBName
                        transitTokenMintPubkey = try SolanaSDK.PublicKey(string: self.orcaSwapClient.getMint(tokenName: interTokenName))
                    } else {
                        transitTokenMintPubkey = nil
                    }
                    
                    // Define destination
                    let needsCreateDestinationTokenAccount: Bool
                    let userDestinationAddress: String
                    let userDestinationAccountOwnerAddress: SolanaSDK.PublicKey?
                    
                    if owner.publicKey.base58EncodedString == destinationTokenAddress {
                        userDestinationAccountOwnerAddress = owner.publicKey
                        needsCreateDestinationTokenAccount = true
                        userDestinationAddress = owner.publicKey.base58EncodedString
                    } else {
                        userDestinationAccountOwnerAddress = nil
                        if let address = destinationTokenAddress {
                            userDestinationAddress = address
                            needsCreateDestinationTokenAccount = false
                        } else {
                            userDestinationAddress = try SolanaSDK.PublicKey.associatedTokenAddress(
                                walletAddress: owner.publicKey,
                                tokenMintAddress: try SolanaSDK.PublicKey(string: destinationTokenMintAddress)
                            ).base58EncodedString
                            needsCreateDestinationTokenAccount = true
                        }
                    }
                    
                    // STEP 1: Calculate swapping fee
                    let swappingFee = try self.calculateSwappingFee(
                        network: self.solanaClient.endpoint.network,
                        userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                        userDestinationAddress: userDestinationAddress,
                        sourceTokenMintAddress: sourceTokenMintAddress,
                        destinationTokenMintAddress: destinationTokenMintAddress,
                        userAuthorityAddress: owner.publicKey,
                        userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress?.base58EncodedString,
                        pools: pools,
                        inputAmount: inputAmount,
                        transitTokenMintPubkey: transitTokenMintPubkey,
                        minimumTokenAccountBalance: minimumTokenAccountBalance,
                        needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount,
                        feePayerAddress: feePayerAddress,
                        lamportsPerSignature: lamportsPerSignature
                    )
                    
                    // STEP 2: Check if relay account has already had enough balance to cover swapping fee
                    // STEP 2.1: If relay account has enough balance to cover swapping fee
                    if let relayAccountBalance = relayAccountStatus.balance,
                        balance >= swappingFee {
                        // STEP 2.1.1: Swap
                        
                    }
                    // STEP 2.2: Else
                    else {
                        // STEP 2.2.1: Top up
                        
                        // STEP 2.2.2: Swap
                    }
                }
        }
        
        /// Check relay account status
        func checkRelayAccountStatus(
            relayAccountAddress: SolanaSDK.PublicKey
        ) -> Single<RelayAccountStatus> {
            
        }
        
        /// Submits a signed top up swap transaction to the backend for processing
        func topUp(
            owner: SolanaSDK.Account,
            userRelayAddress: SolanaSDK.PublicKey,
            userSourceTokenAccountAddress: String,
            sourceTokenMintAddress: String,
            amount: UInt64,
            minimumTokenAccountBalance: UInt64,
            feePayerAddress: String,
            lamportsPerSignature: UInt64
        ) -> Single<[String]> {
            // make amount mutable, because the final amount is equal to amount + topup fee
            var amount = amount
            
            // request needed infos
            return Single.zip(
                // check if creating user relay account is needed
                solanaClient.checkAccountValidation(account: userRelayAddress.base58EncodedString),
                // get minimum relay account balance
                solanaClient.getMinimumBalanceForRentExemption(span: 0),
                // get recent blockhash
                solanaClient.getRecentBlockhash(commitment: nil),
                // get topup pools
                orcaSwapClient
                    .getTradablePoolsPairs(
                        fromMint: sourceTokenMintAddress,
                        toMint: SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString
                    )
            )
                .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
                .flatMap { [weak self] needsCreateUserRelayAccount, minimumRelayAccountBalance, recentBlockhash, availableTopUpPools in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    
                    // Get best poolpairs for swapping
                    guard let topUpPools = try self.orcaSwapClient.findBestPoolsPairForEstimatedAmount(amount, from: availableTopUpPools) else {
                        throw FeeRelayer.Error.swapPoolsNotFound
                    }
                    
                    // Get transit token mint
                    var transitTokenMintPubkey: SolanaSDK.PublicKey?
                    if topUpPools.count == 2 {
                        let interTokenName = topUpPools[0].tokenBName
                        transitTokenMintPubkey = try SolanaSDK.PublicKey(string: self.orcaSwapClient.getMint(tokenName: interTokenName))
                    }
                    
                    // STEP 1: calculate top up fees
                    let topUpFee = try self.calculateTopUpFee(
                        network: self.solanaClient.endpoint.network,
                        userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                        sourceTokenMintAddress: sourceTokenMintAddress,
                        userAuthorityAddress: owner.publicKey,
                        userRelayAddress: userRelayAddress,
                        topUpPools: topUpPools,
                        amount: amount,
                        transitTokenMintPubkey: transitTokenMintPubkey,
                        minimumRelayAccountBalance: minimumRelayAccountBalance,
                        minimumTokenAccountBalance: minimumTokenAccountBalance,
                        needsCreateUserRelayAccount: needsCreateUserRelayAccount,
                        feePayerAddress: feePayerAddress,
                        lamportsPerSignature: lamportsPerSignature
                    )
                    
                    // STEP 2: add top up fee into total amount
                    amount += topUpFee
                    
                    // STEP 3: prepare for topUp
                    let topUpTransaction = try self.prepareForTopUp(
                        network: self.solanaClient.endpoint.network,
                        userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                        sourceTokenMintAddress: sourceTokenMintAddress,
                        userAuthorityAddress: owner.publicKey,
                        userRelayAddress: userRelayAddress,
                        topUpPools: topUpPools,
                        amount: amount,
                        transitTokenMintPubkey: transitTokenMintPubkey,
                        feeAmount: topUpFee,
                        blockhash: recentBlockhash,
                        minimumRelayAccountBalance: minimumRelayAccountBalance,
                        minimumTokenAccountBalance: minimumTokenAccountBalance,
                        needsCreateUserRelayAccount: needsCreateUserRelayAccount,
                        feePayerAddress: feePayerAddress,
                        lamportsPerSignature: lamportsPerSignature
                    )
                    
                    var transaction = topUpTransaction.transaction
                    
                    // STEP 4: send transaction
                    try transaction.sign(signers: [owner, topUpTransaction.transferAuthorityAccount])
                    guard let ownerSignatureData = transaction.findSignature(pubkey: owner.publicKey)?.signature,
                          let transferAuthoritySignatureData = transaction.findSignature(pubkey: topUpTransaction.transferAuthorityAccount.publicKey)?.signature
                    else {
                        throw FeeRelayer.Error.invalidSignature
                    }
                    
                    let ownerSignature = Base58.encode(ownerSignatureData.bytes)
                    let transferAuthoritySignature = Base58.encode(transferAuthoritySignatureData.bytes)
                    
                    return self.apiClient.sendTransaction(
                        .relayTopUp(
                            .init(
                                userSourceTokenAccountPubkey: userSourceTokenAccountAddress,
                                sourceTokenMintPubkey: sourceTokenMintAddress,
                                userAuthorityPubkey: owner.publicKey.base58EncodedString,
                                topUpSwap: topUpTransaction.swapData,
                                feeAmount: topUpFee,
                                signatures: .init(
                                    userAuthoritySignature: ownerSignature,
                                    transferAuthoritySignature: transferAuthoritySignature
                                ),
                                blockhash: recentBlockhash
                            )
                        ),
                        decodedTo: [String].self
                    )
                }
                .observe(on: MainScheduler.instance)
        }
    }
}

extension FeeRelayer.Relay: FeeRelayerRelayType {}
