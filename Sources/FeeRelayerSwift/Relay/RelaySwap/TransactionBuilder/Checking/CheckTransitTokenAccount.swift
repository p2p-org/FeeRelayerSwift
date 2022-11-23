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
        let transitTokenAccountManager = TransitTokenAccountManager(
            owner: owner,
            solanaAPIClient: solanaAPIClient,
            orcaSwap: orcaSwap
        )
        let transitToken = try? transitTokenAccountManager.getTransitToken(
            pools: poolsPair
        )
        
        let needsCreateTransitTokenAccount = try await transitTokenAccountManager
            .checkIfNeedsCreateTransitTokenAccount(
                transitToken: transitToken
            )

        env.needsCreateTransitTokenAccount = needsCreateTransitTokenAccount
        env.transitTokenAccountAddress = transitToken?.address
        env.transitTokenMintPubkey = transitToken?.mint
    }
}
