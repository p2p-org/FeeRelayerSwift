// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

public class DefaultSwapFeeRelayerCalculator: SwapFeeRelayerCalculator {
    let solanaApiClient: SolanaAPIClient
    let accountStorage: SolanaAccountStorage
    
    var userAccount: Account { accountStorage.account! }

    public init(solanaApiClient: SolanaAPIClient, accountStorage: SolanaAccountStorage) {
        self.solanaApiClient = solanaApiClient
        self.accountStorage = accountStorage
    }
    
    public func calculateSwappingNetworkFees(
        _ context: RelayContext,
        swapPools: PoolsPair?,
        sourceTokenMint: PublicKey,
        destinationTokenMint: PublicKey,
        destinationAddress: PublicKey?
    ) async throws -> FeeAmount {
        let destinationFinder = DestinationFinderImpl(solanaAPIClient: solanaApiClient)
        let destinationInfo = try await destinationFinder.findRealDestination(
            owner: userAccount.publicKey,
            mint: destinationTokenMint,
            givenDestination: destinationAddress
        )
        let lamportsPerSignature = context.lamportsPerSignature
        let minimumTokenAccountBalance = context.minimumTokenAccountBalance

        var expectedFee = FeeAmount.zero

        // fee for payer's signature
        expectedFee.transaction += lamportsPerSignature

        // fee for owner's signature
        expectedFee.transaction += lamportsPerSignature

        // when source token is native SOL
        if sourceTokenMint == PublicKey.wrappedSOLMint {
            expectedFee.transaction += lamportsPerSignature
        }

        // when needed to create destination
        if destinationInfo.needsCreation, destinationTokenMint != PublicKey.wrappedSOLMint {
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
