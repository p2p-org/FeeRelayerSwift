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
        private static let relayTopUpPath      = "/relay_top_up_with_swap"
        
        case transferSOL(TransferSolParams)
        case transferSPLToken(TransferSPLTokenParams)
        case swapToken(SwapTokensParams)
        case relayTopUp(RelayTopUpParams)
        
        var url: String {
            var endpoint = FeeRelayer.feeRelayerUrl
            let path: String
            switch self {
            case .transferSOL:
                path = RequestType.transferSOLPath
            case .transferSPLToken:
                path = RequestType.transferTokenPath
            case .swapToken:
                path = RequestType.swapTokenPath
            case .relayTopUp:
                fatalError("New endpoint?")
                path = RequestType.relayTopUpPath
            }
            return endpoint + path
        }
        
        public func getParams() throws -> Data {
            switch self {
            case .transferSOL(let params):
                return try JSONEncoder().encode(params)
            case .transferSPLToken(let params):
                return try JSONEncoder().encode(params)
            case .swapToken(let params):
                return try JSONEncoder().encode(params)
            case .relayTopUp(let params):
                return try JSONEncoder().encode(params)
            }
        }
    }
}
