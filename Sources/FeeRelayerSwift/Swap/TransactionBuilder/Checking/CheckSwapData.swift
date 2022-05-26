// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension SwapTransactionBuilder {
     static func checkSwapData(context: inout BuildContext, swapData: SwapData) throws {
        let userTransferAuthority = swapData.transferAuthorityAccount?.publicKey
        switch swapData.swapData {
        case let swap as DirectSwapData:
            guard let pool = context.config.pools.first else {throw FeeRelayerError.swapPoolsNotFound}
            
            // approve
            if let userTransferAuthority = userTransferAuthority {
                context.env.instructions.append(
                    TokenProgram.approveInstruction(
                        account: context.config.sourceAccount.address,
                        delegate: userTransferAuthority,
                        owner: try context.config.userAuthorityAddress,
                        multiSigners: [],
                        amount: swap.amountIn
                    )
                )
            }
            
            // swap
            context.env.instructions.append(
                try pool.createSwapInstruction(
                    userTransferAuthorityPubkey: userTransferAuthority ?? (try context.config.userAuthorityAddress),
                    sourceTokenAddress: context.config.sourceAccount.address,
                    destinationTokenAddress: context.env.userDestinationTokenAccountAddress!,
                    amountIn: swap.amountIn,
                    minAmountOut: swap.minimumAmountOut
                )
            )
        case let swap as TransitiveSwapData:
            // approve
            if let userTransferAuthority = userTransferAuthority {
                context.env.instructions.append(
                    TokenProgram.approveInstruction(
                        account: context.config.sourceAccount.address,
                        delegate: userTransferAuthority,
                        owner: try context.config.userAuthorityAddress,
                        multiSigners: [],
                        amount: swap.from.amountIn
                    )
                )
            }
            
            // create transit token account
            let transitTokenMint = try PublicKey(string: swap.transitTokenMintPubkey)
            let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
                user: try context.config.userAuthorityAddress,
                transitTokenMint: transitTokenMint,
                network: context.config.network
            )
            
            if context.env.needsCreateTransitTokenAccount == true {
                context.env.instructions.append(
                    try Program.createTransitTokenAccountInstruction(
                        feePayer: context.feeRelayerContext.feePayerAddress,
                        userAuthority: try context.config.userAuthorityAddress,
                        transitTokenAccount: transitTokenAccountAddress,
                        transitTokenMint: transitTokenMint,
                        network: context.config.network
                    )
                )
            }
            
            // relay swap
            context.env.instructions.append(
                try Program.createRelaySwapInstruction(
                    transitiveSwap: swap,
                    userAuthorityAddressPubkey: context.config.userAuthorityAddress,
                    sourceAddressPubkey: context.config.sourceAccount.address,
                    transitTokenAccount: transitTokenAccountAddress,
                    destinationAddressPubkey: context.env.userDestinationTokenAccountAddress!,
                    feePayerPubkey: context.feeRelayerContext.feePayerAddress,
                    network: context.config.network
                )
            )
        default:
            fatalError("unsupported swap type")
        }
    }
}