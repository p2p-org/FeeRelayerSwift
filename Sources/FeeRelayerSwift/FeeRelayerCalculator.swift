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
