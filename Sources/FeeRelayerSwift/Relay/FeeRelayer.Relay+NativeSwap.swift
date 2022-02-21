//
//  File.swift
//  
//
//  Created by Chung Tran on 21/02/2022.
//

import Foundation
import OrcaSwapSwift
import RxSwift
import SolanaSwift

extension FeeRelayer.Relay {
    /// Calculate needed top up amount for swap
    public func calculateNeededTopUpAmount(
        swapTransactions: [OrcaSwap.PreparedSwapTransaction]
    ) -> Single<SolanaSDK.FeeAmount> {
        guard let cache = cache else {
            return .error(FeeRelayer.Error.relayInfoMissing)
        }

        // transaction fee
        let transactionFee = UInt64(swapTransactions.count) * 2 * cache.lamportsPerSignature
        
        // account creation fee
        let accountCreationFee = swapTransactions.reduce(0, {$0+$1.accountCreationFee})
        
        let expectedFee = SolanaSDK.FeeAmount(transaction: transactionFee, accountBalances: accountCreationFee)
        return calculateNeededTopUpAmount(expectedFee: expectedFee)
    }
    
    public func topUpAndSwap(
        _ swapTransactions: [OrcaSwap.PreparedSwapTransaction],
        feePayer: SolanaSDK.PublicKey?,
        payingFeeToken: FeeRelayer.Relay.TokenInfo?
    ) -> Single<[String]> {
        Single.zip(
            getRelayAccountStatus(reuseCache: false),
            getFreeTransactionFeeLimit(useCache: false),
            calculateNeededTopUpAmount(swapTransactions: swapTransactions)
        )
            .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
            .flatMap { [weak self] relayAccountStatus, freeTransactionFeeLimit, expectedFee -> Single<FreeTransactionFeeLimit> in
                guard let self = self else {throw FeeRelayer.Error.unknown}
                return self.checkAndTopUp(
                    expectedFee: expectedFee,
                    payingFeeToken: payingFeeToken,
                    relayAccountStatus: relayAccountStatus,
                    freeTransactionFeeLimit: freeTransactionFeeLimit
                )
                    .map {[weak self] _ in
                        var freeTransactionFeeLimit = freeTransactionFeeLimit
                        freeTransactionFeeLimit.currentUsage += 1
                        freeTransactionFeeLimit.amountUsed += (self?.cache?.lamportsPerSignature ?? 0) * 2 // fee for topping up
                        return freeTransactionFeeLimit
                    }
            }
            .flatMap { [weak self] freeTransactionFeeLimit in
                guard let self = self else {throw FeeRelayer.Error.unknown}
                guard swapTransactions.count > 0 && swapTransactions.count <= 2 else {
                    throw OrcaSwapError.invalidNumberOfTransactions
                }
                var request = self.prepareAndSend(
                    swapTransactions[0],
                    feePayer: feePayer ?? self.owner.publicKey,
                    payingFeeToken: payingFeeToken,
                    freeTransactionFeeLimit: freeTransactionFeeLimit
                )
                
                if swapTransactions.count == 2 {
                    request = request
                        .flatMap {[weak self] _ in
                            guard let self = self else {throw OrcaSwapError.unknown}
                            return self.prepareAndSend(
                                swapTransactions[1],
                                feePayer: feePayer ?? self.owner.publicKey,
                                payingFeeToken: payingFeeToken,
                                freeTransactionFeeLimit: freeTransactionFeeLimit
                            )
                                .retry { errors in
                                    errors.enumerated().flatMap{ (index, error) -> Observable<Int64> in
                                        if let error = error as? SolanaSDK.Error {
                                            switch error {
                                            case .invalidResponse(let error) where error.data?.logs?.contains("Program log: Error: InvalidAccountData") == true:
                                                return .timer(.seconds(1), scheduler: MainScheduler.instance)
                                            case .transactionError(_, logs: let logs) where logs.contains("Program log: Error: InvalidAccountData"):
                                                return .timer(.seconds(1), scheduler: MainScheduler.instance)
                                            default:
                                                break
                                            }
                                        }
                                        
                                        return .error(error)
                                    }
                                }
                                .timeout(.seconds(60), scheduler: MainScheduler.instance)
                        }
                }
                return request
            }
    }
    
    // MARK: - Helpers
    private func prepareAndSend(
        _ swapTransaction: OrcaSwap.PreparedSwapTransaction,
        feePayer: OrcaSwap.PublicKey,
        payingFeeToken: FeeRelayer.Relay.TokenInfo?,
        freeTransactionFeeLimit: FreeTransactionFeeLimit
    ) -> Single<[String]> {
        solanaClient.prepareTransaction(
            instructions: swapTransaction.instructions,
            signers: swapTransaction.signers,
            feePayer: feePayer,
            accountsCreationFee: swapTransaction.accountCreationFee,
            recentBlockhash: nil,
            lamportsPerSignature: nil
        )
            .flatMap { [weak self] preparedTransaction in
                guard let self = self else {throw OrcaSwapError.unknown}
                return try self.relayTransaction(
                    preparedTransaction: preparedTransaction,
                    freeTransactionFeeLimit: freeTransactionFeeLimit
                )
            }
    }
}
