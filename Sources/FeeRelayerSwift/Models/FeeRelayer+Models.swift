//
//  FeeRelayer+Models.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 16/07/2021.
//

import Foundation

extension FeeRelayer {
    public typealias Lamports = UInt64
    public typealias Decimals = UInt8
    
    public struct FeeAmount {
        public var transaction: UInt64
        public var accountBalances: UInt64
    }
}
