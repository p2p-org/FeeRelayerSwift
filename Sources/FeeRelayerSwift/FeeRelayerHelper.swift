// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

actor FeeRelayHelper {
    private let cache: Cache<CacheKey, Any>
    private let accountStorage: SolanaAccountStorage
    private let feeRelayerAPIClient: FeeRelayerAPIClient
    private let solanaApiClient: SolanaAPIClient

    init(
        cache: Cache<CacheKey, Any>,
        accountStorage: SolanaAccountStorage,
        feeRelayerAPIClient: FeeRelayerAPIClient,
        solanaApiClient: SolanaAPIClient
    ) {
        self.cache = cache
        self.accountStorage = accountStorage
        self.feeRelayerAPIClient = feeRelayerAPIClient
        self.solanaApiClient = solanaApiClient
    }
    
    // Clear critical key
    func clear() async throws {
        await cache.removeValue(forKey: .usageStatus)
        await cache.removeValue(forKey: .relayAccountStatus)
    }
    
    /// Preload all cache values
    func warmUp() async throws {
        await withThrowingTaskGroup(of: Any.self) { group in
            group.addTask { try await self.getRelayAccountStatus() }
            group.addTask { try await self.getUsageStatus() }
            group.addTask { try await self.getMinimumBalanceForRentExemption() }
            group.addTask { try await self.getMinimumRelayAccountBalance() }
            group.addTask { try await self.getFeePayerPubkey() }
        }
    }

    internal func read<T>(key: CacheKey, fetch: () async throws -> T) async throws -> T {
        if let cachedValue = await cache[key] as? T { return cachedValue }

        let fetchedValue = try await fetch()
        await cache.insert(fetchedValue, forKey: key)
        return fetchedValue
    }

    internal func getRelayAccountStatus() async throws -> RelayAccountStatus {
        try await read(key: .relayAccountStatus) {
            try await solanaApiClient
                .getRelayAccountStatus(try accountStorage.pubkey.base58EncodedString)
        }
    }

    internal func getUsageStatus() async throws -> UsageStatus {
        try await read(key: .usageStatus) {
            let response = try await feeRelayerAPIClient
                .requestFreeFeeLimits(for: accountStorage.pubkey.base58EncodedString)
            return UsageStatus(
                maxUsage: response.limits.maxCount,
                currentUsage: response.processedFee.count,
                maxAmount: response.limits.maxAmount,
                amountUsed: response.processedFee.totalAmount
            )
        }
    }

    internal func getMinimumBalanceForRentExemption() async throws -> UInt64 {
        try await read(key: .minimumTokenAccountBalance) {
            try await solanaApiClient.getMinimumBalanceForRentExemption(span: 165)
        }
    }

    internal func getMinimumRelayAccountBalance() async throws -> UInt64 {
        try await read(key: .minimumRelayAccountBalance) {
            try await solanaApiClient.getMinimumBalanceForRentExemption(span: 0)
        }
    }

    internal func getFeePayerPubkey() async throws -> PublicKey {
        try await read(key: .feePayerAddress) {
            let address = try await feeRelayerAPIClient.getFeePayerPubkey()
            return try PublicKey(string: address)
        }
    }

    internal func getLamportsPerSignature() async throws -> UInt64 {
        try await read(key: .lamportsPerSignature) {
            let fee = try await solanaApiClient.getFees(commitment: nil)
            return fee.feeCalculator?.lamportsPerSignature ?? 0
        }
    }
}
