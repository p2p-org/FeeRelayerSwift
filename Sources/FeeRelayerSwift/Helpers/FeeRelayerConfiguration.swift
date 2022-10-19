import Foundation

/// Configuration for fee relayer
public struct FeeRelayerConfiguration {
    let additionalPaybackFee: UInt64
    
    let operationType: StatsInfo.OperationType
    let currency: String?

    public init(additionalPaybackFee: UInt64 = 0, operationType: StatsInfo.OperationType, currency: String? = nil) {
        self.additionalPaybackFee = additionalPaybackFee
        self.operationType = operationType
        self.currency = currency
    }
}
