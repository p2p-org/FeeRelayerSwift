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
    
    // MARK: - Transfer SOL
    public struct TransferSolParams: Encodable {
        let sender: String
        let recipient: String
        let amount: Lamports
        var signature: String
        var blockhash: String
        
        public init(sender: String, recipient: String, amount: Lamports, signature: String, blockhash: String) {
            self.sender = sender
            self.recipient = recipient
            self.amount = amount
            self.signature = signature
            self.blockhash = blockhash
        }
        
        enum CodingKeys: String, CodingKey {
            case sender     =   "sender_pubkey"
            case recipient  =   "recipient_pubkey"
            case amount     =   "lamports"
            case signature
            case blockhash
        }
    }
    
    // MARK: - Transfer SPL Tokens
    public struct TransferSPLTokenParams: Encodable {
        let sender: String
        let recipient: String
        let mintAddress: String
        let authority: String
        let amount: Lamports
        let decimals: Decimals
        var signature: String
        var blockhash: String
        
        public init(sender: String, recipient: String, mintAddress: String, authority: String, amount: FeeRelayer.Lamports, decimals: FeeRelayer.Decimals, signature: String, blockhash: String) {
            self.sender = sender
            self.recipient = recipient
            self.mintAddress = mintAddress
            self.authority = authority
            self.amount = amount
            self.decimals = decimals
            self.signature = signature
            self.blockhash = blockhash
        }
        
        enum CodingKeys: String, CodingKey {
            case sender         =   "sender_token_account_pubkey"
            case recipient      =   "recipient_pubkey"
            case mintAddress    =   "token_mint_pubkey"
            case authority      =   "authority_pubkey"
            case amount
            case decimals
            case signature
            case blockhash
        }
    }
    
    // MARK: - Swap Tokens
    public struct SwapTokensParams: Encodable {
        let source: String
        let sourceMint: String
        let destination: String
        let destinationMint: String
        let authority: String
        let swapAccount: SwapTokensParamsSwapAccount
        let feeCompensationSwapAccount: SwapTokensParamsSwapAccount
        let feePayerWSOLAccountKeypair: String
        let signature: String
        let blockhash: String
        
        public init(source: String, sourceMint: String, destination: String, destinationMint: String, authority: String, swapAccount: FeeRelayer.SwapTokensParamsSwapAccount, feeCompensationSwapAccount: FeeRelayer.SwapTokensParamsSwapAccount, feePayerWSOLAccountKeypair: String, signature: String, blockhash: String) {
            self.source = source
            self.sourceMint = sourceMint
            self.destination = destination
            self.destinationMint = destinationMint
            self.authority = authority
            self.swapAccount = swapAccount
            self.feeCompensationSwapAccount = feeCompensationSwapAccount
            self.feePayerWSOLAccountKeypair = feePayerWSOLAccountKeypair
            self.signature = signature
            self.blockhash = blockhash
        }
        
        enum CodingKeys: String, CodingKey {
            case source             =   "user_source_token_account_pubkey"
            case sourceMint         =   "source_token_mint_pubkey"
            case destination        =   "user_destination_pubkey"
            case destinationMint    =   "destination_token_mint_pubkey"
            case authority          =   "user_authority_pubkey"
            case swapAccount        =   "user_swap"
            case feeCompensationSwapAccount
                                    =   "fee_compensation_swap"
            case feePayerWSOLAccountKeypair
                                    =   "fee_payer_wsol_account_keypair"
            case signature
            case blockhash
        }
    }
    
    public struct SwapTokensParamsSwapAccount: Encodable {
        let pubkey: String
        let authority: String
        let transferAuthority: String
        let source: String
        let destination: String
        let poolTokenMint: String
        let poolFeeAccount: String
        let amountIn: Lamports
        let minimumAmountOut: Lamports
        
        public init(pubkey: String, authority: String, transferAuthority: String, source: String, destination: String, poolTokenMint: String, poolFeeAccount: String, amountIn: FeeRelayer.Lamports, minimumAmountOut: FeeRelayer.Lamports) {
            self.pubkey = pubkey
            self.authority = authority
            self.transferAuthority = transferAuthority
            self.source = source
            self.destination = destination
            self.poolTokenMint = poolTokenMint
            self.poolFeeAccount = poolFeeAccount
            self.amountIn = amountIn
            self.minimumAmountOut = minimumAmountOut
        }
        
        enum CodingKeys: String, CodingKey {
            case pubkey             =   "account_pubkey"
            case authority          =   "authority_pubkey"
            case transferAuthority  =   "transfer_authority_pubkey"
            case source             =   "source_pubkey"
            case destination        =   "destination_pubkey"
            case poolTokenMint      =   "pool_token_mint_pubkey"
            case poolFeeAccount     =   "pool_fee_account_pubkey"
            case amountIn           =   "amount_in"
            case minimumAmountOut   =   "minimum_amount_out"
        }
    }
}
