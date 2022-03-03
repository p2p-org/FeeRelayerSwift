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
        swapTransactions: [OrcaSwap.PreparedSwapTransaction],
        payingTokenMint: String?
    ) -> Single<SolanaSDK.FeeAmount> {
        guard let lamportsPerSignature = cache.lamportsPerSignature else {
            return .error(FeeRelayer.Error.relayInfoMissing)
        }

        // transaction fee
        let transactionFee = UInt64(swapTransactions.count) * 2 * lamportsPerSignature
        
        // account creation fee
        let accountCreationFee = swapTransactions.reduce(0, {$0+$1.accountCreationFee})
        
        let expectedFee = SolanaSDK.FeeAmount(transaction: transactionFee, accountBalances: accountCreationFee)
        return calculateNeededTopUpAmount(expectedFee: expectedFee, payingTokenMint: payingTokenMint)
    }
    
    public func topUpAndSwap(
        _ swapTransactions: [OrcaSwap.PreparedSwapTransaction],
        feePayer: SolanaSDK.PublicKey?,
        payingFeeToken: FeeRelayer.Relay.TokenInfo?
    ) -> Single<[String]> {
        Single.zip(
            updateRelayAccountStatus().andThen(.just(())),
            updateFreeTransactionFeeLimit().andThen(.just(())),
            calculateNeededTopUpAmount(swapTransactions: swapTransactions, payingTokenMint: payingFeeToken?.mint)
        )
            .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
            .flatMap { [weak self] _, _, expectedFee -> Single<[String]?> in
                guard let self = self else {throw FeeRelayer.Error.unknown}
                return self.checkAndTopUp(
                    expectedFee: expectedFee,
                    payingFeeToken: payingFeeToken
                )
            }
            .flatMap { [weak self] _ in
                guard let self = self else {throw FeeRelayer.Error.unknown}
                guard swapTransactions.count > 0 && swapTransactions.count <= 2 else {
                    throw OrcaSwapError.invalidNumberOfTransactions
                }
                var request = self.prepareAndSend(
                    swapTransactions[0],
                    feePayer: feePayer ?? self.owner.publicKey,
                    payingFeeToken: payingFeeToken
                )
                
                if swapTransactions.count == 2 {
                    request = request
                        .flatMap {[weak self] _ in
                            guard let self = self else {throw OrcaSwapError.unknown}
                            return self.prepareAndSend(
                                swapTransactions[1],
                                feePayer: feePayer ?? self.owner.publicKey,
                                payingFeeToken: payingFeeToken
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
        payingFeeToken: FeeRelayer.Relay.TokenInfo?
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
                    payingFeeToken: payingFeeToken
                )
            }
    }
}
