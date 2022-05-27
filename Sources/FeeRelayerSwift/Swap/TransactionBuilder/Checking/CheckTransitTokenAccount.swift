// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension SwapTransactionBuilder {
    static func checkTransitTokenAccount(_ context: inout BuildContext) async throws {
        let transitToken = try? TransitTokenAccountAnalysator.getTransitToken(
            solanaApiClient: context.solanaApiClient,
            orcaSwap: context.orcaSwap,
            account: context.config.userAccount,
            pools: context.config.pools
        )
        
        let needsCreateTransitTokenAccount = try await TransitTokenAccountAnalysator
            .checkIfNeedsCreateTransitTokenAccount(
                solanaApiClient: context.solanaApiClient,
                transitToken: transitToken
            )

        context.env.needsCreateTransitTokenAccount = needsCreateTransitTokenAccount
        context.env.transitTokenAccountAddress = transitToken?.address
        context.env.transitTokenMintPubkey = transitToken?.mint
    }
}