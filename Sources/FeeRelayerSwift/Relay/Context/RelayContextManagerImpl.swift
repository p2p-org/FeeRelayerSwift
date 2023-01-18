// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import Combine
import SolanaSwift


/// Default implementation for RelayContextManager
public class RelayContextManagerImpl: RelayContextManager {
    
    // MARK: - Dependencies

    /// Solana account storage
    private let accountStorage: SolanaAccountStorage
    
    /// Solana APIClient
    private let solanaAPIClient: SolanaAPIClient
    
    /// FeeRelayerAPIClient
    private let feeRelayerAPIClient: FeeRelayerAPIClient
    
    // MARK: - Properties

    /// Subject to handle context data flow
    private let contextSubject = CurrentValueSubject<RelayContext?, Never>(nil)
    
    /// Current RelayContext
    public var currentContext: RelayContext? { contextSubject.value }
    
    /// Publisher for current RelayContext
    public var contextPublisher: AnyPublisher<RelayContext?, Never> { contextSubject.eraseToAnyPublisher() }
    
    /// Updating task
    private var updatingTask: Task<RelayContext, Error>?

    // MARK: - Initializer

    init(
        accountStorage: SolanaAccountStorage,
        solanaAPIClient: SolanaAPIClient,
        feeRelayerAPIClient: FeeRelayerAPIClient
    ) {
        self.accountStorage = accountStorage
        self.solanaAPIClient = solanaAPIClient
        self.feeRelayerAPIClient = feeRelayerAPIClient
    }

    // MARK: - Methods

    /// Update current context
    public func update() async throws {
        // cancel current task
        updatingTask?.cancel()
        
        // assign task
        updatingTask = Task { [weak self] () -> RelayContext in
            // assertion
            guard let self, let account = self.accountStorage.account
            else { throw RelayContextManagerError.invalidContext }
            
            // retrieve RelayContext
            let (
                minimumTokenAccountBalance,
                minimumRelayAccountBalance,
                lamportsPerSignature,
                feePayerAddress,
                relayAccountStatus,
                usageStatus
            ) = try await(
                self.solanaAPIClient.getMinimumBalanceForRentExemption(span: 165),
                self.solanaAPIClient.getMinimumBalanceForRentExemption(span: 0),
                self.solanaAPIClient.getFees(commitment: nil).feeCalculator?.lamportsPerSignature ?? 0,
                self.feeRelayerAPIClient.getFeePayerPubkey(),
                self.solanaAPIClient.getRelayAccountStatus(
                    try RelayProgram.getUserRelayAddress(user: account.publicKey, network: solanaAPIClient.endpoint.network)
                        .base58EncodedString
                ),
                self.feeRelayerAPIClient.getFreeFeeLimits(for: account.publicKey.base58EncodedString)
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
        
        // execute task
        guard let result = try await updatingTask?.value else {
            throw RelayContextManagerError.invalidContext
        }

        // mark as completed
        contextSubject.send(result)
    }

    /// Modify context locally
    public func replaceContext(by context: RelayContext) {
        self.contextSubject.send(context)
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
