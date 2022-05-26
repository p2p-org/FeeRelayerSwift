// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift
import OrcaSwapSwift

extension SwapTransactionBuilder {
    static internal func checkClosingAccount(_ context: inout BuildContext) throws {
            if let newAccount = context.sourceWSOLNewAccount {
            context.instructions.append(contentsOf: [
                TokenProgram.closeAccountInstruction(
                    account: newAccount.publicKey,
                    destination: try context.userAuthorityAddress,
                    owner: try context.userAuthorityAddress
                )
            ])
        }
        // close destination
        if let newAccount = context.destinationNewAccount, context.destinationToken.mint == .wrappedSOLMint {
            context.instructions.append(contentsOf: [
                TokenProgram.closeAccountInstruction(
                    account: newAccount.publicKey,
                    destination: try context.userAuthorityAddress,
                    owner: try context.userAuthorityAddress
                ),
                SystemProgram.transferInstruction(
                    from: try context.userAuthorityAddress,
                    to: context.feeRelayerContext.feePayerAddress,
                    lamports: context.feeRelayerContext.minimumTokenAccountBalance
                )
            ])
            context.accountCreationFee -= context.feeRelayerContext.minimumTokenAccountBalance
        }
    }
}