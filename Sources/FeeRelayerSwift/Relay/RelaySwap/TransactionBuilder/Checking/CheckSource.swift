// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension SwapTransactionBuilder {
    internal static func checkSource(
        owner: PublicKey,
        sourceMint: PublicKey,
        inputAmount: UInt64,
        network: SolanaSwift.Network,
        feePayer: PublicKey,
        minimumTokenAccountBalance: UInt64,
        env: inout BuildContext.Environment
    ) async throws {
        var sourceWSOLNewAccount: Account?
        
        // Check if source token is NATIVE SOL
        // Treat SPL SOL like another SPL Token (WSOL new account is not needed)
        
        if sourceMint == PublicKey.wrappedSOLMint &&
           (env.userSource == nil || env.userSource == owner) // check for native sol
        {
            sourceWSOLNewAccount = try await Account(network: network)
            env.instructions.append(contentsOf: [
                SystemProgram.transferInstruction(
                    from: owner,
                    to: feePayer,
                    lamports: inputAmount
                ),
                SystemProgram.createAccountInstruction(
                    from: feePayer,
                    toNewPubkey: sourceWSOLNewAccount!.publicKey,
                    lamports: minimumTokenAccountBalance + inputAmount,
                    space: AccountInfo.BUFFER_LENGTH,
                    programId: TokenProgram.id
                ),
                TokenProgram.initializeAccountInstruction(
                    account: sourceWSOLNewAccount!.publicKey,
                    mint: .wrappedSOLMint,
                    owner: owner
                ),
            ])
            env.userSource = sourceWSOLNewAccount!.publicKey
            env.additionalPaybackFee += minimumTokenAccountBalance
        }
        
        env.sourceWSOLNewAccount = sourceWSOLNewAccount
    }
}
