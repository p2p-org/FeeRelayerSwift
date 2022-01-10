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
        private let solanaSDK: SolanaSDK
        
        // MARK: - Initializers
        public init(solanaSDK: SolanaSDK) {
            self.solanaSDK = solanaSDK
        }
        
        // MARK: - Methods
        func topUp(
            userSourceTokenAccountAddress: String,
            sourceTokenMintAddress: String,
            userAuthorityAddress: SolanaSDK.PublicKey,
            topUpPools: OrcaSwap.PoolsPair,
            amount: UInt64,
            transitTokenMintPubkey: SolanaSDK.PublicKey? = nil,
            minimumTokenAccountBalance: UInt64,
            feePayerAddress: String,
            lamportsPerSignature: UInt64
        ) -> Single<[String]> {
            // get relay account
            guard let userRelayAddress = try? Program.getUserRelayAddress(user: userAuthorityAddress) else {
                return .error(FeeRelayer.Error.wrongAddress)
            }
            
            let defaultSlippage: Double = 1
            
            // make amount mutable, because the final amount is equal to amount + topup fee
            var amount = amount
            
            // request needed infos
            return Single.zip(
                // check if creating user relay account is needed
                solanaSDK.checkAccountValidation(account: userRelayAddress.base58EncodedString),
                // get minimum relay account balance
                solanaSDK.getMinimumBalanceForRentExemption(span: 0),
                // get recent blockhash
                solanaSDK.getRecentBlockhash()
            )
                .map { [weak self] needsCreateUserRelayAccount, minimumRelayAccountBalance, recentBlockhash in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    
                    // STEP 1: calculate top up fees
                    let topUpFee = try self.calculateTopUpFee(
                        userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                        sourceTokenMintAddress: sourceTokenMintAddress,
                        userAuthorityAddress: userAuthorityAddress,
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
                        userAuthorityAddress: userAuthorityAddress,
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
                    
                }
        }
    }
}

extension FeeRelayer.Relay: FeeRelayerRelayType {}
