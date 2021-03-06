// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

public struct FeeRelayerContext: Hashable {
    public let minimumTokenAccountBalance: UInt64
    public let minimumRelayAccountBalance: UInt64
    public let feePayerAddress: PublicKey
    public let lamportsPerSignature: UInt64
    public let relayAccountStatus: RelayAccountStatus
    public let usageStatus: UsageStatus
    
    public init(
        minimumTokenAccountBalance: UInt64,
        minimumRelayAccountBalance: UInt64,
        feePayerAddress: PublicKey,
        lamportsPerSignature: UInt64,
        relayAccountStatus: RelayAccountStatus,
        usageStatus: UsageStatus
    ) {
        self.minimumTokenAccountBalance = minimumTokenAccountBalance
        self.minimumRelayAccountBalance = minimumRelayAccountBalance
        self.feePayerAddress = feePayerAddress
        self.lamportsPerSignature = lamportsPerSignature
        self.relayAccountStatus = relayAccountStatus
        self.usageStatus = usageStatus
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(minimumTokenAccountBalance)
        hasher.combine(minimumRelayAccountBalance)
        hasher.combine(feePayerAddress)
        hasher.combine(lamportsPerSignature)
    }
    
    public static func ==(lhs: FeeRelayerContext, rhs: FeeRelayerContext) -> Bool {
        if lhs.minimumTokenAccountBalance != rhs.minimumTokenAccountBalance { return false }
        if lhs.minimumRelayAccountBalance != rhs.minimumRelayAccountBalance { return false }
        if lhs.feePayerAddress != rhs.feePayerAddress { return false }
        if lhs.lamportsPerSignature != rhs.lamportsPerSignature { return false }
        if lhs.relayAccountStatus != rhs.relayAccountStatus { return false }
        return true
    }
}
