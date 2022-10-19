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
                        account: context.env.userSource!,
                        delegate: userTransferAuthority,
                        owner: context.config.userAccount.publicKey,
                        multiSigners: [],
                        amount: swap.amountIn
                    )
                )
            }
            
            // swap
            context.env.instructions.append(
                try pool.createSwapInstruction(
                    userTransferAuthorityPubkey: userTransferAuthority ?? (context.config.userAccount.publicKey),
                    sourceTokenAddress: context.env.userSource!,
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
                        account: context.env.userSource!,
                        delegate: userTransferAuthority,
                        owner: context.config.userAccount.publicKey,
                        multiSigners: [],
                        amount: swap.from.amountIn
                    )
                )
            }
            
            // create transit token account
            let transitTokenMint = try PublicKey(string: swap.transitTokenMintPubkey)
            let transitTokenAccountAddress = try RelayProgram.getTransitTokenAccountAddress(
                user: context.config.userAccount.publicKey,
                transitTokenMint: transitTokenMint,
                network: context.solanaApiClient.endpoint.network
            )
            
            if context.env.needsCreateTransitTokenAccount == true {
                context.env.instructions.append(
                    try RelayProgram.createTransitTokenAccountInstruction(
                        feePayer: context.feeRelayerContext.feePayerAddress,
                        userAuthority: context.config.userAccount.publicKey,
                        transitTokenAccount: transitTokenAccountAddress,
                        transitTokenMint: transitTokenMint,
                        network: context.solanaApiClient.endpoint.network
                    )
                )
            }
            
            // relay swap
            context.env.instructions.append(
                try RelayProgram.createRelaySwapInstruction(
                    transitiveSwap: swap,
                    userAuthorityAddressPubkey: context.config.userAccount.publicKey,
                    sourceAddressPubkey: context.env.userSource!,
                    transitTokenAccount: transitTokenAccountAddress,
                    destinationAddressPubkey: context.env.userDestinationTokenAccountAddress!,
                    feePayerPubkey: context.feeRelayerContext.feePayerAddress,
                    network: context.solanaApiClient.endpoint.network
                )
            )
        default:
            fatalError("unsupported swap type")
        }
    }
}
