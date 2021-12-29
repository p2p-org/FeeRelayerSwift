//
//  FeeRelayer.Relay.Program.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 29/12/2021.
//

import Foundation
import SolanaSwift

extension FeeRelayer.Relay {
    struct Program {
        static let id: SolanaSDK.PublicKey = "24tpHRcbGKGYFGMYq66G3hfH8GQEYGTysXqiJyaCy9eR"
        
        static func getUserRelayAddress(
            user: SolanaSDK.PublicKey
        ) throws -> SolanaSDK.PublicKey {
            try .createWithSeed(fromPublicKey: user, seed: "relay", programId: id)
        }
    }
}
