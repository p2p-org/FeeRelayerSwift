// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension SwapTransactionBuilder {
    internal static func checkSource(_ context: inout BuildContext) async throws {
        var sourceWSOLNewAccount: Account?
        if context.config.sourceAccount.mint == PublicKey.wrappedSOLMint {
            sourceWSOLNewAccount = try await Account(network: context.solanaApiClient.endpoint.network)
            context.env.instructions.append(contentsOf: [
                SystemProgram.transferInstruction(
                    from: context.config.userAccount.publicKey,
                    to: context.feeRelayerContext.feePayerAddress,
                    lamports: context.config.inputAmount
                ),
                SystemProgram.createAccountInstruction(
                    from: context.feeRelayerContext.feePayerAddress,
                    toNewPubkey: sourceWSOLNewAccount!.publicKey,
                    lamports: context.feeRelayerContext.minimumTokenAccountBalance + context.config.inputAmount,
                    space: AccountInfo.BUFFER_LENGTH,
                    programId: TokenProgram.id
                ),
                TokenProgram.initializeAccountInstruction(
                    account: sourceWSOLNewAccount!.publicKey,
                    mint: .wrappedSOLMint,
                    owner: context.config.userAccount.publicKey
                ),
            ])
            context.env.userSource = sourceWSOLNewAccount!.publicKey
        }
        
        context.env.sourceWSOLNewAccount = sourceWSOLNewAccount
    }
}