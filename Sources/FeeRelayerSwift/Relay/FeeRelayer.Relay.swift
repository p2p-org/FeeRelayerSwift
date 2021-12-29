//
//  FeeRelayer+Relay.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 29/12/2021.
//

import Foundation
import RxSwift
import SolanaSwift

public protocol FeeRelayerRelayType {}

extension FeeRelayer {
    public struct Relay {
        func prepareForTopUp(
            userSourceTokenAccountAddress: String,
            sourceTokenMintAddress: String,
            userAuthorityAddress: SolanaSDK.PublicKey,
            topUpSwap: FeeRelayerRelaySwapType,
            feeAmount: UInt64,
            minimumRelayAccountBalance: UInt64,
            minimumTokenAccountBalance: UInt64,
            needsCreateUserRelayAccount: Bool,
            feePayerAddress: String
        ) -> Single<String> {
            // assertion
            guard let userSourceTokenAccountAddress = try? SolanaSDK.PublicKey(string: userSourceTokenAccountAddress),
                  let sourceTokenMintAddress = try? SolanaSDK.PublicKey(string: sourceTokenMintAddress),
                  let feePayerAddress = try? SolanaSDK.PublicKey(string: feePayerAddress),
                  let associatedTokenAddress = try? SolanaSDK.PublicKey.associatedTokenAddress(walletAddress: feePayerAddress, tokenMintAddress: sourceTokenMintAddress),
                  userSourceTokenAccountAddress != associatedTokenAddress
            else {return .error(FeeRelayer.Error.wrongAddress)}
            
            // forming transaction and count fees
            var expectedFee = FeeAmount(transaction: 0, accountBalances: 0)
            var instructions = [SolanaSDK.TransactionInstruction]()
            
            // create user relay account
            do {
                if needsCreateUserRelayAccount {
                    let userRelayAddress = try Program.getUserRelayAddress(user: userAuthorityAddress)
                    instructions.append(
                        SolanaSDK.SystemProgram.transferInstruction(
                            from: feePayerAddress,
                            to: userRelayAddress,
                            lamports: minimumRelayAccountBalance
                        )
                    )
                    expectedFee.accountBalances += minimumRelayAccountBalance
                }
                
                // top up swap
                switch topUpSwap {
                case let swap as DirectSwapData:
                    expectedFee.accountBalances += minimumTokenAccountBalance
                    instructions.append(
                        SolanaSDK.TokenProgram.approveInstruction(
                            tokenProgramId: .tokenProgramId,
                            account: userSourceTokenAccountAddress,
                            delegate: try SolanaSDK.PublicKey(string: swap.transferAuthorityPubkey),
                            owner: userAuthorityAddress,
                            amount: swap.amountIn
                        )
                    )
                    instructions.append(
                        try Program.topUpSwapInstruction(
                            topUpSwap: swap,
                            userAuthorityAddress: userAuthorityAddress,
                            userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                            feePayerAddress: feePayerAddress
                        )
                    )
                    instructions.append(
                        try Program.transferSolInstruction(
                            topUpSwap: swap,
                            userAuthorityAddress: userAuthorityAddress,
                            recipient: feePayerAddress,
                            lamports: feeAmount
                        )
                    )
                case let swap as TransitiveSwapData:
                    instructions.append(
                        SolanaSDK.TokenProgram.approveInstruction(
                            tokenProgramId: .tokenProgramId,
                            account: userSourceTokenAccountAddress,
                            delegate: try SolanaSDK.PublicKey(string: swap.from.transferAuthorityPubkey),
                            owner: userAuthorityAddress,
                            amount: swap.from.amountIn
                        )
                    )
                    let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
                        user: userAuthorityAddress,
                        transitTokenMint: try SolanaSDK.PublicKey(string: swap.transitTokenMintPubkey)
                    )
                    
                    
                default:
                    fatalError("unsupported swap type")
                }
            } catch {
                return .error(error)
            }
        }
    }
}

extension FeeRelayer.Relay: FeeRelayerRelayType {}
