// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

/// The service that allows users to create gas-less swap transactions.
protocol SwapFeeRelayer {
    func calculateSwappingNetworkFees(
        swapPools: OrcaSwap.PoolsPair?,
        sourceTokenMint: String,
        destinationTokenMint: String,
        destinationAddress: String?
    ) async throws -> FeeAmount

    func prepareSwapTransaction(
        sourceToken: Token,
        destinationTokenMint: String,
        destinationAddress: String?,
        fee payingFeeToken: Token,
        swapPools: PoolsPair,
        inputAmount: UInt64,
        slippage: Double
    ) async throws -> (transactions: [SolanaSDK.PreparedTransaction], additionalPaybackFee: UInt64)
}
