// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

protocol TransitTokenAccountManagerType {
    func getTransitToken(pools: PoolsPair) throws -> TokenAccount?
    func checkIfNeedsCreateTransitTokenAccount(transitToken: TokenAccount?) async throws -> Bool?
}

class TransitTokenAccountManager: TransitTokenAccountManagerType {
    private let owner: PublicKey
    private let solanaAPIClient: SolanaAPIClient
    private let orcaSwap: OrcaSwapType
    
    init(owner: PublicKey, solanaAPIClient: SolanaAPIClient, orcaSwap: OrcaSwapType) {
        self.owner = owner
        self.solanaAPIClient = solanaAPIClient
        self.orcaSwap = orcaSwap
    }
    
    func getTransitToken(pools: PoolsPair) throws -> TokenAccount? {
        guard let transitTokenMintPubkey = try getTransitTokenMintPubkey(pools: pools) else { return nil }

        let transitTokenAccountAddress = try RelayProgram.getTransitTokenAccountAddress(
            user: owner,
            transitTokenMint: transitTokenMintPubkey,
            network: solanaAPIClient.endpoint.network
        )

        return TokenAccount(
            address: transitTokenAccountAddress,
            mint: transitTokenMintPubkey
        )
    }
    
    func getTransitTokenMintPubkey(pools: PoolsPair) throws -> PublicKey? {
        guard pools.count == 2 else { return nil }
        let interTokenName = pools[0].tokenBName
        return try PublicKey(string: orcaSwap.getMint(tokenName: interTokenName))
    }
    
    func checkIfNeedsCreateTransitTokenAccount(transitToken: TokenAccount?) async throws -> Bool? {
        guard let transitToken = transitToken else { return nil }

        guard let account: BufferInfo<AccountInfo> = try await solanaAPIClient.getAccountInfo(account: transitToken.address.base58EncodedString) else {
            return true
        }
        
        return account.data.mint != transitToken.mint
    }
}
