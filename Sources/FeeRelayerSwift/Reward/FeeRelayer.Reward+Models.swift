//
//  FeeRelayer.Reward+Models.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 29/12/2021.
//

import Foundation
import SolanaSwift

extension FeeRelayer.Reward {
    // MARK: - Transfer SOL
    public struct TransferSolParams: Encodable {
        let sender: String
        let recipient: String
        let amount: SolanaSDK.Lamports
        var signature: String
        var blockhash: String
        let statsInfo: StatsInfo
        
        public init(sender: String, recipient: String, amount: SolanaSDK.Lamports, signature: String, blockhash: String, deviceType: StatsInfo.DeviceType, buildNumber: String) {
            self.sender = sender
            self.recipient = recipient
            self.amount = amount
            self.signature = signature
            self.blockhash = blockhash
            self.statsInfo = .init(
                operationType: .transfer,
                deviceType: deviceType,
                currency: "SOL",
                build: buildNumber
            )
        }
        
        enum CodingKeys: String, CodingKey {
            case sender     =   "sender_pubkey"
            case recipient  =   "recipient_pubkey"
            case amount     =   "lamports"
            case signature
            case blockhash
            case statsInfo  =   "info"
        }
    }
    
    // MARK: - Transfer SPL Tokens
    public struct TransferSPLTokenParams: Encodable {
        let sender: String
        let recipient: String
        let mintAddress: String
        let authority: String
        let amount: SolanaSDK.Lamports
        let decimals: SolanaSDK.Decimals
        var signature: String
        var blockhash: String
        let statsInfo: StatsInfo
        
        public init(sender: String, recipient: String, mintAddress: String, authority: String, amount: SolanaSDK.Lamports, decimals: SolanaSDK.Decimals, signature: String, blockhash: String, deviceType: StatsInfo.DeviceType, buildNumber: String) {
            self.sender = sender
            self.recipient = recipient
            self.mintAddress = mintAddress
            self.authority = authority
            self.amount = amount
            self.decimals = decimals
            self.signature = signature
            self.blockhash = blockhash
            self.statsInfo = .init(
                operationType: .transfer,
                deviceType: deviceType,
                currency: mintAddress,
                build: buildNumber
            )
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
            case statsInfo      =   "info"
        }
    }
}
