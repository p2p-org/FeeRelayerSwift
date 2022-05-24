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
        swapTransactions: [PreparedSwapTransaction],
        payingTokenMint: String?
    ) async throws -> FeeAmount {
        guard let lamportsPerSignature = cache.lamportsPerSignature else {
            throw FeeRelayer.Error.relayInfoMissing
        }

        // transaction fee
        let transactionFee = UInt64(swapTransactions.count) * 2 * lamportsPerSignature
        
        // account creation fee
        let accountCreationFee = swapTransactions.reduce(0, {$0+$1.accountCreationFee})
        
        let expectedFee = FeeAmount(transaction: transactionFee, accountBalances: accountCreationFee)
        return try await calculateNeededTopUpAmount(expectedFee: expectedFee, payingTokenMint: payingTokenMint)
    }
    
    public func topUpAndSwap(
        _ swapTransactions: [PreparedSwapTransaction],
        feePayer: PublicKey?,
        payingFeeToken: FeeRelayer.Relay.TokenInfo?
    ) async throws -> [String] {
        try await updateRelayAccountStatus()
        try await updateFreeTransactionFeeLimit()
        let expectedFee = try await calculateNeededTopUpAmount(
            swapTransactions: swapTransactions,
            payingTokenMint: payingFeeToken?.mint
        )
        let checkAndTopUp = try await checkAndTopUp(
            expectedFee: expectedFee,
            payingFeeToken: payingFeeToken
        )
        guard swapTransactions.count > 0 && swapTransactions.count <= 2 else {
            throw OrcaSwapError.invalidNumberOfTransactions
        }
        return []
//        var request = self.prepareAndSend(
//            swapTransactions[0],
//            feePayer: feePayer ?? self.owner.publicKey,
//            payingFeeToken: payingFeeToken
//        )
//
//        if swapTransactions.count == 2 {
//            request = request
//                .flatMap {[weak self] _ in
//                    guard let self = self else {throw OrcaSwapError.unknown}
//                    return self.prepareAndSend(
//                        swapTransactions[1],
//                        feePayer: feePayer ?? self.owner.publicKey,
//                        payingFeeToken: payingFeeToken
//                    )
//                        .retry { errors in
//                            errors.enumerated().flatMap{ (index, error) -> Observable<Int64> in
//                                if let error = error as? SolanaError {
//                                    switch error {
//                                    case .invalidResponse(let error) where error.data?.logs?.contains("Program log: Error: InvalidAccountData") == true:
//                                        return .timer(.seconds(1), scheduler: MainScheduler.instance)
//                                    case .transactionError(_, logs: let logs) where logs.contains("Program log: Error: InvalidAccountData"):
//                                        return .timer(.seconds(1), scheduler: MainScheduler.instance)
//                                    default:
//                                        break
//                                    }
//                                }
//
//                                return .error(error)
//                            }
//                        }
//                        .timeout(.seconds(60), scheduler: MainScheduler.instance)
//                }
//        }
//        return request
    }
    
    // MARK: - Helpers
    private func prepareAndSend(
        _ swapTransaction: PreparedSwapTransaction,
        feePayer: PublicKey,
        payingFeeToken: FeeRelayer.Relay.TokenInfo?
    ) throws -> [String] {
        let preparedTransaction = solanaClient.prepareTransaction(
            instructions: swapTransaction.instructions,
            signers: swapTransaction.signers,
            feePayer: feePayer,
            accountsCreationFee: swapTransaction.accountCreationFee,
            recentBlockhash: nil,
            lamportsPerSignature: nil
        )
        return try self.relayTransaction(
            preparedTransaction: preparedTransaction,
            payingFeeToken: payingFeeToken,
            relayAccountStatus: self.cache.relayAccountStatus ?? .notYetCreated,
            additionalPaybackFee: 0
        )
    }
}
