// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

class SwapFeeRelayerImpl: SwapFeeRelayer {
    let feeRelayer: FeeRelayer

    init(feeRelayer: FeeRelayer) { self.feeRelayer = feeRelayer }

    func calculateSwappingNetworkFees(
        swapPools _: PoolsPair?,
        sourceTokenMint _: String,
        destinationTokenMint _: String,
        destinationAddress _: String?
    ) async throws -> FeeAmount {}

    func prepareSwapTransaction(
        sourceToken _: Token,
        destinationTokenMint _: String,
        destinationAddress _: String?,
        fee _: Token,
        swapPools _: OrcaSwapSwift.PoolsPair,
        inputAmount _: UInt64,
        slippage _: Double
    ) async throws
    -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
        fatalError(
            "prepareSwapTransaction(sourceToken:destinationTokenMint:destinationAddress:fee:swapPools:inputAmount:slippage:) has not been implemented"
        )
    }

    private func getDestination(
        destinationAddress: PublicKey?,
        destination: PublicKey
    ) async throws
        -> (destinationToken: Token, userDestinationAccountOwnerAddress: PublicKey?,
            needsCreateDestinationTokenAccount: Bool)
    {
        let account = try feeRelayer.account

        if PublicKey.wrappedSOLMint == destinationTokenMint {
            // Target is SOL Token
            return (
                destinationToken: Token(address: account.publicKey, mint: destinationTokenMint),
                userDestinationAccountOwnerAddress: account.publicKey,
                needsCreateDestinationTokenAccount: true
            )
        } else {
            // Target is SPL Token
            if let destinationAddress = try? PublicKey(string: destinationAddress) {
                // User already has SPL account
                return (
                    destinationToken: Token(address: destinationAddress, mint: destinationTokenMint),
                    userDestinationAccountOwnerAddress: account.publicKey,
                    needsCreateDestinationTokenAccount: false
                )
            } else {
                // User doesn't have SPL account
                return (
                    destinationToken: Token(address: account.publicKey, mint: destinationTokenMint),
                    userDestinationAccountOwnerAddress: account.publicKey,
                    needsCreateDestinationTokenAccount: true
                )
            }
        }
    }
    
    private func getAssociatedTokenAddress(for address: PublicKey, with mintAddress: PublicKey) {
//        let accountInfo = feeRelayer.apiClient.getAccountInfo(account: <#T##String#>)
    }
}

//public func topUpAndSwap(
//    _ swapTransactions: [PreparedSwapTransaction],
//    feePayer: PublicKey?,
//    payingFeeToken: TokenInfo?
//) async throws -> [String] {
//    try await updateRelayAccountStatus()
//    try await updateFreeTransactionFeeLimit()
//    let expectedFee = try await calculateNeededTopUpAmount(
//        swapTransactions: swapTransactions,
//        payingTokenMint: payingFeeToken?.mint
//    )
//    let checkAndTopUp = try await checkAndTopUp(
//        expectedFee: expectedFee,
//        payingFeeToken: payingFeeToken
//    )
//    guard swapTransactions.count > 0 && swapTransactions.count <= 2 else {
//        throw OrcaSwapError.invalidNumberOfTransactions
//    }
//    return []
////        var request = self.prepareAndSend(
////            swapTransactions[0],
////            feePayer: feePayer ?? self.owner.publicKey,
////            payingFeeToken: payingFeeToken
////        )
////
////        if swapTransactions.count == 2 {
////            request = request
////                .flatMap {[weak self] _ in
////                    guard let self = self else {throw OrcaSwapError.unknown}
////                    return self.prepareAndSend(
////                        swapTransactions[1],
////                        feePayer: feePayer ?? self.owner.publicKey,
////                        payingFeeToken: payingFeeToken
////                    )
////                        .retry { errors in
////                            errors.enumerated().flatMap{ (index, error) -> Observable<Int64> in
////                                if let error = error as? SolanaError {
////                                    switch error {
////                                    case .invalidResponse(let error) where error.data?.logs?.contains("Program log: Error: InvalidAccountData") == true:
////                                        return .timer(.seconds(1), scheduler: MainScheduler.instance)
////                                    case .transactionError(_, logs: let logs) where logs.contains("Program log: Error: InvalidAccountData"):
////                                        return .timer(.seconds(1), scheduler: MainScheduler.instance)
////                                    default:
////                                        break
////                                    }
////                                }
////
////                                return .error(error)
////                            }
////                        }
////                        .timeout(.seconds(60), scheduler: MainScheduler.instance)
////                }
////        }
////        return request
//}
