// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

/// A fee relayer configuration.
struct FeeRelayerConfiguration {
    let additionalPaybackFee: UInt64

    init(additionalPaybackFee: UInt64 = 0) {
        self.additionalPaybackFee = additionalPaybackFee
    }
}

/// The service that allows users to do gas-less transactions.
protocol FeeRelayer {
    var account: Account { get throws }

    func topUpAndRelayTransaction(
        _ preparedTransaction: PreparedTransaction,
        fee payingFeeToken: TokenAccount?,
        config configuration: FeeRelayerConfiguration
    ) async throws -> TransactionID

    func topUpAndRelayTransaction(
        _ preparedTransaction: [PreparedTransaction],
        fee payingFeeToken: TokenAccount?,
        config configuration: FeeRelayerConfiguration
    ) async throws -> [TransactionID]
}
