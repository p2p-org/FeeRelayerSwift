// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

public class DefaultSwapFeeRelayerCalculator: SwapFeeRelayerCalculator {
    let destinationFinder: DestinationFinder
    let accountStorage: SolanaAccountStorage
    
    var userAccount: Account { accountStorage.account! }

    public init(destinationFinder: DestinationFinder, accountStorage: SolanaAccountStorage) {
        self.destinationFinder = destinationFinder
        self.accountStorage = accountStorage
    }
    
    public func calculateSwappingNetworkFees(
        lamportsPerSignature: UInt64,
        minimumTokenAccountBalance: UInt64,
        swapPoolsCount: Int,
        sourceTokenMint: PublicKey,
        destinationTokenMint: PublicKey,
        destinationAddress: PublicKey?
    ) async throws -> FeeAmount {
        let destinationInfo = try await destinationFinder.findRealDestination(
            owner: userAccount.publicKey,
            mint: destinationTokenMint,
            givenDestination: destinationAddress
        )

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
        if swapPoolsCount == 2, sourceTokenMint == PublicKey.wrappedSOLMint, destinationAddress == nil {
            expectedFee.transaction += lamportsPerSignature * 2
        }

        return expectedFee
    }
}
