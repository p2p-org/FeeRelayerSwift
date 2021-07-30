//
//  FeeRelayer+Error.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 30/07/2021.
//

import Foundation

public protocol FeeRelayerErrorDataType {}
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
        
        case unknown                        = "UnknownError"
    }
    
    public struct Error: Swift.Error {
        public let type: ErrorType
        public let data: FeeRelayerErrorDataType?
    }
    
    public struct FeeRelayerErrorData: FeeRelayerErrorDataType {
        var minimum: Double?
        var actual: Double?
        var expected: Double?
        var found: Double?
    }
}
