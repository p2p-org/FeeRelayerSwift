// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

public actor RelayContextManagerImpl: RelayContextManager {
    private let accountStorage: SolanaAccountStorage
    private let solanaAPIClient: SolanaAPIClient
    private let feeRelayerAPIClient: FeeRelayerAPIClient
    
    private var context: RelayContext?
    
    public init(
        accountStorage: SolanaAccountStorage,
        solanaAPIClient: SolanaAPIClient,
        feeRelayerAPIClient: FeeRelayerAPIClient
    ) {
        self.accountStorage = accountStorage
        self.solanaAPIClient = solanaAPIClient
        self.feeRelayerAPIClient = feeRelayerAPIClient
    }
    
    public func getCurrentContext() async throws -> RelayContext {
        if context == nil { try await update() }
        guard let context = context else { throw RelayContextManagerError.invalidContext }
        return context;
    }
    
    public func update() async throws {
        context = try await loadNewContext()
    }
    
    public func validate() async throws -> Bool {
        let newContext = try await loadNewContext()
        return newContext == context
    }
    
    private func loadNewContext() async throws -> RelayContext {
        guard let account = accountStorage.account else { throw FeeRelayerError.unauthorized }
        
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
            solanaAPIClient.getRelayAccountStatus(
                try RelayProgram.getUserRelayAddress(user: account.publicKey, network: solanaAPIClient.endpoint.network)
                    .base58EncodedString
            ),
            feeRelayerAPIClient.getFreeFeeLimits(for: account.publicKey.base58EncodedString)
                .asUsageStatus()
        )

        return RelayContext(
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
