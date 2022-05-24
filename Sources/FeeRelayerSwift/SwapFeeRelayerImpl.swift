// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

class SwapFeeRelayerImpl: SwapFeeRelayer {
    let feeRelayer: FeeRelayer

    init(feeRelayer: FeeRelayer) { self.feeRelayer = feeRelayer }

    func calculateSwappingNetworkFees(
        swapPools _: PoolsPair?,
        sourceTokenMint _: String,
        destinationTokenMint _: String,
        destinationAddress _: String?
    ) async throws -> FeeAmount {}

    func prepareSwapTransaction(
        sourceToken _: Token,
        destinationTokenMint _: String,
        destinationAddress _: String?,
        fee _: Token,
        swapPools _: OrcaSwapSwift.PoolsPair,
        inputAmount _: UInt64,
        slippage _: Double
    ) async throws
    -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
        fatalError(
            "prepareSwapTransaction(sourceToken:destinationTokenMint:destinationAddress:fee:swapPools:inputAmount:slippage:) has not been implemented"
        )
    }

    private func getDestination(
        destinationAddress: String?,
        destinationTokenMint: String
    ) async throws
        -> (destinationToken: Token, userDestinationAccountOwnerAddress: PublicKey?,
            needsCreateDestinationTokenAccount: Bool)
    {
        let account = try feeRelayer.account

        if PublicKey.wrappedSOLMint == destinationTokenMint {
            // Target is SOL Token
            return (
                destinationToken: Token(address: account.publicKey, mint: destinationTokenMint),
                userDestinationAccountOwnerAddress: account.publicKey,
                needsCreateDestinationTokenAccount: true
            )
        } else {
            // Target is SPL Token
            if let destinationAddress = try? PublicKey(string: destinationAddress) {
                // User already has SPL account
                return (
                    destinationToken: Token(address: destinationAddress, mint: destinationTokenMint),
                    userDestinationAccountOwnerAddress: account.publicKey,
                    needsCreateDestinationTokenAccount: false
                )
            } else {
                // User doesn't have SPL account
                return (
                    destinationToken: Token(address: account.publicKey, mint: destinationTokenMint),
                    userDestinationAccountOwnerAddress: account.publicKey,
                    needsCreateDestinationTokenAccount: true
                )
            }
        }
    }
    
    private func getAssociatedTokenAddress(for address: PublicKey, with mintAddress: PublicKey) {
        let accountInfo = feeRelayer.apiClient.getAccountInfo()
    }
}
