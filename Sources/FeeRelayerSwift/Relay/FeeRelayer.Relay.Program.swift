//
//  FeeRelayer.Relay.Program.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 29/12/2021.
//

import Foundation
import SolanaSwift

extension FeeRelayer.Relay {
    enum Program {
        static func id(network: SolanaSDK.Network) -> SolanaSDK.PublicKey {
            switch network {
            case .mainnetBeta:
                return "12YKFL4mnZz6CBEGePrf293mEzueQM3h8VLPUJsKpGs9"
            case .devnet:
                return "6xKJFyuM6UHCT8F5SBxnjGt6ZrZYjsVfnAnAeHPU775k"
            default:
                fatalError("Unsupported network")
            }
        }
        
        static func getUserRelayAddress(
            user: SolanaSDK.PublicKey,
            network: SolanaSDK.Network
        ) throws -> SolanaSDK.PublicKey {
            try .findProgramAddress(seeds: [user.data, "relay".data(using: .utf8)!], programId: id(network: network)).0
        }
        
        static func getUserTemporaryWSOLAddress(
            user: SolanaSDK.PublicKey,
            network: SolanaSDK.Network
        ) throws -> SolanaSDK.PublicKey {
            try .findProgramAddress(seeds: [user.data, "temporary_wsol".data(using: .utf8)!], programId: id(network: network)).0
        }
        
        static func getTransitTokenAccountAddress(
            user: SolanaSDK.PublicKey,
            transitTokenMint: SolanaSDK.PublicKey,
            network: SolanaSDK.Network
        ) throws -> SolanaSDK.PublicKey {
            try .findProgramAddress(seeds: [user.data, transitTokenMint.data, "transit".data(using: .utf8)!], programId: id(network: network)).0
        }
        
        static func topUpSwapInstruction(
            network: SolanaSDK.Network,
            topUpSwap: FeeRelayerRelaySwapType,
            userAuthorityAddress: SolanaSDK.PublicKey,
            userSourceTokenAccountAddress: SolanaSDK.PublicKey,
            feePayerAddress: SolanaSDK.PublicKey
        ) throws -> SolanaSDK.TransactionInstruction {
            let userRelayAddress = try getUserRelayAddress(user: userAuthorityAddress, network: network)
            let userTemporarilyWSOLAddress = try getUserTemporaryWSOLAddress(user: userAuthorityAddress, network: network)
            
            switch topUpSwap {
            case let swap as DirectSwapData:
                return topUpWithSPLSwapDirectInstruction(
                    feePayer: feePayerAddress,
                    userAuthority: userAuthorityAddress,
                    userRelayAccount: userRelayAddress,
                    userTransferAuthority: try SolanaSDK.PublicKey(string: swap.transferAuthorityPubkey),
                    userSourceTokenAccount: userSourceTokenAccountAddress,
                    userTemporaryWsolAccount: userTemporarilyWSOLAddress,
                    swapProgramId: try SolanaSDK.PublicKey(string: swap.programId),
                    swapAccount: try SolanaSDK.PublicKey(string: swap.accountPubkey),
                    swapAuthority: try SolanaSDK.PublicKey(string: swap.authorityPubkey),
                    swapSource: try SolanaSDK.PublicKey(string: swap.sourcePubkey),
                    swapDestination: try SolanaSDK.PublicKey(string: swap.destinationPubkey),
                    poolTokenMint: try SolanaSDK.PublicKey(string: swap.poolTokenMintPubkey),
                    poolFeeAccount: try SolanaSDK.PublicKey(string: swap.poolFeeAccountPubkey),
                    amountIn: swap.amountIn,
                    minimumAmountOut: swap.minimumAmountOut,
                    network: network
                )
            case let swap as TransitiveSwapData:
                return try topUpWithSPLSwapTransitiveInstruction(
                    feePayer: feePayerAddress,
                    userAuthority: userAuthorityAddress,
                    userRelayAccount: userRelayAddress,
                    userTransferAuthority: try SolanaSDK.PublicKey(string: swap.from.transferAuthorityPubkey),
                    userSourceTokenAccount: userSourceTokenAccountAddress,
                    userDestinationTokenAccount: userTemporarilyWSOLAddress,
                    transitTokenMint: try SolanaSDK.PublicKey(string: swap.transitTokenMintPubkey),
                    swapFromProgramId: try SolanaSDK.PublicKey(string: swap.from.programId),
                    swapFromAccount: try SolanaSDK.PublicKey(string: swap.from.accountPubkey),
                    swapFromAuthority: try SolanaSDK.PublicKey(string: swap.from.authorityPubkey),
                    swapFromSource: try SolanaSDK.PublicKey(string: swap.from.sourcePubkey),
                    swapFromDestination: try SolanaSDK.PublicKey(string: swap.from.destinationPubkey),
                    swapFromPoolTokenMint: try SolanaSDK.PublicKey(string: swap.from.poolTokenMintPubkey),
                    swapFromPoolFeeAccount: try SolanaSDK.PublicKey(string: swap.from.poolFeeAccountPubkey),
                    swapToProgramId: try SolanaSDK.PublicKey(string: swap.to.programId),
                    swapToAccount: try SolanaSDK.PublicKey(string: swap.to.accountPubkey),
                    swapToAuthority: try SolanaSDK.PublicKey(string: swap.to.authorityPubkey),
                    swapToSource: try SolanaSDK.PublicKey(string: swap.to.sourcePubkey),
                    swapToDestination: try SolanaSDK.PublicKey(string: swap.to.destinationPubkey),
                    swapToPoolTokenMint: try SolanaSDK.PublicKey(string: swap.to.poolTokenMintPubkey),
                    swapToPoolFeeAccount: try SolanaSDK.PublicKey(string: swap.to.poolFeeAccountPubkey),
                    amountIn: swap.from.amountIn,
                    transitMinimumAmount: swap.from.minimumAmountOut,
                    minimumAmountOut: swap.to.minimumAmountOut,
                    network: network
                )
            default:
                fatalError("unsupported swap type")
            }
        }
        
        static func transferSolInstruction(
            userAuthorityAddress: SolanaSDK.PublicKey,
            recipient: SolanaSDK.PublicKey,
            lamports: UInt64,
            network: SolanaSDK.Network
        ) throws -> SolanaSDK.TransactionInstruction {
            .init(
                keys: [
                    .readonly(publicKey: userAuthorityAddress, isSigner: true),
                    .writable(publicKey: try getUserRelayAddress(user: userAuthorityAddress, network: network), isSigner: false),
                    .writable(publicKey: recipient, isSigner: false),
                    .readonly(publicKey: .programId, isSigner: false),
                ],
                programId: id(network: network),
                data: [
                    UInt8(2),
                    lamports
                ]
            )
        }
        
        static func createTransitTokenAccountInstruction(
            feePayer: SolanaSDK.PublicKey,
            userAuthority: SolanaSDK.PublicKey,
            transitTokenAccount: SolanaSDK.PublicKey,
            transitTokenMint: SolanaSDK.PublicKey,
            network: SolanaSDK.Network
        ) throws -> SolanaSDK.TransactionInstruction {
            .init(
                keys: [
                    .writable(publicKey: transitTokenAccount, isSigner: false),
                    .readonly(publicKey: transitTokenMint, isSigner: false),
                    .writable(publicKey: userAuthority, isSigner: true),
                    .readonly(publicKey: feePayer, isSigner: true),
                    .readonly(publicKey: .tokenProgramId, isSigner: false),
                    .readonly(publicKey: .sysvarRent, isSigner: false),
                    .readonly(publicKey: .programId, isSigner: false)
                ],
                programId: id(network: network),
                data: [
                    UInt8(3)
                ]
            )
        }
        
        static func createRelaySwapInstruction(
            transitiveSwap: TransitiveSwapData,
            userAuthorityAddressPubkey: SolanaSDK.PublicKey,
            sourceAddressPubkey: SolanaSDK.PublicKey,
            transitTokenAccount: SolanaSDK.PublicKey,
            destinationAddressPubkey: SolanaSDK.PublicKey,
            feePayerPubkey: SolanaSDK.PublicKey,
            network: SolanaSDK.Network
        ) throws -> SolanaSDK.TransactionInstruction {
            let transferAuthorityPubkey = try SolanaSDK.PublicKey(string: transitiveSwap.from.transferAuthorityPubkey)
            let transitTokenMintPubkey = try SolanaSDK.PublicKey(string: transitiveSwap.transitTokenMintPubkey)
            let swapFromProgramId = try SolanaSDK.PublicKey(string: transitiveSwap.from.programId)
            let swapFromAccount = try SolanaSDK.PublicKey(string: transitiveSwap.from.accountPubkey)
            let swapFromAuthority = try SolanaSDK.PublicKey(string: transitiveSwap.from.authorityPubkey)
            let swapFromSource = try SolanaSDK.PublicKey(string: transitiveSwap.from.sourcePubkey)
            let swapFromDestination = try SolanaSDK.PublicKey(string: transitiveSwap.from.destinationPubkey)
            let swapFromTokenMint = try SolanaSDK.PublicKey(string: transitiveSwap.from.poolTokenMintPubkey)
            let swapFromPoolFeeAccount = try SolanaSDK.PublicKey(string: transitiveSwap.from.poolFeeAccountPubkey)
            let swapToProgramId = try SolanaSDK.PublicKey(string: transitiveSwap.to.programId)
            let swapToAccount = try SolanaSDK.PublicKey(string: transitiveSwap.to.accountPubkey)
            let swapToAuthority = try SolanaSDK.PublicKey(string: transitiveSwap.to.authorityPubkey)
            let swapToSource = try SolanaSDK.PublicKey(string: transitiveSwap.to.sourcePubkey)
            let swapToDestination = try SolanaSDK.PublicKey(string: transitiveSwap.to.destinationPubkey)
            let swapToPoolTokenMint = try SolanaSDK.PublicKey(string: transitiveSwap.to.poolTokenMintPubkey)
            let swapToPoolFeeAccount = try SolanaSDK.PublicKey(string: transitiveSwap.to.poolFeeAccountPubkey)
            let amountIn = transitiveSwap.from.amountIn
            let transitMinimumAmount = transitiveSwap.from.minimumAmountOut
            let minimumAmountOut = transitiveSwap.to.minimumAmountOut
            
            
            return try splSwapTransitiveInstruction(
                feePayer: feePayerPubkey,
                userAuthority: userAuthorityAddressPubkey,
                userTransferAuthority: transferAuthorityPubkey,
                userSourceTokenAccount: sourceAddressPubkey,
                userTransitTokenAccount: transitTokenAccount,
                userDestinationTokenAccount: destinationAddressPubkey,
                transitTokenMint: transitTokenMintPubkey,
                swapFromProgramId: swapFromProgramId,
                swapFromAccount: swapFromAccount,
                swapFromAuthority: swapFromAuthority,
                swapFromSource: swapFromSource,
                swapFromDestination: swapFromDestination,
                swapFromPoolTokenMint: swapFromTokenMint,
                swapFromPoolFeeAccount: swapFromPoolFeeAccount,
                swapToProgramId: swapToProgramId,
                swapToAccount: swapToAccount,
                swapToAuthority: swapToAuthority,
                swapToSource: swapToSource,
                swapToDestination: swapToDestination,
                swapToPoolTokenMint: swapToPoolTokenMint,
                swapToPoolFeeAccount: swapToPoolFeeAccount,
                amountIn: amountIn,
                transitMinimumAmount: transitMinimumAmount,
                minimumAmountOut: minimumAmountOut,
                network: network
            )
        }
        
        // MARK: - Helpers
        private static func topUpWithSPLSwapDirectInstruction(
            feePayer: SolanaSDK.PublicKey,
            userAuthority: SolanaSDK.PublicKey,
            userRelayAccount: SolanaSDK.PublicKey,
            userTransferAuthority: SolanaSDK.PublicKey,
            userSourceTokenAccount: SolanaSDK.PublicKey,
            userTemporaryWsolAccount: SolanaSDK.PublicKey,
            swapProgramId: SolanaSDK.PublicKey,
            swapAccount: SolanaSDK.PublicKey,
            swapAuthority: SolanaSDK.PublicKey,
            swapSource: SolanaSDK.PublicKey,
            swapDestination: SolanaSDK.PublicKey,
            poolTokenMint: SolanaSDK.PublicKey,
            poolFeeAccount: SolanaSDK.PublicKey,
            amountIn: UInt64,
            minimumAmountOut: UInt64,
            network: SolanaSDK.Network
        ) -> SolanaSDK.TransactionInstruction {
            .init(
                keys: [
                    .readonly(publicKey: .wrappedSOLMint, isSigner: false),
                    .writable(publicKey: feePayer, isSigner: true),
                    .readonly(publicKey: userAuthority, isSigner: true),
                    .writable(publicKey: userRelayAccount, isSigner: false),
                    .readonly(publicKey: .tokenProgramId, isSigner: false),
                    .readonly(publicKey: swapProgramId, isSigner: false),
                    .readonly(publicKey: swapAccount, isSigner: false),
                    .readonly(publicKey: swapAuthority, isSigner: false),
                    .readonly(publicKey: userTransferAuthority, isSigner: true),
                    .writable(publicKey: userSourceTokenAccount, isSigner: false),
                    .writable(publicKey: userTemporaryWsolAccount, isSigner: false),
                    .writable(publicKey: swapSource, isSigner: false),
                    .writable(publicKey: swapDestination, isSigner: false),
                    .writable(publicKey: poolTokenMint, isSigner: false),
                    .writable(publicKey: poolFeeAccount, isSigner: false),
                    .readonly(publicKey: .sysvarRent, isSigner: false),
                    .readonly(publicKey: .programId, isSigner: false)
                ],
                programId: id(network: network),
                data: [
                    UInt8(0),
                    amountIn,
                    minimumAmountOut
                ]
            )
        }
        
        private static func topUpWithSPLSwapTransitiveInstruction(
            feePayer: SolanaSDK.PublicKey,
            userAuthority: SolanaSDK.PublicKey,
            userRelayAccount: SolanaSDK.PublicKey,
            userTransferAuthority: SolanaSDK.PublicKey,
            userSourceTokenAccount: SolanaSDK.PublicKey,
            userDestinationTokenAccount: SolanaSDK.PublicKey,
            transitTokenMint: SolanaSDK.PublicKey,
            swapFromProgramId: SolanaSDK.PublicKey,
            swapFromAccount: SolanaSDK.PublicKey,
            swapFromAuthority: SolanaSDK.PublicKey,
            swapFromSource: SolanaSDK.PublicKey,
            swapFromDestination: SolanaSDK.PublicKey,
            swapFromPoolTokenMint: SolanaSDK.PublicKey,
            swapFromPoolFeeAccount: SolanaSDK.PublicKey,
            swapToProgramId: SolanaSDK.PublicKey,
            swapToAccount: SolanaSDK.PublicKey,
            swapToAuthority: SolanaSDK.PublicKey,
            swapToSource: SolanaSDK.PublicKey,
            swapToDestination: SolanaSDK.PublicKey,
            swapToPoolTokenMint: SolanaSDK.PublicKey,
            swapToPoolFeeAccount: SolanaSDK.PublicKey,
            amountIn: UInt64,
            transitMinimumAmount: UInt64,
            minimumAmountOut: UInt64,
            network: SolanaSDK.Network
        ) throws -> SolanaSDK.TransactionInstruction {
            .init(
                keys: [
                    .readonly(publicKey: .wrappedSOLMint, isSigner: false),
                    .writable(publicKey: feePayer, isSigner: true),
                    .readonly(publicKey: userAuthority, isSigner: true),
                    .writable(publicKey: userRelayAccount, isSigner: false),
                    .readonly(publicKey: .tokenProgramId, isSigner: false),
                    .readonly(publicKey: userTransferAuthority, isSigner: true),
                    .writable(publicKey: userSourceTokenAccount, isSigner: false),
                    .writable(publicKey: try getTransitTokenAccountAddress(user: userAuthority, transitTokenMint: transitTokenMint, network: network), isSigner: false),
                    .writable(publicKey: userDestinationTokenAccount, isSigner: false),
                    .readonly(publicKey: swapFromProgramId, isSigner: false),
                    .readonly(publicKey: swapFromAccount, isSigner: false),
                    .readonly(publicKey: swapFromAuthority, isSigner: false),
                    .writable(publicKey: swapFromSource, isSigner: false),
                    .writable(publicKey: swapFromDestination, isSigner: false),
                    .writable(publicKey: swapFromPoolTokenMint, isSigner: false),
                    .writable(publicKey: swapFromPoolFeeAccount, isSigner: false),
                    .readonly(publicKey: swapToProgramId, isSigner: false),
                    .readonly(publicKey: swapToAccount, isSigner: false),
                    .readonly(publicKey: swapToAuthority, isSigner: false),
                    .writable(publicKey: swapToSource, isSigner: false),
                    .writable(publicKey: swapToDestination, isSigner: false),
                    .writable(publicKey: swapToPoolTokenMint, isSigner: false),
                    .writable(publicKey: swapToPoolFeeAccount, isSigner: false),
                    .readonly(publicKey: .sysvarRent, isSigner: false),
                    .readonly(publicKey: .programId, isSigner: false)
                ],
                programId: id(network: network),
                data: [
                    UInt8(1),
                    amountIn,
                    transitMinimumAmount,
                    minimumAmountOut
                ]
            )
        }
        
        private static func splSwapTransitiveInstruction(
            feePayer: SolanaSDK.PublicKey,
            userAuthority: SolanaSDK.PublicKey,
            userTransferAuthority: SolanaSDK.PublicKey,
            userSourceTokenAccount: SolanaSDK.PublicKey,
            userTransitTokenAccount: SolanaSDK.PublicKey,
            userDestinationTokenAccount: SolanaSDK.PublicKey,
            transitTokenMint: SolanaSDK.PublicKey,
            swapFromProgramId: SolanaSDK.PublicKey,
            swapFromAccount: SolanaSDK.PublicKey,
            swapFromAuthority: SolanaSDK.PublicKey,
            swapFromSource: SolanaSDK.PublicKey,
            swapFromDestination: SolanaSDK.PublicKey,
            swapFromPoolTokenMint: SolanaSDK.PublicKey,
            swapFromPoolFeeAccount: SolanaSDK.PublicKey,
            swapToProgramId: SolanaSDK.PublicKey,
            swapToAccount: SolanaSDK.PublicKey,
            swapToAuthority: SolanaSDK.PublicKey,
            swapToSource: SolanaSDK.PublicKey,
            swapToDestination: SolanaSDK.PublicKey,
            swapToPoolTokenMint: SolanaSDK.PublicKey,
            swapToPoolFeeAccount: SolanaSDK.PublicKey,
            amountIn: UInt64,
            transitMinimumAmount: UInt64,
            minimumAmountOut: UInt64,
            network: SolanaSDK.Network
        ) throws -> SolanaSDK.TransactionInstruction {
            .init(
                keys: [
                    .writable(publicKey: feePayer, isSigner: true),
                    .readonly(publicKey: .tokenProgramId, isSigner: false),
                    .readonly(publicKey: userTransferAuthority, isSigner: true),
                    .writable(publicKey: userSourceTokenAccount, isSigner: false),
                    .writable(publicKey: userTransitTokenAccount, isSigner: false),
                    .writable(publicKey: userDestinationTokenAccount, isSigner: false),
                    .readonly(publicKey: swapFromProgramId, isSigner: false),
                    .readonly(publicKey: swapFromAccount, isSigner: false),
                    .readonly(publicKey: swapFromAuthority, isSigner: false),
                    .writable(publicKey: swapFromSource, isSigner: false),
                    .writable(publicKey: swapFromDestination, isSigner: false),
                    .writable(publicKey: swapFromPoolTokenMint, isSigner: false),
                    .writable(publicKey: swapFromPoolFeeAccount, isSigner: false),
                    .readonly(publicKey: swapToProgramId, isSigner: false),
                    .readonly(publicKey: swapToAccount, isSigner: false),
                    .readonly(publicKey: swapToAuthority, isSigner: false),
                    .writable(publicKey: swapToSource, isSigner: false),
                    .writable(publicKey: swapToDestination, isSigner: false),
                    .writable(publicKey: swapToPoolTokenMint, isSigner: false),
                    .writable(publicKey: swapToPoolFeeAccount, isSigner: false),
                ],
                programId: Program.id(network: network),
                data: [
                    UInt8(4),
                    amountIn,
                    transitMinimumAmount,
                    minimumAmountOut
                ]
            )
        }
    }
}
