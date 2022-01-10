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
                solanaSDK.getMinimumBalanceForRentExemption(span: 0)
            )
                .map { [weak self] needsCreateUserRelayAccount, minimumRelayAccountBalance in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    
                    // STEP 1: calculate top up fees
                    let topUpSwap = try self.prepareSwapData(
                        topUpPools: topUpPools,
                        amount: amount,
                        transitTokenMintPubkey: transitTokenMintPubkey
                    )
                    let topUpFee = try self.calculateTopUpFee(
                        userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                        sourceTokenMintAddress: sourceTokenMintAddress,
                        userAuthorityAddress: userAuthorityAddress,
                        userRelayAddress: userRelayAddress,
                        topUpSwap: topUpSwap,
                        minimumRelayAccountBalance: minimumRelayAccountBalance,
                        minimumTokenAccountBalance: minimumTokenAccountBalance,
                        needsCreateUserRelayAccount: needsCreateUserRelayAccount,
                        feePayerAddress: feePayerAddress,
                        lamportsPerSignature: lamportsPerSignature
                    )
                    
                    // STEP 2: modify amount
                    guard let topUpFeeInput = topUpPools.getInputAmount(minimumAmountOut: topUpFee, slippage: defaultSlippage)
                    else {throw FeeRelayer.Error.invalidAmount}
                    amount += topUpFeeInput
                    
                    // STEP 3: prepare for topUp
                }
            
            
            do {
                // Request needed infos
                
                
                
                // requests
                let getRecentBlockhashRequest = solanaSDK.getRecentBlockhash(commitment: "recent")
            } catch {
                return .error(error)
            }
            
        }
    }
}

extension FeeRelayer.Relay: FeeRelayerRelayType {}
