// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

public struct FeeRelayerContext {
    public var minimumTokenAccountBalance: UInt64
    public var minimumRelayAccountBalance: UInt64
    public var feePayerAddress: PublicKey
    public var lamportsPerSignature: UInt64
    public var relayAccountStatus: RelayAccountStatus
    public var usageStatus: UsageStatus

    static func create(
        userAccount: Account,
        solanaAPIClient: SolanaAPIClient,
        feeRelayerAPIClient: FeeRelayerAPIClient
    ) async throws -> FeeRelayerContext {
        let (
            minimumTokenAccountBalance,
            minimumRelayAccountBalance,
            lamportsPerSignature,
            feePayerAddress,
            relayAccountStatus,
            usageStatus
        ) = try await(
            solanaAPIClient.getMinimumBalanceForRentExemption(span: 165),
            solanaAPIClient.getMinimumBalanceForRentExemption(span: 0),
            solanaAPIClient.getFees(commitment: nil).feeCalculator?.lamportsPerSignature ?? 0,
            feeRelayerAPIClient.getFeePayerPubkey(),
            solanaAPIClient.getRelayAccountStatus(userAccount.publicKey.base58EncodedString),
            feeRelayerAPIClient.requestFreeFeeLimits(for: userAccount.publicKey.base58EncodedString)
                .asUsageStatus()
        )

        return .init(
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            minimumRelayAccountBalance: minimumRelayAccountBalance,
            feePayerAddress: try PublicKey(string: feePayerAddress),
            lamportsPerSignature: lamportsPerSignature,
            relayAccountStatus: relayAccountStatus,
            usageStatus: usageStatus
        )
    }
}

internal extension FeeLimitForAuthorityResponse {
    func asUsageStatus() -> UsageStatus {
        UsageStatus(
            maxUsage: limits.maxCount,
            currentUsage: processedFee.count,
            maxAmount: limits.maxAmount,
            amountUsed: processedFee.totalAmount
        )
    }
}
