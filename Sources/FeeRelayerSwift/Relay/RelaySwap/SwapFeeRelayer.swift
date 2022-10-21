// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

/// The service that allows users to create gas-less swap transactions.
public protocol SwapFeeRelayer {
    var calculator: SwapFeeRelayerCalculator { get }
    
    func prepareSwapTransaction(
        _ context: RelayContext,
        sourceToken: TokenAccount,
        destinationTokenMint: PublicKey,
        destinationAddress: PublicKey?,
        fee payingFeeToken: TokenAccount?,
        swapPools: PoolsPair,
        inputAmount: UInt64,
        slippage: Double
    ) async throws -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64)
}
