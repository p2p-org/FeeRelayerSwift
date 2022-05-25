// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

class SwapFeeRelayerImpl: SwapFeeRelayer {
    let feeRelayer: FeeRelayer
    private(set) var solanaApiClient: SolanaAPIClient

    init(feeRelayer: FeeRelayer, solanaApiClient: SolanaAPIClient) {
        self.feeRelayer = feeRelayer
        self.solanaApiClient = solanaApiClient
    }

    func calculateSwappingNetworkFees(
        swapPools _: PoolsPair?,
        sourceTokenMint _: String,
        destinationTokenMint _: String,
        destinationAddress _: String?
    ) async throws -> FeeAmount {
        fatalError(
            "prepareSwapTransaction(sourceToken:destinationTokenMint:destinationAddress:fee:swapPools:inputAmount:slippage:) has not been implemented"
        )
    }

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

    private func analyseDestination(
        _ destination: PublicKey?,
        mint: PublicKey
    ) async throws -> (destination: Token, destinationOwner: PublicKey?, needCreateDestination: Bool) {
        let account = try feeRelayer.account

        if PublicKey.wrappedSOLMint == mint {
            // Target is SOL Token
            return (
                destination: Token(address: account.publicKey, mint: mint),
                destinationOwner: account.publicKey,
                needCreateDestination: true
            )
        } else {
            // Target is SPL Token
            if let destination = destination {
                // User already has SPL account
                return (
                    destination: Token(address: destination, mint: mint),
                    destinationOwner: account.publicKey,
                    needCreateDestination: false
                )
            } else {
                // User doesn't have SPL account

                // Try to get associated account
                let address = try await solanaApiClient.getAssociatedSPLTokenAddress(for: account.publicKey, mint: mint)

                // Check destination address is exist.
                var info: BufferInfo<AccountInfo>? = try await solanaApiClient
                    .getAccountInfo(account: address.base58EncodedString)
                let needsCreateDestinationTokenAccount = info?.owner == PublicKey.tokenProgramId.base58EncodedString

                return (
                    destination: Token(address: account.publicKey, mint: mint),
                    destinationOwner: nil,
                    needCreateDestination: needsCreateDestinationTokenAccount
                )
            }
        }
    }
}

// public func topUpAndSwap(
//    _ swapTransactions: [PreparedSwapTransaction],
//    feePayer: PublicKey?,
//    payingFeeToken: TokenInfo?
// ) async throws -> [String] {
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
// }
