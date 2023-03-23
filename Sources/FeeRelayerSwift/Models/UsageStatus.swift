// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation

/// A user's usage status for fee relayer service.
public struct UsageStatus: Equatable {
    public let maxUsage: Int
    public var currentUsage: Int
    public let maxAmount: UInt64
    public var amountUsed: UInt64
    public let maxTokenAccountCreationAmount: UInt64
    public let maxTokenAccountCreationCount: Int
    public let tokenAccountCreationAmountUsed: UInt64
    public let tokenAccountCreationCountUsed: Int
    
    public init(
        maxUsage: Int,
        currentUsage: Int,
        maxAmount: UInt64,
        amountUsed: UInt64,
        maxTokenAccountCreationAmount: UInt64,
        maxTokenAccountCreationCount: Int,
        tokenAccountCreationAmountUsed: UInt64,
        tokenAccountCreationCountUsed: Int
    ) {
        self.maxUsage = maxUsage
        self.currentUsage = currentUsage
        self.maxAmount = maxAmount
        self.amountUsed = amountUsed
        self.maxTokenAccountCreationAmount = maxTokenAccountCreationAmount
        self.maxTokenAccountCreationCount = maxTokenAccountCreationCount
        self.tokenAccountCreationAmountUsed = tokenAccountCreationAmountUsed
        self.tokenAccountCreationCountUsed = tokenAccountCreationCountUsed
    }
    
    public func isFreeTransactionFeeAvailable(transactionFee: UInt64) -> Bool {
        currentUsage < maxUsage && (amountUsed + transactionFee) <= maxAmount
    }
}
