// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

protocol FeeRelayerCalculator {
    /// Calculate a top up amount for user's relayer account.
    ///
    /// The user's relayer account will be used as fee payer address.
    /// - Parameters:
    ///   - expectedFee: an amount of fee, that blockchain need to process if user's send directly.
    ///   - payingTokenMint: a mint address of spl token, that user will use to play fee.
    /// - Returns: Fee amount in SOL
    /// - Throws:
    func calculateNeededTopUpAmount(expectedFee: FeeAmount, payingTokenMint: String?) async throws -> FeeAmount

    /// TODO: is return value optional?
    /// TODO: Add this function to OrcaSwap. We use this function at many places.
    /// Convert fee amount into spl value.
    ///
    /// - Parameters:
    ///   - feeInSOL: a fee amount in SOL
    ///   - payingFeeTokenMint: a mint address of spl token, that user will use to play fee.
    /// - Returns:
    /// - Throws:
    func calculateFeeInPayingToken(feeInSOL: FeeAmount, payingFeeTokenMint: String) async throws -> FeeAmount?
    
    
}


///// Calculate needed top up amount for swap
//public func calculateNeededTopUpAmount(
//    swapTransactions: [PreparedSwapTransaction],
//    payingTokenMint: String?
//) async throws -> FeeAmount {
//    guard let lamportsPerSignature = cache.lamportsPerSignature else {
//        throw FeeRelayerError.relayInfoMissing
//    }
//
//    // transaction fee
//    let transactionFee = UInt64(swapTransactions.count) * 2 * lamportsPerSignature
//
//    // account creation fee
//    let accountCreationFee = swapTransactions.reduce(0, {$0+$1.accountCreationFee})
//
//    let expectedFee = FeeAmount(transaction: transactionFee, accountBalances: accountCreationFee)
//    return try await calculateNeededTopUpAmount(expectedFee: expectedFee, payingTokenMint: payingTokenMint)
//}


// MARK: - Helpers

///// Calculate needed fee for topup transaction by forming fake transaction
//func calculateTopUpFee(relayAccountStatus: RelayAccountStatus) throws -> FeeAmount {
//    guard let lamportsPerSignature = cache.lamportsPerSignature,
//          let minimumRelayAccountBalance = cache.minimumRelayAccountBalance,
//          let minimumTokenAccountBalance = cache.minimumTokenAccountBalance
//    else {throw FeeRelayer.Error.relayInfoMissing}
//    var topUpFee = FeeAmount.zero
//    
//    // transaction fee
//    let numberOfSignatures: UInt64 = 2 // feePayer's signature, owner's Signature
////        numberOfSignatures += 1 // transferAuthority
//    topUpFee.transaction = numberOfSignatures * lamportsPerSignature
//    
//    // account creation fee
//    if relayAccountStatus == .notYetCreated {
//        topUpFee.accountBalances += minimumRelayAccountBalance
//    }
//    
//    // swap fee
//    topUpFee.accountBalances += minimumTokenAccountBalance
//    
//    return topUpFee
//}
//
//func calculateTopUpAmount(
//    targetAmount: UInt64,
//    relayAccountStatus: RelayAccountStatus,
//    freeTransactionFeeLimit: FreeTransactionFeeLimit?
//) throws -> (topUpAmount: UInt64, expectedFee: UInt64) {
//    // get cache
//    guard let minimumRelayAccountBalance = cache.minimumRelayAccountBalance,
//          let lamportsPerSignature = cache.lamportsPerSignature,
//          let minimumTokenAccountBalance = cache.minimumTokenAccountBalance
//    else {throw FeeRelayer.Error.relayInfoMissing}
//    
//    // current_fee
//    var currentFee: UInt64 = 0
//    if relayAccountStatus == .notYetCreated {
//        currentFee += minimumRelayAccountBalance
//    }
//    
//    let transactionNetworkFee = 2 * lamportsPerSignature // feePayer, owner
//    if freeTransactionFeeLimit?.isFreeTransactionFeeAvailable(transactionFee: transactionNetworkFee) == false {
//        currentFee += transactionNetworkFee
//    }
//    
//    // swap_amount_out
////        let swapAmountOut = targetAmount + currentFee
//    var swapAmountOut = targetAmount
//    if relayAccountStatus == .notYetCreated {
//        swapAmountOut += getRelayAccountCreationCost() // Temporary solution
//    } else {
//        swapAmountOut += currentFee
//    }
//    
//    // expected_fee
//    let expectedFee = currentFee + minimumTokenAccountBalance
//    
//    return (topUpAmount: swapAmountOut, expectedFee: expectedFee)
//}
