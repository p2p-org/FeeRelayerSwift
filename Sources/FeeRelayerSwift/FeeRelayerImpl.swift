// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

class FeeRelayerImpl: FeeRelayer {
    private(set) var cache: Cache<Key, Value>? = nil
    
    func getUsageStatus() async throws -> UsageStatus { fatalError("getUsageStatus() has not been implemented") }
    
    func topUpAndRelayTransaction(
        _ preparedTransaction: PreparedTransaction,
        fee payingFeeToken: Token?,
        config configuration: FeeRelayerConfiguration
    ) async throws -> TransactionID { fatalError("topUpAndRelayTransaction(_:fee:config:) has not been implemented") }
    
    func topUpAndRelayTransaction(
        _ preparedTransaction: [PreparedTransaction],
        fee payingFeeToken: Token?,
        config configuration: FeeRelayerConfiguration
    ) async throws -> [TransactionID] { fatalError("topUpAndRelayTransaction(_:fee:config:) has not been implemented") }
}