// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension SwapTransactionBuilder {
    static func checkTransitTokenAccount(
        solanaAPIClient: SolanaAPIClient,
        orcaSwap: OrcaSwapType,
        owner: PublicKey,
        poolsPair: PoolsPair,
        env: inout BuildContext.Environment
    ) async throws {
        let transitToken = try? TransitTokenAccountManager.getTransitToken(
            network: solanaAPIClient.endpoint.network,
            orcaSwap: orcaSwap,
            owner: owner,
            pools: poolsPair
        )
        
        let needsCreateTransitTokenAccount = try await TransitTokenAccountManager
            .checkIfNeedsCreateTransitTokenAccount(
                solanaApiClient: solanaAPIClient,
                transitToken: transitToken
            )

        env.needsCreateTransitTokenAccount = needsCreateTransitTokenAccount
        env.transitTokenAccountAddress = transitToken?.address
        env.transitTokenMintPubkey = transitToken?.mint
    }
}
