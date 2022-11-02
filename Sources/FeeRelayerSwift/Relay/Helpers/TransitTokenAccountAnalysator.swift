// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

class TransitTokenAccountManager {
    internal static func getTransitToken(
        network: SolanaSwift.Network,
        orcaSwap: OrcaSwapType,
        account: Account,
        pools: PoolsPair
    ) throws -> TokenAccount? {
        guard let transitTokenMintPubkey = try getTransitTokenMintPubkey(orcaSwap: orcaSwap, pools: pools) else { return nil }

        let transitTokenAccountAddress = try RelayProgram.getTransitTokenAccountAddress(
            user: account.publicKey,
            transitTokenMint: transitTokenMintPubkey,
            network: network
        )

        return TokenAccount(
            address: transitTokenAccountAddress,
            mint: transitTokenMintPubkey
        )
    }

    internal static func getTransitTokenMintPubkey(orcaSwap: OrcaSwapType, pools: PoolsPair) throws -> PublicKey? {
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
