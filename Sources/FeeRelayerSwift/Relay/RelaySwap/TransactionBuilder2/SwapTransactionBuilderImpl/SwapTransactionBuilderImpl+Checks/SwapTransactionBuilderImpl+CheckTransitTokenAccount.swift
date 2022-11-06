//
//  File.swift
//  
//
//  Created by Chung Tran on 06/11/2022.
//

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension SwapTransactionBuilderImpl {
    func checkTransitTokenAccount(
        owner: PublicKey,
        poolsPair: PoolsPair,
        output: inout SwapTransactionBuilderOutput
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

        output.needsCreateTransitTokenAccount = needsCreateTransitTokenAccount
        output.transitTokenAccountAddress = transitToken?.address
        output.transitTokenMintPubkey = transitToken?.mint
    }
}
