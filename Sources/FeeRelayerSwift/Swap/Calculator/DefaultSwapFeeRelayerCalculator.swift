// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

class DefaultSwapFeeRelayerCalculator: SwapFeeRelayerCalculator {
    let solanaApiClient: SolanaAPIClient
    let userAccount: Account

    init(solanaApiClient: SolanaAPIClient, userAccount: Account) {
        self.solanaApiClient = solanaApiClient
        self.userAccount = userAccount
    }

    func calculateSwappingNetworkFees(
        _ context: FeeRelayerContext,
        swapPools: PoolsPair?,
        sourceTokenMint: PublicKey,
        destinationTokenMint: PublicKey,
        destinationAddress: PublicKey?
    ) async throws -> FeeAmount {
        let destinationInfo = try await DestinationAnalysator.analyseDestination(
            solanaApiClient,
            destination: destinationAddress,
            mint: destinationTokenMint,
            userAccount: userAccount
        )
        let lamportsPerSignature = context.lamportsPerSignature
        let minimumTokenAccountBalance = context.minimumTokenAccountBalance

        var expectedFee = FeeAmount.zero

        // fee for payer's signature
        expectedFee.transaction += lamportsPerSignature

        expectedFee.transaction += lamportsPerSignature

        // when source token is native SOL
        if sourceTokenMint == PublicKey.wrappedSOLMint {
            expectedFee.transaction += lamportsPerSignature
        }

        // when needed to create destination
        if destinationInfo.needCreateDestination, destinationTokenMint != PublicKey.wrappedSOLMint {
            expectedFee.accountBalances += minimumTokenAccountBalance
        }

        // when destination is native SOL
        if destinationTokenMint == PublicKey.wrappedSOLMint {
            expectedFee.transaction += lamportsPerSignature
        }

        // in transitive swap, there will be situation when swapping from SOL -> SPL that needs spliting transaction to 2 transactions
        if swapPools?.count == 2, sourceTokenMint == PublicKey.wrappedSOLMint, destinationAddress == nil {
            expectedFee.transaction += lamportsPerSignature * 2
        }

        return expectedFee
    }
}
