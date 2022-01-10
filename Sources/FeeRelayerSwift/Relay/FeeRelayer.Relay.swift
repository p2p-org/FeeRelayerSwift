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
            transitTokenMintPubkey: SolanaSDK.PublicKey? = nil
        ) -> Single<[String]> {
            do {
                // preconditions
                guard topUpPools.count > 0 && topUpPools.count <= 2 else { throw FeeRelayer.Error.swapPoolsNotFound }
                let defaultSlippage = 0.01
                
                // create transferAuthority
                let transferAuthority = try SolanaSDK.Account(network: .mainnetBeta)
                
                // form topUp params
                if topUpPools.count == 1 {
                    let pool = topUpPools[0]
                    
                    guard let amountIn = try pool.getInputAmount(minimumReceiveAmount: amount, slippage: defaultSlippage) else {
                        throw FeeRelayer.Error.invalidAmount
                    }
                    
                    let directSwapData = pool.getSwapData(
                        transferAuthorityPubkey: transferAuthority.publicKey,
                        amountIn: amountIn,
                        minAmountOut: amount
                    )
                } else {
                    let firstPool = topUpPools[0]
                    let secondPool = topUpPools[1]
                    
                    guard let transitTokenMintPubkey = transitTokenMintPubkey,
                          let secondPoolAmountIn = try secondPool.getInputAmount(minimumReceiveAmount: amount, slippage: defaultSlippage),
                          let firstPoolAmountIn = try firstPool.getInputAmount(minimumReceiveAmount: secondPoolAmountIn, slippage: defaultSlippage)
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
                }
                
                // requests
                let getRecentBlockhashRequest = solanaSDK.getRecentBlockhash(commitment: "recent")
            } catch {
                return .error(error)
            }
            
        }
    }
}

extension FeeRelayer.Relay: FeeRelayerRelayType {}

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
