//
//  FeeRelayer+Relay.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 28/12/2021.
//

import Foundation
import SolanaSwift

public protocol FeeRelayerRelaySwapType: Encodable {}

extension FeeRelayer.Relay {
    // MARK: - Relay info
    public struct RelayInfo {
        var minimumTokenAccountBalance: UInt64
        var minimumRelayAccountBalance: UInt64
        var feePayerAddress: String
        var lamportsPerSignature: UInt64
        var relayAccountStatus: RelayAccountStatus
    }
    
    // MARK: - Top up
    public struct TopUpWithSwapParams: Encodable {
        let userSourceTokenAccountPubkey: String
        let sourceTokenMintPubkey: String
        let userAuthorityPubkey: String
        let topUpSwap: SwapData
        let feeAmount:  UInt64
        let signatures: SwapTransactionSignatures
        let blockhash:  String
        
        enum CodingKeys: String, CodingKey {
            case userSourceTokenAccountPubkey = "user_source_token_account_pubkey"
            case sourceTokenMintPubkey = "source_token_mint_pubkey"
            case userAuthorityPubkey = "user_authority_pubkey"
            case topUpSwap = "top_up_swap"
            case feeAmount = "fee_amount"
            case signatures = "signatures"
            case blockhash = "blockhash"
        }
    }
    
    // MARK: - Swap
    public struct SwapParams: Encodable {
        let userSourceTokenAccountPubkey: String
        let userDestinationPubkey: String
        let userDestinationAccountOwner: String?
        let sourceTokenMintPubkey: String
        let destinationTokenMintPubkey: String
        let userAuthorityPubkey: String
        let userSwap: SwapData
        let feeAmount: UInt64
        let signatures: SwapTransactionSignatures
        let blockhash: String
        
        enum CodingKeys: String, CodingKey {
            case userSourceTokenAccountPubkey = "user_source_token_account_pubkey"
            case userDestinationPubkey = "user_destination_pubkey"
            case userDestinationAccountOwner = "user_destination_account_owner"
            case sourceTokenMintPubkey = "source_token_mint_pubkey"
            case destinationTokenMintPubkey = "destination_token_mint_pubkey"
            case userAuthorityPubkey = "user_authority_pubkey"
            case userSwap = "user_swap"
            case feeAmount = "fee_amount"
            case signatures = "signatures"
            case blockhash = "blockhash"
        }
    }
    
    // MARK: - Swap data
    public struct SwapData: Encodable {
        public init(_ swap: FeeRelayerRelaySwapType) {
            switch swap {
            case let swap as DirectSwapData:
                self.Spl = swap
                self.SplTransitive = nil
            case let swap as TransitiveSwapData:
                self.Spl = nil
                self.SplTransitive = swap
            default:
                fatalError("unsupported swap type")
            }
        }
        
        public let Spl: DirectSwapData?
        public let SplTransitive: TransitiveSwapData?
    }
    
    public struct TransitiveSwapData: FeeRelayerRelaySwapType {
        let from: DirectSwapData
        let to: DirectSwapData
        let transitTokenMintPubkey: String
        
        public init(from: FeeRelayer.Relay.DirectSwapData, to: FeeRelayer.Relay.DirectSwapData, transitTokenMintPubkey: String) {
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
    
    // MARK: - Others
    struct PreparedParams {
        let swapData: FeeRelayerRelaySwapType
        let transaction: SolanaSDK.Transaction
        let feeAmount: FeeRelayer.FeeAmount
        let transferAuthorityAccount: SolanaSDK.Account
    }
    
    public enum RelayAccountStatus: Equatable {
        case notYetCreated
        case created(balance: UInt64)
        
        var balance: UInt64? {
            switch self {
            case .notYetCreated:
                return nil
            case .created(let balance):
                return balance
            }
        }
    }
    
    public struct TokenInfo {
        public init(address: String, mint: String) {
            self.address = address
            self.mint = mint
        }
        
        let address: String
        let mint: String
    }
    
    public struct TopUpAndActionPreparedParams {
        public let topUpFeesAndPools: FeesAndPools?
        public let actionFeesAndPools: FeesAndPools
        public let topUpAmount: UInt64?
    }
    
    public struct FeesAndPools {
        public let fee: FeeRelayer.FeeAmount
        public let poolsPair: OrcaSwap.PoolsPair
    }
}
