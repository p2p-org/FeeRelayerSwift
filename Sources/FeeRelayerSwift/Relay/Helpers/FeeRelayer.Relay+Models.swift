//
//  FeeRelayer+Relay.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 28/12/2021.
//

import Foundation
import SolanaSwift
import OrcaSwapSwift

public protocol FeeRelayerRelaySwapType: Encodable {}

extension FeeRelayer.Relay {
    public struct FeeLimitForAuthorityResponse: Codable {
        let authority: [Int]
        let limits: Limits
        let processedFee: ProcessedFee
    
        enum CodingKeys: String, CodingKey {
            case authority, limits
            case processedFee = "processed_fee"
        }
    
        struct Limits: Codable {
            let useFreeFee: Bool
            let maxAmount: UInt64
            let maxCount: Int
            let period: Period
        
            enum CodingKeys: String, CodingKey {
                case useFreeFee = "use_free_fee"
                case maxAmount = "max_amount"
                case maxCount = "max_count"
                case period
            }
        }

        struct Period: Codable {
            let secs, nanos: Int
        }

        struct ProcessedFee: Codable {
            let totalAmount: UInt64
            let count: Int
            
            enum CodingKeys: String, CodingKey {
                case totalAmount = "total_amount"
                case count
            }
        }
    }
    
    public struct FreeTransactionFeeLimit {
        public let maxUsage: Int
        public var currentUsage: Int
        public let maxAmount: UInt64
        public var amountUsed: UInt64
        
        public func isFreeTransactionFeeAvailable(transactionFee: UInt64, forNextTransaction: Bool = false) -> Bool {
            var currentUsage = currentUsage
            if forNextTransaction {
                currentUsage += 1
            }
            return currentUsage < maxUsage && (amountUsed + transactionFee) <= maxAmount
        }
    }
    
    // MARK: - Relay info
    public struct Cache {
        public var minimumTokenAccountBalance: UInt64?
        public var minimumRelayAccountBalance: UInt64?
        public var feePayerAddress: String?
        public var lamportsPerSignature: UInt64?
        public var relayAccountStatus: RelayAccountStatus?
        public var preparedParams: TopUpAndActionPreparedParams?
        public var freeTransactionFeeLimit: FreeTransactionFeeLimit?
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
    
    // MARK: - TransferParam
    public struct TransferParam: Codable {
        let senderTokenAccountPubkey, recipientPubkey, tokenMintPubkey, authorityPubkey: String
        let amount, feeAmount: UInt64
        let decimals: UInt8
        let authoritySignature, blockhash: String
        
        enum CodingKeys: String, CodingKey {
            case senderTokenAccountPubkey = "sender_token_account_pubkey"
            case recipientPubkey = "recipient_pubkey"
            case tokenMintPubkey = "token_mint_pubkey"
            case authorityPubkey = "authority_pubkey"
            case amount = "amount"
            case decimals = "decimals"
            case feeAmount = "fee_amount"
            case authoritySignature = "authority_signature"
            case blockhash = "blockhash"
        }
    }
    
    // MARK: - RelayTransactionParam
    public struct RelayTransactionParam: Codable {
        let instructions: [RequestInstruction]
        let signatures: [String: String]
        let pubkeys: [String]
        let blockhash: String
        
        public init(preparedTransaction: SolanaSDK.PreparedTransaction) throws {
            guard let recentBlockhash = preparedTransaction.transaction.recentBlockhash
            else {throw FeeRelayer.Error.unknown}
            
            let message = try preparedTransaction.transaction.compileMessage()
            pubkeys = message.accountKeys.map {$0.base58EncodedString}
            blockhash = recentBlockhash
            instructions = message.instructions.enumerated().map {index, compiledInstruction -> RequestInstruction in
                let accounts: [RequestAccountMeta] = compiledInstruction.accounts.map { account in
                    let pubkey = message.accountKeys[account]
                    let meta = preparedTransaction.transaction.instructions[index].keys
                        .first(where: {$0.publicKey == pubkey})
                    return .init(
                        pubkeyIndex: UInt8(account),
                        isSigner: meta?.isSigner ?? message.isAccountSigner(index: account),
                        isWritable: meta?.isWritable ?? message.isAccountWritable(index: account)
                    )
                }
                
                return.init(
                    programIndex: compiledInstruction.programIdIndex,
                    accounts: accounts,
                    data: compiledInstruction.data
                )
            }
            var signatures = [String: String]()
            for signer in preparedTransaction.signers {
                if let idx = pubkeys.firstIndex(of: signer.publicKey.base58EncodedString) {
                    let idxString = "\(idx)"
                    let signature = try preparedTransaction.findSignature(publicKey: signer.publicKey)
                    signatures[idxString] = signature
                } else {
                    throw FeeRelayer.Error.invalidSignature
                }
            }
            self.signatures = signatures
        }
    }
    
    public struct RequestInstruction: Codable {
        let programIndex: UInt8
        let accounts: [RequestAccountMeta]
        let data: [UInt8]
        
        enum CodingKeys: String, CodingKey {
            case programIndex = "program_id"
            case accounts
            case data
        }
    }
    
    public struct RequestAccountMeta: Codable {
        let pubkeyIndex: UInt8
        let isSigner: Bool
        let isWritable: Bool
        
        enum CodingKeys: String, CodingKey {
            case pubkeyIndex = "pubkey"
            case isSigner = "is_signer"
            case isWritable = "is_writable"
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
        let needsCreateTransitTokenAccount: Bool
        
        public init(
            from: FeeRelayer.Relay.DirectSwapData,
            to: FeeRelayer.Relay.DirectSwapData,
            transitTokenMintPubkey: String,
            needsCreateTransitTokenAccount: Bool
        ) {
            self.from = from
            self.to = to
            self.transitTokenMintPubkey = transitTokenMintPubkey
            self.needsCreateTransitTokenAccount = needsCreateTransitTokenAccount
        }
        
        enum CodingKeys: String, CodingKey {
            case from, to
            case transitTokenMintPubkey = "transit_token_mint_pubkey"
            case needsCreateTransitTokenAccount = "needs_create_transit_token_account"
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
        let transferAuthoritySignature: String?
        
        public init(userAuthoritySignature: String, transferAuthoritySignature: String?) {
            self.userAuthoritySignature = userAuthoritySignature
            self.transferAuthoritySignature = transferAuthoritySignature
        }
        
        enum CodingKeys: String, CodingKey {
            case userAuthoritySignature = "user_authority_signature"
            case transferAuthoritySignature = "transfer_authority_signature"
        }
    }
    
    // MARK: - Others
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
        
        public let address: String
        public let mint: String
    }
    
    public struct TopUpPreparedParams {
        public let amount: UInt64
        public let expectedFee: UInt64
        public let poolsPair: PoolsPair
    }
    
    public struct TopUpAndActionPreparedParams {
        public let topUpPreparedParam: TopUpPreparedParams?
        public let actionFeesAndPools: FeesAndPools
    }
    
    public struct FeesAndPools {
        public let fee: SolanaSDK.FeeAmount
        public let poolsPair: PoolsPair
    }
    
    public struct FeesAndTopUpAmount {
        public let feeInSOL: SolanaSDK.FeeAmount?
        public let topUpAmountInSOL: UInt64?
        public let feeInPayingToken: SolanaSDK.FeeAmount?
        public let topUpAmountInPayingToen: UInt64?
    }
}
