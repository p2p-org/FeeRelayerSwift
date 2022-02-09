//
//  FeeRelayer+Error.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 30/07/2021.
//

import Foundation

public protocol FeeRelayerErrorDataType: Decodable {}
extension String: FeeRelayerErrorDataType {}

extension FeeRelayer {
    public enum ErrorType: String {
        case parseHashError                 = "ParseHashError"
        case parsePubkeyError               = "ParsePubkeyError"
        case parseKeypairError              = "ParseKeypairError"
        case parseSignatureError            = "ParseSignatureError"
        case wrongSignature                 = "WrongSignature"
        case signerError                    = "SignerError"
        case clientError                    = "ClientError"
        case programError                   = "ProgramError"
        case tooSmallAmount                 = "TooSmallAmount"
        case notEnoughBalance               = "NotEnoughBalance "
        case notEnoughTokenBalance          = "NotEnoughTokenBalance"
        case decimalsMismatch               = "DecimalsMismatch"
        case tokenAccountNotFound           = "TokenAccountNotFound"
        case incorrectAccountOwner          = "IncorrectAccountOwner"
        case tokenMintMismatch              = "TokenMintMismatch"
        case unsupportedRecipientAddress    = "UnsupportedRecipientAddress"
        case feeCalculatorNotFound          = "FeeCalculatorNotFound"
        case notEnoughOutAmount             = "NotEnoughOutAmount"
        case unknownSwapProgramId           = "UnknownSwapProgramId"
        
        case unknown                        = "UnknownError"
    }
    
    public struct Error: Swift.Error, Decodable, Equatable {
        
        public let code: Int
        public let message: String
        public let data: ErrorDetail?
        
        public static var unknown: Self {
            .init(code: -1, message: "Unknown error", data: nil)
        }
        
        public static var wrongAddress: Self {
            .init(code: 0, message: "Wrong address", data: nil)
        }
        
        public static var swapPoolsNotFound: Self {
            .init(code: 1, message: "Swap pools not found", data: nil)
        }
        
        public static var transitTokenMintNotFound: Self {
            .init(code: 2, message: "Transit token mint not found", data: nil)
        }
        
        public static var invalidAmount: Self {
            .init(code: 3, message: "Invalid amount", data: nil)
        }
        
        public static var invalidSignature: Self {
            .init(code: 4, message: "Invalid signature", data: nil)
        }
        
        public static var unsupportedSwap: Self {
            .init(code: 5, message: "Unssuported swap", data: nil)
        }
        
        public static var relayInfoMissing: Self {
            .init(code: 6, message: "Relay info missing", data: nil)
        }
        
        public static var invalidFeePayer: Self {
            .init(code: 7, message: "Invalid fee payer", data: nil)
        }
        
        public static var unauthorized: Self {
            .init(code: 403, message: "Unauthorized", data: nil)
        }
    }
    
    public struct ErrorDetail: Decodable, Equatable {
        public let type: ErrorType?
        public let data: ErrorData?
        
        init(type: FeeRelayer.ErrorType?, data: FeeRelayer.ErrorData?) {
            self.type = type
            self.data = data
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.singleValueContainer()
            let dict = try values.decode([String: ErrorData].self).first
            
            let code = dict?.key ?? "Unknown"
            type = ErrorType(rawValue: code) ?? .unknown
            data = dict?.value
        }
    }
    
    public struct ErrorData: Decodable, Equatable {
        public let array: [String]?
        public let dict: [String: UInt64]?
        
        init(array: [String]? = nil, dict: [String : UInt64]? = nil) {
            self.array = array
            self.dict = dict
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.singleValueContainer()
            array = try? values.decode([String].self)
            dict = try? values.decode([String: UInt64].self)
        }
    }
}
