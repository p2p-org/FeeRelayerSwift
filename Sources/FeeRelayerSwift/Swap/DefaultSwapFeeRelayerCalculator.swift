// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

class DefaultSwapFeeRelayerCalculator: SwapFeeRelayerCalculator {
    let solanaApiClient: SolanaAPIClient
    let accountStorage: SolanaAccountStorage
    let helper: FeeRelayHelper

    init(solanaApiClient: SolanaAPIClient, accountStorage: SolanaAccountStorage, helper: FeeRelayHelper) {
        self.solanaApiClient = solanaApiClient
        self.accountStorage = accountStorage
        self.helper = helper
    }

    func calculateSwappingNetworkFees(
        swapPools: PoolsPair?,
        sourceTokenMint: PublicKey,
        destinationTokenMint: PublicKey,
        destinationAddress: PublicKey?
    ) async throws -> FeeAmount {
        let destinationInfo = try await analyseDestination(destinationAddress, mint: destinationTokenMint)
        let lamportsPerSignature = try await helper.getLamportsPerSignature()
        let minimumTokenAccountBalance = try await helper.getMinimumBalanceForRentExemption()

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

    internal func analyseDestination(
        _ destination: PublicKey?,
        mint: PublicKey
    ) async throws -> (destination: TokenAccount, destinationOwner: PublicKey?, needCreateDestination: Bool) {
        let owner = try accountStorage.pubkey

        if PublicKey.wrappedSOLMint == mint {
            // Target is SOL Token
            return (
                destination: TokenAccount(address: owner, mint: mint),
                destinationOwner: owner,
                needCreateDestination: true
            )
        } else {
            // Target is SPL Token
            if let destination = destination {
                // User already has SPL account
                return (
                    destination: TokenAccount(address: destination, mint: mint),
                    destinationOwner: owner,
                    needCreateDestination: false
                )
            } else {
                // User doesn't have SPL account

                // Try to get associated account
                let address = try await solanaApiClient.getAssociatedSPLTokenAddress(for: owner, mint: mint)

                // Check destination address is exist.
                let info: BufferInfo<AccountInfo>? = try await solanaApiClient
                    .getAccountInfo(account: address.base58EncodedString)
                let needsCreateDestinationTokenAccount = info?.owner == TokenProgram.id.base58EncodedString

                return (
                    destination: TokenAccount(address: owner, mint: mint),
                    destinationOwner: nil,
                    needCreateDestination: needsCreateDestinationTokenAccount
                )
            }
        }
    }
}
