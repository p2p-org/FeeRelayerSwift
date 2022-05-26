//// Copyright 2022 P2P Validator Authors. All rights reserved.
//// Use of this source code is governed by a MIT-style license that can be
//// found in the LICENSE file.
//
//import Foundation
//import OrcaSwapSwift
//import SolanaSwift
//
//internal enum SwapTransactionBuilder {
//    internal static func prepareSwapTransaction(
//        accountStorage: SolanaAccountStorage,
//        network _: Network,
//        sourceToken: TokenAccount,
//        destinationToken _: TokenAccount,
//        userDestinationAccountOwnerAddress _: PublicKey?,
//
//        pools _: PoolsPair,
//        inputAmount _: UInt64,
//        slippage _: Double,
//
//        feeAmount _: UInt64,
//        blockhash _: String,
//        minimumTokenAccountBalance _: UInt64,
//        needsCreateDestinationTokenAccount _: Bool,
//        feePayerAddress: PublicKey,
//        lamportsPerSignature _: UInt64,
//
//        needsCreateTransitTokenAccount _: Bool?,
//        transitTokenMintPubkey _: PublicKey?,
//        transitTokenAccountAddress _: PublicKey?
//    ) throws -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
//        let userAuthorityAddress = try accountStorage.pubkey
//        let associatedToken = try PublicKey.associatedTokenAddress(
//            walletAddress: feePayerAddress,
//            tokenMintAddress: sourceToken.mint
//        )
//
//        var additionalTransaction: PreparedTransaction?
//        var accountCreationFee: Lamports = 0
//        var instructions = [TransactionInstruction]()
//        var additionalPaybackFee: UInt64 = 0
//
//        var sourceWSOLNewAccount: Account?
//        if sourceToken.mint == PublicKey.wrappedSOLMint {
//            sourceWSOLNewAccount = try Account(network: network)
//            instructions.append(contentsOf: [
//                SolanaSDK.SystemProgram.transferInstruction(
//                    from: userAuthorityAddress,
//                    to: feePayerAddress,
//                    lamports: inputAmount
//                ),
//                SolanaSDK.SystemProgram.createAccountInstruction(
//                    from: feePayerAddress,
//                    toNewPubkey: sourceWSOLNewAccount!.publicKey,
//                    lamports: minimumTokenAccountBalance + inputAmount
//                ),
//                SolanaSDK.TokenProgram.initializeAccountInstruction(
//                    account: sourceWSOLNewAccount!.publicKey,
//                    mint: .wrappedSOLMint,
//                    owner: userAuthorityAddress
//                ),
//            ])
//            userSourceTokenAccountAddress = sourceWSOLNewAccount!.publicKey
//            additionalPaybackFee += minimumTokenAccountBalance
//        }
//    }
//}
