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
            guard let pool = context.pools.first else {throw FeeRelayerError.swapPoolsNotFound}
            
            // approve
            if let userTransferAuthority = userTransferAuthority {
                context.instructions.append(
                    TokenProgram.approveInstruction(
                        account: context.sourceToken.address,
                        delegate: userTransferAuthority,
                        owner: try context.userAuthorityAddress,
                        multiSigners: [],
                        amount: swap.amountIn
                    )
                )
            }
            
            // swap
            context.instructions.append(
                try pool.createSwapInstruction(
                    userTransferAuthorityPubkey: userTransferAuthority ?? (try context.userAuthorityAddress),
                    sourceTokenAddress: context.sourceToken.address,
                    destinationTokenAddress: context.userDestinationTokenAccountAddress!,
                    amountIn: swap.amountIn,
                    minAmountOut: swap.minimumAmountOut
                )
            )
        case let swap as TransitiveSwapData:
            // approve
            if let userTransferAuthority = userTransferAuthority {
                context.instructions.append(
                    TokenProgram.approveInstruction(
                        account: context.sourceToken.address,
                        delegate: userTransferAuthority,
                        owner: try context.userAuthorityAddress,
                        multiSigners: [],
                        amount: swap.from.amountIn
                    )
                )
            }
            
            // create transit token account
            let transitTokenMint = try PublicKey(string: swap.transitTokenMintPubkey)
            let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
                user: try context.userAuthorityAddress,
                transitTokenMint: transitTokenMint,
                network: context.network
            )
            
            if context.needsCreateTransitTokenAccount == true {
                context.instructions.append(
                    try Program.createTransitTokenAccountInstruction(
                        feePayer: context.feeRelayerContext.feePayerAddress,
                        userAuthority: try context.userAuthorityAddress,
                        transitTokenAccount: transitTokenAccountAddress,
                        transitTokenMint: transitTokenMint,
                        network: context.network
                    )
                )
            }
            
            // relay swap
            context.instructions.append(
                try Program.createRelaySwapInstruction(
                    transitiveSwap: swap,
                    userAuthorityAddressPubkey: context.userAuthorityAddress,
                    sourceAddressPubkey: context.sourceToken.address,
                    transitTokenAccount: transitTokenAccountAddress,
                    destinationAddressPubkey: context.userDestinationTokenAccountAddress!,
                    feePayerPubkey: context.feeRelayerContext.feePayerAddress,
                    network: context.network
                )
            )
        default:
            fatalError("unsupported swap type")
        }
    }
}