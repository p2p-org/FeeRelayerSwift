// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension SwapTransactionBuilder {
    static func checkTransitTokenAccount(_ context: inout BuildContext) async throws {
        let transitToken = try? TransitTokenAccountManager.getTransitToken(
            network: context.solanaApiClient.endpoint.network,
            orcaSwap: context.orcaSwap,
            owner: context.config.userAccount.publicKey,
            pools: context.config.pools
        )
        
        let needsCreateTransitTokenAccount = try await TransitTokenAccountManager
            .checkIfNeedsCreateTransitTokenAccount(
                solanaApiClient: context.solanaApiClient,
                transitToken: transitToken
            )

        context.env.needsCreateTransitTokenAccount = needsCreateTransitTokenAccount
        context.env.transitTokenAccountAddress = transitToken?.address
        context.env.transitTokenMintPubkey = transitToken?.mint
    }
}
