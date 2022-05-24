// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation

class SwapFeeRelayerImpl: SwapFeeRelayer {
    let feeRelayer: FeeRelayer

    init(feeRelayer: FeeRelayer) { self.feeRelayer = feeRelayer }
    
    func calculateSwappingNetworkFees(
        swapPools: OrcaSwap.PoolsPair?,
        sourceTokenMint: String,
        destinationTokenMint: String,
        destinationAddress: String?
    ) async throws -> SolanaSwift.FeeAmount { fatalError("calculateSwappingNetworkFees(swapPools:sourceTokenMint:destinationTokenMint:destinationAddress:) has not been implemented") }
    
    func prepareSwapTransaction(
        sourceToken: Token,
        destinationTokenMint: String,
        destinationAddress: String?,
        fee payingFeeToken: Token,
        swapPools: OrcaSwapSwift.PoolsPair,
        inputAmount: UInt64,
        slippage: Double
    ) async throws -> (transactions: [SolanaSDK.PreparedTransaction], additionalPaybackFee: UInt64) { fatalError("prepareSwapTransaction(sourceToken:destinationTokenMint:destinationAddress:fee:swapPools:inputAmount:slippage:) has not been implemented") }
}
