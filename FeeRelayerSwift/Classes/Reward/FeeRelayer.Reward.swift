//
//  FeeRelayer.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 16/07/2021.
//

import Foundation

public protocol FeeRelayerRewardType {}

extension FeeRelayer {
    public struct Reward {
        
    }
}

extension FeeRelayer.Reward: FeeRelayerRewardType {}
