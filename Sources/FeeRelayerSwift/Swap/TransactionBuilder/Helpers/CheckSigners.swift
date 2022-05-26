// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

extension SwapTransactionBuilder {
    static func checkSigners(context: inout BuildContext) throws {
        context.signers.append(try context.accountStorage.signer)
        if let sourceWSOLNewAccount = context.sourceWSOLNewAccount { context.signers.append(sourceWSOLNewAccount) }
        if let destinationNewAccount = context.destinationNewAccount { context.signers.append(destinationNewAccount) }
    }
}