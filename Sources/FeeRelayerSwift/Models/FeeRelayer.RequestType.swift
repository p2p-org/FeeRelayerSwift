//
//  FeeRelayer+RequestType.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 16/07/2021.
//

import Foundation

extension FeeRelayer {
    public struct EncodableWrapper: Encodable {
        let wrapped: Encodable
        
        public func encode(to encoder: Encoder) throws {
            try self.wrapped.encode(to: encoder)
        }
    }
    
    public struct RequestType {
        // MARK: - Properties
        private let path: String
        private let params: EncodableWrapper
        
        // MARK: - Initializer
        public init(path: String, params: Encodable) {
            self.path = path
            self.params = EncodableWrapper(wrapped: params)
        }
        
        // MARK: - Getters
        public var url: String {
            FeeRelayer.feeRelayerUrl + path
        }
        
        public func getParams() throws -> Data {
            try JSONEncoder().encode(params)
        }
        
        // MARK: - Builders
        public static func transferSOL(_ params: Reward.TransferSolParams) -> RequestType {
            .init(path: "/transfer_sol", params: params)
        }
        
        public static func transferSPLToken(_ params: Reward.TransferSPLTokenParams) -> RequestType {
            .init(path: "/transfer_spl_token", params: params)
        }
        
        public static func swapToken(_ params: Compensation.SwapTokensParams) -> RequestType {
            .init(path: "/swap_spl_token_with_fee_compensation", params: params)
        }
        
        public static func relayTopUpWithSwap(_ params: Relay.TopUpParams) -> RequestType {
            .init(path: "/v2/relay_top_up_with_swap", params: params)
        }
        
        public static func relaySwap(_ params: Relay.SwapParams) -> RequestType {
            .init(path: "/v2/relay_swap", params: params)
        }
        
        
    }
}
