// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

public protocol FeeRelayerCalculator {
    /// Calculate a top up amount for user's relayer account.
    ///
    /// The user's relayer account will be used as fee payer address.
    /// - Parameters:
    ///   - context: Processing context
    ///   - expectedFee: an amount of fee, that blockchain need to process if user's send directly.
    ///   - payingTokenMint: a mint address of spl token, that user will use to play fee.
    /// - Returns: Fee amount in SOL
    /// - Throws:
    func calculateNeededTopUpAmount(
        _ context: FeeRelayerContext,
        expectedFee: FeeAmount,
        payingTokenMint: PublicKey?
    ) async throws -> FeeAmount

    func calculateExpectedFeeForTopUp(_ context: FeeRelayerContext) throws -> UInt64

    /// Convert fee amount into spl value.
    ///
    /// - Parameters:
    ///   - orcaSwap: OrcaSwap service
    ///   - feeInSOL: a fee amount in SOL
    ///   - payingFeeTokenMint: a mint address of spl token, that user will use to play fee.
    /// - Returns:
    /// - Throws:
    func calculateFeeInPayingToken(
        orcaSwap: OrcaSwapType,
        feeInSOL: FeeAmount,
        payingFeeTokenMint: PublicKey
    ) async throws -> FeeAmount?
}

public class DefaultFreeRelayerCalculator: FeeRelayerCalculator {
    public init() {}
    
    public func calculateNeededTopUpAmount(
        _ context: FeeRelayerContext,
        expectedFee: FeeAmount,
        payingTokenMint: PublicKey?
    ) async throws -> FeeAmount {
        var amount = calculateMinTopUpAmount(
            context,
            expectedFee: expectedFee,
            payingTokenMint: payingTokenMint
        )
        
        // TODO: Ask Artem
        if amount.total > 0 && amount.total < 1000 {
            amount.transaction += 1000 - amount.total
        }
        
        // TODO: amount.transaction = max(1000, amount.total)
        return amount
    }
    
    private func calculateMinTopUpAmount(
        _ context: FeeRelayerContext,
        expectedFee: FeeAmount,
        payingTokenMint: PublicKey?
    ) -> FeeAmount {
        var neededAmount = expectedFee
        
        // expected fees
        let expectedTopUpNetworkFee = 2 * context.lamportsPerSignature
        let expectedTransactionNetworkFee = expectedFee.transaction
        
        // real fees
        var neededTopUpNetworkFee = expectedTopUpNetworkFee
        var neededTransactionNetworkFee = expectedTransactionNetworkFee
        
        // is Top up free
        if context.usageStatus.isFreeTransactionFeeAvailable(transactionFee: expectedTopUpNetworkFee) {
            neededTopUpNetworkFee = 0
        }
        
        // is transaction free
        if context.usageStatus.isFreeTransactionFeeAvailable(transactionFee: expectedTopUpNetworkFee + expectedTransactionNetworkFee, forNextTransaction: true)
        {
            neededTransactionNetworkFee = 0
        }
        
        neededAmount.transaction = neededTopUpNetworkFee + neededTransactionNetworkFee
        
        // transaction is totally free
        if neededAmount.total == 0 {
            return neededAmount
        }
        
        let neededAmountWithoutCheckingRelayAccount = neededAmount
        let minimumRelayAccountBalance = context.minimumRelayAccountBalance
        
        // check if relay account current balance can cover part of needed amount
        if var relayAccountBalance = context.relayAccountStatus.balance {
            if relayAccountBalance < minimumRelayAccountBalance {
                neededAmount.transaction += minimumRelayAccountBalance - relayAccountBalance
            } else {
                relayAccountBalance -= minimumRelayAccountBalance
                
                // if relayAccountBalance has enough balance to cover transaction fee
                if relayAccountBalance >= neededAmount.transaction {
                    
                    neededAmount.transaction = 0
                    
                    // if relayAccountBalance has enough balance to cover accountBalances fee too
                    if relayAccountBalance - neededAmount.transaction >= neededAmount.accountBalances {
                        neededAmount.accountBalances = 0
                    }
                    
                    // Relay account balance can cover part of account creation fee
                    else {
                        neededAmount.accountBalances -= (relayAccountBalance - neededAmount.transaction)
                    }
                }
                // if not, relayAccountBalance can cover part of transaction fee
                else {
                    neededAmount.transaction -= relayAccountBalance
                }
            }
        } else {
            neededAmount.transaction += minimumRelayAccountBalance
        }
        
        // if relay account could not cover all fees and paying token is WSOL, the compensation will be done without the existense of relay account
        if neededAmount.total > 0, payingTokenMint == PublicKey.wrappedSOLMint {
            return neededAmountWithoutCheckingRelayAccount
        }
        
        return neededAmount
    }
    
    public func calculateExpectedFeeForTopUp(_ context: FeeRelayerContext) throws -> UInt64 {
        var expectedFee: UInt64 = 0
        if context.relayAccountStatus == .notYetCreated {
            expectedFee += context.minimumRelayAccountBalance
        }
        
        let transactionNetworkFee = 2 * context.lamportsPerSignature // feePayer, owner
        if context.usageStatus.isFreeTransactionFeeAvailable(transactionFee: transactionNetworkFee) == false {
            expectedFee += transactionNetworkFee
        }
        
        expectedFee += context.minimumTokenAccountBalance
        return expectedFee
    }
    
    public func calculateFeeInPayingToken(
        orcaSwap: OrcaSwapType,
        feeInSOL: FeeAmount,
        payingFeeTokenMint: PublicKey
    ) async throws -> FeeAmount? {
        if payingFeeTokenMint == PublicKey.wrappedSOLMint {
            return feeInSOL
        }
        let tradableTopUpPoolsPair = try await orcaSwap.getTradablePoolsPairs(
            fromMint: payingFeeTokenMint.base58EncodedString,
            toMint: PublicKey.wrappedSOLMint.base58EncodedString
        )
            
        guard let topUpPools = try orcaSwap.findBestPoolsPairForEstimatedAmount(feeInSOL.total, from: tradableTopUpPoolsPair) else {
            throw FeeRelayerError.swapPoolsNotFound
        }
        
        let transactionFee = topUpPools.getInputAmount(minimumAmountOut: feeInSOL.transaction, slippage: FeeRelayerConstants.topUpSlippage)
        let accountCreationFee = topUpPools.getInputAmount(minimumAmountOut: feeInSOL.accountBalances, slippage: FeeRelayerConstants.topUpSlippage)
                
        return .init(transaction: transactionFee ?? 0, accountBalances: accountCreationFee ?? 0)
    }
}
