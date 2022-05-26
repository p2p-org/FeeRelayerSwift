// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension SwapTransactionBuilder {
    internal static func checkSource(_ context: inout BuildContext) async throws {
        var sourceWSOLNewAccount: Account?
        if context.sourceToken.mint == PublicKey.wrappedSOLMint {
            sourceWSOLNewAccount = try await Account(network: context.network)
            context.instructions.append(contentsOf: [
                SystemProgram.transferInstruction(
                    from: try context.accountStorage.pubkey,
                    to: context.feeRelayerContext.feePayerAddress,
                    lamports: context.inputAmount
                ),
                SystemProgram.createAccountInstruction(
                    from: context.feeRelayerContext.feePayerAddress,
                    toNewPubkey: sourceWSOLNewAccount!.publicKey,
                    lamports: context.feeRelayerContext.minimumTokenAccountBalance + context.inputAmount,
                    space: AccountInfo.BUFFER_LENGTH,
                    programId: TokenProgram.id
                ),
                TokenProgram.initializeAccountInstruction(
                    account: sourceWSOLNewAccount!.publicKey,
                    mint: .wrappedSOLMint,
                    owner: try context.userAuthorityAddress
                ),
            ])
            context.userSource = sourceWSOLNewAccount!.publicKey
            context.additionalPaybackFee += context.feeRelayerContext.minimumTokenAccountBalance
        }
        
        context.sourceWSOLNewAccount = sourceWSOLNewAccount
    }
}