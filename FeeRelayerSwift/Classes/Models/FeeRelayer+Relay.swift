//
//  FeeRelayer+Relay.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 28/12/2021.
//

import Foundation

public protocol FeeRelayerRelaySwapType: Encodable {}

extension FeeRelayer {
    // MARK: - Top up
    public struct RelayTopUpParams: Encodable {
        let userSourceTokenAccountPubkey: String
        let sourceTokenMintPubkey: String
        let userAuthorityPubkey: String
        let topUpSwap: FeeRelayerRelaySwapType
        let feeAmount:  UInt64
        let signatures: SwapTransactionSignatures
        let blockhash:  String
        
        public init(userSourceTokenAccountPubkey: String, sourceTokenMintPubkey: String, userAuthorityPubkey: String, topUpSwap: FeeRelayerRelaySwapType, feeAmount: UInt64, signatures: FeeRelayer.SwapTransactionSignatures, blockhash: String) {
            self.userSourceTokenAccountPubkey = userSourceTokenAccountPubkey
            self.sourceTokenMintPubkey = sourceTokenMintPubkey
            self.userAuthorityPubkey = userAuthorityPubkey
            self.topUpSwap = topUpSwap
            self.feeAmount = feeAmount
            self.signatures = signatures
            self.blockhash = blockhash
        }
        
        enum CodingKeys: String, CodingKey {
            case userSourceTokenAccountPubkey = "user_source_token_account_pubkey"
            case sourceTokenMintPubkey = "source_token_mint_pubkey"
            case userAuthorityPubkey = "user_authority_pubkey"
            case topUpSwap = "top_up_swap"
            case feeAmount = "fee_amount"
            case signatures = "signatures"
            case blockhash = "blockhash"
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(userSourceTokenAccountPubkey, forKey: .userSourceTokenAccountPubkey)
            try container.encode(sourceTokenMintPubkey, forKey: .sourceTokenMintPubkey)
            try container.encode(userAuthorityPubkey, forKey: .userAuthorityPubkey)
            switch topUpSwap {
            case let swap as DirectSwapData:
                try container.encode(swap, forKey: .topUpSwap)
            case let swap as TransitiveSwapData:
                try container.encode(swap, forKey: .topUpSwap)
            default:
                fatalError("unsupported swap type")
            }
            try container.encode(feeAmount, forKey: .feeAmount)
            try container.encode(signatures, forKey: .signatures)
            try container.encode(blockhash, forKey: .blockhash)
        }
    }
    
    // MARK: - Swap data
    public struct TransitiveSwapData: FeeRelayerRelaySwapType {
        let from: DirectSwapData
        let to: DirectSwapData
        let transitTokenMintPubkey: String
        
        public init(from: FeeRelayer.DirectSwapData, to: FeeRelayer.DirectSwapData, transitTokenMintPubkey: String) {
            self.from = from
            self.to = to
            self.transitTokenMintPubkey = transitTokenMintPubkey
        }
        
        enum CodingKeys: String, CodingKey {
            case from, to
            case transitTokenMintPubkey = "transit_token_mint_pubkey"
        }
    }
    
    public struct DirectSwapData: FeeRelayerRelaySwapType {
        let programId: String
        let accountPubkey: String
        let authorityPubkey: String
        let transferAuthorityPubkey: String
        let sourcePubkey: String
        let destinationPubkey: String
        let poolTokenMintPubkey: String
        let poolFeeAccountPubkey: String
        let amountIn: UInt64
        let minimumAmountOut: UInt64
        
        public init(programId: String, accountPubkey: String, authorityPubkey: String, transferAuthorityPubkey: String, sourcePubkey: String, destinationPubkey: String, poolTokenMintPubkey: String, poolFeeAccountPubkey: String, amountIn: UInt64, minimumAmountOut: UInt64) {
            self.programId = programId
            self.accountPubkey = accountPubkey
            self.authorityPubkey = authorityPubkey
            self.transferAuthorityPubkey = transferAuthorityPubkey
            self.sourcePubkey = sourcePubkey
            self.destinationPubkey = destinationPubkey
            self.poolTokenMintPubkey = poolTokenMintPubkey
            self.poolFeeAccountPubkey = poolFeeAccountPubkey
            self.amountIn = amountIn
            self.minimumAmountOut = minimumAmountOut
        }
        
        enum CodingKeys: String, CodingKey {
            case programId = "program_id"
            case accountPubkey = "account_pubkey"
            case authorityPubkey = "authority_pubkey"
            case transferAuthorityPubkey = "transfer_authority_pubkey"
            case sourcePubkey = "source_pubkey"
            case destinationPubkey = "destination_pubkey"
            case poolTokenMintPubkey = "pool_token_mint_pubkey"
            case poolFeeAccountPubkey = "pool_fee_account_pubkey"
            case amountIn = "amount_in"
            case minimumAmountOut = "minimum_amount_out"
        }
    }
    
    public struct SwapTransactionSignatures: Encodable {
        let userAuthoritySignature: String
        let transferAuthoritySignature: String
        
        public init(userAuthoritySignature: String, transferAuthoritySignature: String) {
            self.userAuthoritySignature = userAuthoritySignature
            self.transferAuthoritySignature = transferAuthoritySignature
        }
        
        enum CodingKeys: String, CodingKey {
            case userAuthoritySignature = "user_authority_signature"
            case transferAuthoritySignature = "transfer_authority_signature"
        }
    }
}
