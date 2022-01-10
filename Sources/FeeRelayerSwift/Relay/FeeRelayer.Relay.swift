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
        /// Submits a signed top up swap transaction to the backend for processing
        func topUp(
            userSourceTokenAccountAddress: String,
            sourceTokenMintAddress: String,
            amount: UInt64,
            minimumTokenAccountBalance: UInt64,
            feePayerAddress: String,
            lamportsPerSignature: UInt64
        ) -> Single<[String]> {
            // get user account
            guard let owner = accountStorage.account else {
                return .error(FeeRelayer.Error.unauthorized)
            }
            
            // get relay account
            guard let userRelayAddress = try? Program.getUserRelayAddress(user: owner.publicKey) else {
                return .error(FeeRelayer.Error.wrongAddress)
            }
            
            let defaultSlippage: Double = 1
            
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
                    guard let topUpFeeInput = topUpPools.getInputAmount(minimumAmountOut: topUpFee, slippage: defaultSlippage)
                    else {throw FeeRelayer.Error.invalidAmount}
                    
                    amount += topUpFeeInput
                    
                    // STEP 3: prepare for topUp
                    let topUpTransaction = try self.prepareForTopUp(
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
        
        /// Submits a signed token swap transaction to the backend for processing
        func swap(
            
        ) -> Single<[String]> {
            
        }
    }
}

extension FeeRelayer.Relay: FeeRelayerRelayType {}
