// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

/// Destination finding service
protocol DestinationFinder {
    /// User may give SOL address or SPL token address as destination,
    /// so this method will check and give the correct destination
    /// that map user's address and mint address of the token.
    /// - Parameters:
    ///   - owner: account's owner
    ///   - mint: token mint
    ///   - givenDestination: (Optional) given destination by user
    /// - Returns:
    func findRealDestination(
        owner: PublicKey,
        mint: PublicKey,
        givenDestination: PublicKey?
    ) async throws -> (destination: TokenAccount, destinationOwner: PublicKey?, needCreateDestination: Bool)
}

class DestinationFinderImpl: DestinationFinder {
    private let solanaAPIClient: SolanaAPIClient
    
    init(solanaAPIClient: SolanaAPIClient) {
        self.solanaAPIClient = solanaAPIClient
    }
    
    func findRealDestination(
        owner: PublicKey,
        mint: PublicKey,
        givenDestination: PublicKey?
    ) async throws -> (destination: TokenAccount, destinationOwner: PublicKey?, needCreateDestination: Bool) {
        if PublicKey.wrappedSOLMint == mint {
            // Target is SOL Token
            return (
                destination: TokenAccount(address: owner, mint: mint),
                destinationOwner: owner,
                needCreateDestination: true
            )
        } else {
            // Target is SPL Token
            if let givenDestination = givenDestination {
                // User already has SPL account
                return (
                    destination: TokenAccount(address: givenDestination, mint: mint),
                    destinationOwner: owner,
                    needCreateDestination: false
                )
            } else {
                // User doesn't have SPL account

                // Try to get associated account
                let address = try await solanaAPIClient.getAssociatedSPLTokenAddress(for: owner, mint: mint)

                // Check destination address is exist.
                let info: BufferInfo<AccountInfo>? = try? await solanaAPIClient
                    .getAccountInfo(account: address.base58EncodedString)
                let needsCreateDestinationTokenAccount = info?.owner != TokenProgram.id.base58EncodedString

                return (
                    destination: TokenAccount(address: owner, mint: mint),
                    destinationOwner: nil,
                    needCreateDestination: needsCreateDestinationTokenAccount
                )
            }
        }
    }
}
