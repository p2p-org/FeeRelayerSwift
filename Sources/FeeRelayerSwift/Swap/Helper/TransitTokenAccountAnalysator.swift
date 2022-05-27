// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

class TransitTokenAccountAnalysator {
    internal static func getTransitToken(
        solanaApiClient: SolanaAPIClient,
        orcaSwap: OrcaSwap,
        account: Account,
        pools: PoolsPair
    ) throws -> TokenAccount? {
        guard let transitTokenMintPubkey = try getTransitTokenMintPubkey(orcaSwap: orcaSwap, pools: pools) else { return nil }

        let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
            user: account.publicKey,
            transitTokenMint: transitTokenMintPubkey,
            network: solanaApiClient.endpoint.network
        )

        return TokenAccount(
            address: transitTokenAccountAddress,
            mint: transitTokenMintPubkey
        )
    }

    internal static func getTransitTokenMintPubkey(orcaSwap: OrcaSwap, pools: PoolsPair) throws -> PublicKey? {
        guard pools.count == 2 else { return nil }
        let interTokenName = pools[0].tokenBName
        return try PublicKey(string: orcaSwap.getMint(tokenName: interTokenName))
    }
    
    internal static func checkIfNeedsCreateTransitTokenAccount(solanaApiClient: SolanaAPIClient, transitToken: TokenAccount?) async throws -> Bool? {
        guard let transitToken = transitToken else { return nil }

        guard let account: BufferInfo<AccountInfo> = try await solanaApiClient.getAccountInfo(account: transitToken.address.base58EncodedString) else {
            return true
        }
        
        return account.data.mint != transitToken.mint
    }
}