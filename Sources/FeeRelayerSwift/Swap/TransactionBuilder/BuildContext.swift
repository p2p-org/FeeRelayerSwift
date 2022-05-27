// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension SwapTransactionBuilder {
    struct BuildContext {
        let feeRelayerContext: FeeRelayerContext
        let solanaApiClient: SolanaAPIClient
        let orcaSwap: OrcaSwap

        let config: Configuration
        var env: Environment
    }
}

extension SwapTransactionBuilder.BuildContext {
    struct Configuration {
            let userAccount: Account
        
            let pools: PoolsPair
            let inputAmount: UInt64
            let slippage: Double
        
            let sourceAccount: TokenAccount
            let destinationTokenMint: PublicKey
            let destinationAddress: PublicKey?
            
            let blockhash: String
        }
        
        struct Environment {
            var userSource: PublicKey? = nil
            var sourceWSOLNewAccount: Account? = nil
            
            var transitTokenMintPubkey: PublicKey?
            var transitTokenAccountAddress: PublicKey?
            var needsCreateTransitTokenAccount: Bool?
        
            var destinationNewAccount: Account? = nil
            var userDestinationTokenAccountAddress: PublicKey? = nil
        
            var instructions = [TransactionInstruction]()
            var additionalTransaction: PreparedTransaction? = nil
        
            var signers: [Account] = []
        
            // Building fee
            var accountCreationFee: Lamports = 0
            var additionalPaybackFee: UInt64 = 0
        }
}