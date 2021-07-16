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
}
