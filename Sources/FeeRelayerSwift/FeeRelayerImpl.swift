// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

class FeeRelayerImpl: FeeRelayer {
    /// TODO: Use enum keys
    private(set) var cache: Cache<String, Any>?
    private let feeCalculator: FeeRelayerCalculator

    init(feeCalculator: FeeRelayerCalculator, cache: Cache<Key, Value>? = nil) {
        self.cache = cache
        self.feeCalculator = feeCalculator
    }

    func getUsageStatus() async throws -> UsageStatus { fatalError("getUsageStatus() has not been implemented") }

    func topUpAndRelayTransaction(
        _: PreparedTransaction,
        fee _: Token?,
        config _: FeeRelayerConfiguration
    ) async throws -> TransactionID { fatalError("topUpAndRelayTransaction(_:fee:config:) has not been implemented") }

    func topUpAndRelayTransaction(
        _: [PreparedTransaction],
        fee _: Token?,
        config _: FeeRelayerConfiguration
    ) async throws -> [TransactionID] { fatalError("topUpAndRelayTransaction(_:fee:config:) has not been implemented") }
    
    internal func getMinimumTokenAccountBalance() async -> UInt64 {
        // Return from cache
        // ...
        
        // Return from api client
        return 0
    }
}

enum CacheKey: String {
    case minimumTokenAccountBalance
    case minimumRelayAccountBalance
    case minimumRelayAccountBalance
    case lamportsPerSignature
    case relayAccountStatus
    case preparedParams
    case freeTransactionFeeLimit
}