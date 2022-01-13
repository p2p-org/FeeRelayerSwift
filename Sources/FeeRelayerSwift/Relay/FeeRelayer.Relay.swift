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
            sourceToken: TokenInfo, // WARNING: currently does not support native SOL
            destinationTokenMint: String,
            destinationAddress: String?,
            payingFeeToken: TokenInfo,
            pools: OrcaSwap.PoolsPair,
            inputAmount: UInt64,
            slippage: Double
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
                        fromMint: sourceToken.mint,
                        toMint: destinationTokenMint
                    ),
                // get relayAccount's status
                checkRelayAccountStatus(relayAccountAddress: userRelayAddress)
            )
                .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
                .flatMap { [weak self] minimumTokenAccountBalance, feePayerAddress, lamportsPerSignature, availableSwapPools, relayAccountStatus in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    
                    // get transit token mint
                    let transitTokenMintPubkey: SolanaSDK.PublicKey?
                    if pools.count == 2 {
                        let interTokenName = pools[0].tokenBName
                        transitTokenMintPubkey = try SolanaSDK.PublicKey(string: self.orcaSwapClient.getMint(tokenName: interTokenName))
                    } else {
                        transitTokenMintPubkey = nil
                    }
                    
                    // Redefine destination
                    let needsCreateDestinationTokenAccount: Bool
                    let userDestinationAddress: String
                    let userDestinationAccountOwnerAddress: SolanaSDK.PublicKey?
                    
                    if owner.publicKey.base58EncodedString == destinationAddress {
                        userDestinationAccountOwnerAddress = owner.publicKey
                        needsCreateDestinationTokenAccount = true
                        userDestinationAddress = owner.publicKey.base58EncodedString // placeholder, ignore it
                    } else {
                        userDestinationAccountOwnerAddress = nil
                        if let address = destinationAddress {
                            userDestinationAddress = address
                            needsCreateDestinationTokenAccount = false
                        } else {
                            userDestinationAddress = try SolanaSDK.PublicKey.associatedTokenAddress(
                                walletAddress: owner.publicKey,
                                tokenMintAddress: try SolanaSDK.PublicKey(string: destinationTokenMint)
                            ).base58EncodedString
                            needsCreateDestinationTokenAccount = true
                        }
                    }
                    let destinationToken = TokenInfo(address: userDestinationAddress, mint: destinationTokenMint)
                    
                    // STEP 1: Calculate swapping fee and forming transaction
                    let swappingFee = try self.calculateSwappingFee(
                        network: self.solanaClient.endpoint.network,
                        sourceToken: sourceToken,
                        destinationToken: destinationToken,
                        userAuthorityAddress: owner.publicKey,
                        userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress?.base58EncodedString,
                        pools: pools,
                        inputAmount: inputAmount,
                        slippage: slippage,
                        transitTokenMintPubkey: transitTokenMintPubkey,
                        minimumTokenAccountBalance: minimumTokenAccountBalance,
                        needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount,
                        feePayerAddress: feePayerAddress,
                        lamportsPerSignature: lamportsPerSignature
                    )
                    
                    // STEP 2: Check if relay account has already had enough balance to cover swapping fee
                    // STEP 2.1: If relay account has enough balance to cover swapping fee
                    if let relayAccountBalance = relayAccountStatus.balance,
                       relayAccountBalance >= swappingFee
                    {
                        // STEP 2.1.1: Swap
                        return self.swap(
                            network: self.solanaClient.endpoint.network,
                            owner: owner,
                            sourceToken: sourceToken,
                            destinationToken: destinationToken,
                            userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress?.base58EncodedString,
                            pools: pools,
                            inputAmount: inputAmount,
                            slippage: slippage,
                            transitTokenMintPubkey: transitTokenMintPubkey,
                            feeAmount: swappingFee,
                            minimumTokenAccountBalance: minimumTokenAccountBalance,
                            needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount,
                            feePayerAddress: feePayerAddress,
                            lamportsPerSignature: lamportsPerSignature
                        )
                    }
                    // STEP 2.2: Else
                    else {
                        // Get needed amount
                        let topUpAmount = swappingFee - (relayAccountStatus.balance ?? 0)
                        
                        // STEP 2.2.1: Top up
                        return self.topUp(
                            owner: owner,
                            userRelayAddress: userRelayAddress,
                            sourceToken: payingFeeToken,
                            amount: topUpAmount,
                            minimumTokenAccountBalance: minimumTokenAccountBalance,
                            feePayerAddress: feePayerAddress,
                            lamportsPerSignature: lamportsPerSignature
                        )
                        // STEP 2.2.2: Swap
                            .flatMap {_ in
                                self.swap(
                                    network: self.solanaClient.endpoint.network,
                                    owner: owner,
                                    sourceToken: sourceToken,
                                    destinationToken: destinationToken,
                                    userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress?.base58EncodedString,
                                    pools: pools,
                                    inputAmount: inputAmount,
                                    slippage: slippage,
                                    transitTokenMintPubkey: transitTokenMintPubkey,
                                    feeAmount: swappingFee,
                                    minimumTokenAccountBalance: minimumTokenAccountBalance,
                                    needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount,
                                    feePayerAddress: feePayerAddress,
                                    lamportsPerSignature: lamportsPerSignature
                                )
                            }
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
            sourceToken: TokenInfo,
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
                        fromMint: sourceToken.mint,
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
                        sourceToken: sourceToken,
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
                        sourceToken: sourceToken,
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
                    
                    // STEP 4: send transaction
                    let signatures = try self.getSignatures(
                        transaction: topUpTransaction.transaction,
                        owner: owner,
                        transferAuthorityAccount: topUpTransaction.transferAuthorityAccount
                    )
                    return self.apiClient.sendTransaction(
                        .relayTopUp(
                            .init(
                                userSourceTokenAccountPubkey: sourceToken.address,
                                sourceTokenMintPubkey: sourceToken.mint,
                                userAuthorityPubkey: owner.publicKey.base58EncodedString,
                                topUpSwap: topUpTransaction.swapData,
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
            transitTokenMintPubkey: SolanaSDK.PublicKey? = nil,
            
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
                        userAuthorityAddress: owner.publicKey,
                        userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress,
                        pools: pools,
                        inputAmount: inputAmount,
                        slippage: slippage,
                        transitTokenMintPubkey: transitTokenMintPubkey,
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
                        .relayTopUp(<#T##TopUpParams#>),
                        decodedTo: [String].self
                    )
                }
        }
        
        /// Send swap transaction to server
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
            
            let ownerSignature = Base58.encode(ownerSignatureData.bytes)
            let transferAuthoritySignature = Base58.encode(transferAuthoritySignatureData.bytes)
            
            return .init(userAuthoritySignature: ownerSignature, transferAuthoritySignature: transferAuthoritySignature)
        }
    }
}

extension FeeRelayer.Relay: FeeRelayerRelayType {}
