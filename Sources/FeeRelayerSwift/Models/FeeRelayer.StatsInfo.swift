import Foundation

public struct StatsInfo: Codable {
    enum OperationType: String, Codable {
        case topUp = "TopUp"
        case transfer = "Transfer"
        case swap = "Swap"
    }
    
    public enum DeviceType: String, Codable {
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
