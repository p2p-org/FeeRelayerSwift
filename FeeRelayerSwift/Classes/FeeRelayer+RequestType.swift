//
//  FeeRelayer+RequestType.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 16/07/2021.
//

import Foundation

extension FeeRelayer {
    public enum RequestType {
        private static let transferSOLPath     = "/transfer_sol"
        private static let transferTokenPath   = "/transfer_spl_token"
        private static let swapTokenPath       = "/swap_spl_token_with_fee_compensation"
        
        case transferSOL(TransferSolParams)
        case transferSPLToken(TransferSPLTokenParams)
        case swapToken(SwapTokensParams)
        
        var url: String {
            var url = FeeRelayer.feeRelayerUrl
            switch self {
            case .transferSOL:
                url += RequestType.transferSOLPath
            case .transferSPLToken:
                url += RequestType.transferTokenPath
            case .swapToken:
                url += RequestType.swapTokenPath
            }
            return url
        }
        
        public func getParams() throws -> Data {
            switch self {
            case .transferSOL(let params):
                return try JSONEncoder().encode(params)
            case .transferSPLToken(let params):
                return try JSONEncoder().encode(params)
            case .swapToken(let params):
                return try JSONEncoder().encode(params)
            }
        }
    }
}
