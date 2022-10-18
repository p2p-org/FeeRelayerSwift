// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

/// A fee relayer configuration.
public struct FeeRelayerConfiguration {
    let additionalPaybackFee: UInt64

    let operationType: StatsInfo.OperationType
    let currency: String?

    /// Automatically payback to fee relay.
    /// Set false if transaction has already pay back instruction
    let autoPayback: Bool

    public init(
        additionalPaybackFee: UInt64 = 0,
        operationType: StatsInfo.OperationType,
        currency: String? = nil,
        autoPayback: Bool = true
    ) {
        self.additionalPaybackFee = additionalPaybackFee
        self.operationType = operationType
        self.currency = currency
        self.autoPayback = autoPayback
    }
}

/// The service that allows users to do gas-less transactions.
public protocol FeeRelayer {
    var feeCalculator: FeeRelayerCalculator { get }

    func checkAndTopUp(
        _ context: FeeRelayerContext,
        expectedFee: FeeAmount,
        payingFeeToken: TokenAccount?
    ) async throws -> [String]?

    func getFeeTokenData(
        mint: String
    ) async throws -> FeeTokenData
    
    func relayTransaction(
        _ preparedTransaction: PreparedTransaction
    ) async throws -> String

    func topUpAndRelayTransaction(
        _ context: FeeRelayerContext,
        _ preparedTransaction: PreparedTransaction,
        fee payingFeeToken: TokenAccount?,
        config configuration: FeeRelayerConfiguration
    ) async throws -> TransactionID

    func topUpAndRelayTransaction(
        _ context: FeeRelayerContext,
        _ preparedTransaction: [PreparedTransaction],
        fee payingFeeToken: TokenAccount?,
        config configuration: FeeRelayerConfiguration
    ) async throws -> [TransactionID]

    func getFeePayer() async throws -> PublicKey
}
