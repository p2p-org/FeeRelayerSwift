// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

class DestinationAnalysator {
    static internal func analyseDestination(
        _ apiClient: SolanaAPIClient,
        destination: PublicKey?,
        mint: PublicKey,
        userAccount: Account
    ) async throws -> (destination: TokenAccount, destinationOwner: PublicKey?, needCreateDestination: Bool) {
        if PublicKey.wrappedSOLMint == mint {
            // Target is SOL Token
            return (
                destination: TokenAccount(address: userAccount.publicKey, mint: mint),
                destinationOwner: userAccount.publicKey,
                needCreateDestination: true
            )
        } else {
            // Target is SPL Token
            if let destination = destination {
                // User already has SPL account
                return (
                    destination: TokenAccount(address: destination, mint: mint),
                    destinationOwner: userAccount.publicKey,
                    needCreateDestination: false
                )
            } else {
                // User doesn't have SPL account

                // Try to get associated account
                let address = try await apiClient.getAssociatedSPLTokenAddress(for: userAccount.publicKey, mint: mint)

                // Check destination address is exist.
                let info: BufferInfo<AccountInfo>? = try? await apiClient
                    .getAccountInfo(account: address.base58EncodedString)
                let needsCreateDestinationTokenAccount = info?.owner != TokenProgram.id.base58EncodedString

                return (
                    destination: TokenAccount(address: userAccount.publicKey, mint: mint),
                    destinationOwner: nil,
                    needCreateDestination: needsCreateDestinationTokenAccount
                )
            }
        }
    }
}
