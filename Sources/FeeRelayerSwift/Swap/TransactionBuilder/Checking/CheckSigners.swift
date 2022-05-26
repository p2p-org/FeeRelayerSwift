// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

extension SwapTransactionBuilder {
    static func checkSigners(_ context: inout BuildContext) throws {
        context.env.signers.append(try context.config.accountStorage.signer)
        if let sourceWSOLNewAccount = context.env.sourceWSOLNewAccount { context.env.signers.append(sourceWSOLNewAccount) }
        if let destinationNewAccount = context.env.destinationNewAccount { context.env.signers.append(destinationNewAccount) }
    }
}