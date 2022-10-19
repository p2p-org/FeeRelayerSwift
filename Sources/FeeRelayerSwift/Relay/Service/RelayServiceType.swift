// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

/// The service that allows users to do gas-less transactions.
public protocol RelayService {
    
    var feeCalculator: RelayFeeCalculator { get }
    
    func topUpAndRelayTransaction(
        _ context: RelayContext,
        _ preparedTransaction: PreparedTransaction,
        fee payingFeeToken: TokenAccount?,
        config configuration: FeeRelayerConfiguration
    ) async throws -> TransactionID

    func topUpAndRelayTransaction(
        _ context: RelayContext,
        _ preparedTransaction: [PreparedTransaction],
        fee payingFeeToken: TokenAccount?,
        config configuration: FeeRelayerConfiguration
    ) async throws -> [TransactionID]
    
    func getFeePayer() async throws -> PublicKey
}
