import Foundation

public struct StatsInfo: Encodable {
    enum OperationType: String, Encodable {
        case topUp = "TopUp"
        case transfer = "Transfer"
        case swap = "Swap"
    }
    
    public enum DeviceType: String, Encodable {
        case web = "Web"
        case android = "Android"
        case iOS = "Ios"
    }
    
    let operationType: OperationType
    let deviceType: DeviceType
    let currency: String?
    let build: String
    
    enum CodingKeys: String, CodingKey {
        case operationType = "operation_type"
        case deviceType = "device_type"
        case currency
        case build
    }
}
