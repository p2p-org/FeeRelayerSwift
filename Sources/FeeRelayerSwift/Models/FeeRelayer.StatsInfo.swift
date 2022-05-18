import Foundation

public struct StatsInfo: Codable {
    public enum OperationType: RawRepresentable, Codable {
        public init?(rawValue: String) {
            switch rawValue {
            case "TopUp":
                self = .topUp
            case "Transfer":
                self = .transfer
            case "Swap":
                self = .swap
            default:
                self = .other(rawValue)
            }
        }
        
        public var rawValue: String {
            switch self {
            case .topUp:
                return "TopUp"
            case .transfer:
                return "Transfer"
            case .swap:
                return "Swap"
            case .other(let string):
                return string
            }
        }
        
        public typealias RawValue = String
        
        case topUp
        case transfer
        case swap
        case other(String)
    }
    
    public enum DeviceType: String, Codable {
        case web = "Web"
        case android = "Android"
        case iOS = "Ios"
    }
    
    let operationType: OperationType
    let deviceType: DeviceType
    let currency: String?
    let build: String?
    
    enum CodingKeys: String, CodingKey {
        case operationType = "operation_type"
        case deviceType = "device_type"
        case currency
        case build
    }
    
    public init(operationType: StatsInfo.OperationType, deviceType: StatsInfo.DeviceType, currency: String?, build: String?) {
        self.operationType = operationType
        self.deviceType = deviceType
        self.currency = currency
        self.build = build
    }
}
