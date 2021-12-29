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
        
        case transferSOL(Reward.TransferSolParams)
        case transferSPLToken(Reward.TransferSPLTokenParams)
        case swapToken(Compensation.SwapTokensParams)
        case relayTopUp(Relay.TopUpParams)
        
        var url: String {
            let endpoint = FeeRelayer.feeRelayerUrl
            let path: String
            switch self {
            case .transferSOL:
                path = RequestType.transferSOLPath
            case .transferSPLToken:
                path = RequestType.transferTokenPath
            case .swapToken:
                path = RequestType.swapTokenPath
            case .relayTopUp:
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
