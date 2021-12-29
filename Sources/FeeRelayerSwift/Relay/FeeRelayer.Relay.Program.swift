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
            try .findProgramAddress(seeds: [user.data, "relay".data(using: .utf8)!], programId: id).0
        }
        
        static func getUserTemporaryWSOLAddress(
            user: SolanaSDK.PublicKey
        ) throws -> SolanaSDK.PublicKey {
            try .findProgramAddress(seeds: [user.data, "temporary_wsol".data(using: .utf8)!], programId: id).0
        }
        
        static func getTransitTokenAccountAddress(
            user: SolanaSDK.PublicKey,
            transitTokenMint: SolanaSDK.PublicKey
        ) throws -> SolanaSDK.PublicKey {
            try .findProgramAddress(seeds: [user.data, transitTokenMint.data, "transit".data(using: .utf8)!], programId: id).0
        }
        
        static func topUpSwapInstruction(
            topUpSwap: FeeRelayerRelaySwapType,
            userAuthorityAddress: SolanaSDK.PublicKey,
            userSourceTokenAccountAddress: SolanaSDK.PublicKey,
            feePayerAddress: SolanaSDK.PublicKey
        ) throws -> SolanaSDK.TransactionInstruction {
            let userRelayAddress = try getUserRelayAddress(user: userAuthorityAddress)
            let userTemporarilyWSOLAddress = try getUserTemporaryWSOLAddress(user: userAuthorityAddress)
            
            switch topUpSwap {
            case let swap as DirectSwapData:
            case let swap as TransitiveSwapData:
            default:
                fatalError("unsupported swap type")
            }
        }
        
        static func transferSolInstruction(
            topUpSwap: FeeRelayerRelaySwapType,
            userAuthorityAddress: SolanaSDK.PublicKey,
            recipient: SolanaSDK.PublicKey,
            lamports: UInt64
        ) throws -> SolanaSDK.TransactionInstruction {
            
        }
        
        static func createTransitTokenAccountInstruction(
            feePayer: SolanaSDK.PublicKey,
            userAuthority: SolanaSDK.PublicKey,
            transitTokenAccount: SolanaSDK.PublicKey,
            transitTokenMint: SolanaSDK.PublicKey
        ) throws -> SolanaSDK.TransactionInstruction {
            
        }
    }
}
