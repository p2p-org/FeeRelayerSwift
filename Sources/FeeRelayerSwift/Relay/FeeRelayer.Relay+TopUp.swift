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
        amount: UInt64,
        topUpPools: OrcaSwap.PoolsPair,
        topUpFee: SolanaSDK.FeeAmount
    ) -> Single<[String]> {
        guard let owner = accountStorage.account else {return .error(FeeRelayer.Error.unauthorized)}
        
        // get recent blockhash
        return solanaClient.getRecentBlockhash(commitment: nil)
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
                            feeAmount: topUpFee.accountBalances,
                            signatures: signatures,
                            blockhash: recentBlockhash
                        )
                    ),
                    decodedTo: [String].self
                )
            }
            .observe(on: MainScheduler.instance)
    }
    
    // MARK: - Helpers
    func prepareForTopUp(
        amount: SolanaSDK.FeeAmount,
        payingFeeToken: TokenInfo,
        relayAccountStatus: RelayAccountStatus
    ) -> Single<TopUpPreparedParams> {
        // form request
        orcaSwapClient
            .getTradablePoolsPairs(
                fromMint: payingFeeToken.mint,
                toMint: SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString
            )
            .map { [weak self] tradableTopUpPoolsPair in
                guard let self = self else { throw FeeRelayer.Error.unknown }
                
                
                // TOP UP
                let topUpFeesAndPools: FeesAndPools?
                var topUpAmount: UInt64?
                if let relayAccountBalance = relayAccountStatus.balance,
                   relayAccountBalance >= amount.total {
                    topUpFeesAndPools = nil
                }
                // STEP 2.2: Else
                else {
                    // Get best poolpairs for topping up
                    topUpAmount = amount.total - (relayAccountStatus.balance ?? 0)
                    
                    guard let topUpPools = try self.orcaSwapClient.findBestPoolsPairForEstimatedAmount(topUpAmount!, from: tradableTopUpPoolsPair) else {
                        throw FeeRelayer.Error.swapPoolsNotFound
                    }
                    let topUpFee = try self.calculateTopUpFee(topUpPools: topUpPools, relayAccountStatus: relayAccountStatus)
                    topUpFeesAndPools = .init(fee: topUpFee, poolsPair: topUpPools)
                }
                
                return .init(
                    topUpFeesAndPools: topUpFeesAndPools,
                    topUpAmount: topUpAmount
                )
            }
    }
}
