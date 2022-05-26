// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension SwapTransactionBuilder {
    static internal func checkClosingAccount(_ context: inout BuildContext) throws {
            if let newAccount = context.env.sourceWSOLNewAccount {
            context.env.instructions.append(contentsOf: [
                TokenProgram.closeAccountInstruction(
                    account: newAccount.publicKey,
                    destination: try context.config.userAuthorityAddress,
                    owner: try context.config.userAuthorityAddress
                )
            ])
        }
        // close destination
        if let newAccount = context.env.destinationNewAccount, context.config.destinationAccount.mint == .wrappedSOLMint {
            context.env.instructions.append(contentsOf: [
                TokenProgram.closeAccountInstruction(
                    account: newAccount.publicKey,
                    destination: try context.config.userAuthorityAddress,
                    owner: try context.config.userAuthorityAddress
                ),
                SystemProgram.transferInstruction(
                    from: try context.config.userAuthorityAddress,
                    to: context.feeRelayerContext.feePayerAddress,
                    lamports: context.feeRelayerContext.minimumTokenAccountBalance
                )
            ])
            context.env.accountCreationFee -= context.feeRelayerContext.minimumTokenAccountBalance
        }
    }
}