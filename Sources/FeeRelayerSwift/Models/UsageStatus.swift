// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation

/// A user's usage status for fee relayer service.
public struct UsageStatus {
    public let maxUsage: Int
    public var currentUsage: Int
    public let maxAmount: UInt64
    public var amountUsed: UInt64

    public func isFreeTransactionFeeAvailable(transactionFee: UInt64, forNextTransaction: Bool = false) -> Bool {
        var currentUsage = currentUsage
        if forNextTransaction {
            currentUsage += 1
        }
        return currentUsage < maxUsage && (amountUsed + transactionFee) <= maxAmount
    }
}
