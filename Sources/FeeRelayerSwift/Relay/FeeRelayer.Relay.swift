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
    public class Relay {
        // MARK: - Properties
        private let solanaSDK: SolanaSDK
        
        // MARK: - Initializers
        public init(solanaSDK: SolanaSDK) {
            self.solanaSDK = solanaSDK
        }
        
        // MARK: - Methods
        func topUp(
            userSourceTokenAccountAddress: String,
            sourceTokenMintAddress: String,
            userAuthorityAddress: SolanaSDK.PublicKey,
            topUpPools: OrcaSwap.PoolsPair,
            amount: UInt64,
            transitTokenMintPubkey: SolanaSDK.PublicKey? = nil
        ) -> Single<[String]> {
            do {
                // preconditions
                guard topUpPools.count > 0 && topUpPools.count <= 2 else { throw FeeRelayer.Error.swapPoolsNotFound }
                let defaultSlippage = 0.01
                
                // create transferAuthority
                let transferAuthority = try SolanaSDK.Account(network: .mainnetBeta)
                
                // form topUp params
                if topUpPools.count == 1 {
                    let pool = topUpPools[0]
                    
                    guard let amountIn = try pool.getInputAmount(minimumReceiveAmount: amount, slippage: defaultSlippage) else {
                        throw FeeRelayer.Error.invalidAmount
                    }
                    
                    let directSwapData = pool.getSwapData(
                        transferAuthorityPubkey: transferAuthority.publicKey,
                        amountIn: amountIn,
                        minAmountOut: amount
                    )
                } else {
                    let firstPool = topUpPools[0]
                    let secondPool = topUpPools[1]
                    
                    guard let transitTokenMintPubkey = transitTokenMintPubkey,
                          let secondPoolAmountIn = try secondPool.getInputAmount(minimumReceiveAmount: amount, slippage: defaultSlippage),
                          let firstPoolAmountIn = try firstPool.getInputAmount(minimumReceiveAmount: secondPoolAmountIn, slippage: defaultSlippage)
                    else {
                        throw FeeRelayer.Error.transitTokenMintNotFound
                    }
                    
                    let transitiveSwapData = TransitiveSwapData(
                        from: firstPool.getSwapData(
                            transferAuthorityPubkey: transferAuthority.publicKey,
                            amountIn: firstPoolAmountIn,
                            minAmountOut: secondPoolAmountIn
                        ),
                        to: secondPool.getSwapData(
                            transferAuthorityPubkey: transferAuthority.publicKey,
                            amountIn: secondPoolAmountIn,
                            minAmountOut: amount
                        ),
                        transitTokenMintPubkey: transitTokenMintPubkey.base58EncodedString
                    )
                }
                
                // requests
                let getRecentBlockhashRequest = solanaSDK.getRecentBlockhash(commitment: "recent")
            } catch {
                return .error(error)
            }
            
        }
        
        func prepareForTopUp(
            userSourceTokenAccountAddress: String,
            sourceTokenMintAddress: String,
            userAuthorityAddress: SolanaSDK.PublicKey,
            topUpSwap: FeeRelayerRelaySwapType,
            feeAmount: UInt64,
            blockhash: String,
            minimumRelayAccountBalance: UInt64,
            minimumTokenAccountBalance: UInt64,
            needsCreateUserRelayAccount: Bool,
            feePayerAddress: String,
            lamportsPerSignature: UInt64
        ) throws -> (SolanaSDK.Transaction, FeeAmount) {
            // assertion
            guard let userSourceTokenAccountAddress = try? SolanaSDK.PublicKey(string: userSourceTokenAccountAddress),
                  let sourceTokenMintAddress = try? SolanaSDK.PublicKey(string: sourceTokenMintAddress),
                  let feePayerAddress = try? SolanaSDK.PublicKey(string: feePayerAddress),
                  let associatedTokenAddress = try? SolanaSDK.PublicKey.associatedTokenAddress(walletAddress: feePayerAddress, tokenMintAddress: sourceTokenMintAddress),
                  userSourceTokenAccountAddress != associatedTokenAddress
            else { throw FeeRelayer.Error.wrongAddress }
            
            // forming transaction and count fees
            var expectedFee = FeeAmount(transaction: 0, accountBalances: 0)
            var instructions = [SolanaSDK.TransactionInstruction]()
            
            // create user relay account
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
                // approve
                instructions.append(
                    SolanaSDK.TokenProgram.approveInstruction(
                        tokenProgramId: .tokenProgramId,
                        account: userSourceTokenAccountAddress,
                        delegate: try SolanaSDK.PublicKey(string: swap.transferAuthorityPubkey),
                        owner: userAuthorityAddress,
                        amount: swap.amountIn
                    )
                )
                
                // top up
                instructions.append(
                    try Program.topUpSwapInstruction(
                        topUpSwap: swap,
                        userAuthorityAddress: userAuthorityAddress,
                        userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                        feePayerAddress: feePayerAddress
                    )
                )
                
                // transfer
                instructions.append(
                    try Program.transferSolInstruction(
                        topUpSwap: swap,
                        userAuthorityAddress: userAuthorityAddress,
                        recipient: feePayerAddress,
                        lamports: feeAmount
                    )
                )
            case let swap as TransitiveSwapData:
                // approve
                instructions.append(
                    SolanaSDK.TokenProgram.approveInstruction(
                        tokenProgramId: .tokenProgramId,
                        account: userSourceTokenAccountAddress,
                        delegate: try SolanaSDK.PublicKey(string: swap.from.transferAuthorityPubkey),
                        owner: userAuthorityAddress,
                        amount: swap.from.amountIn
                    )
                )
                // create transit token account
                let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
                    user: userAuthorityAddress,
                    transitTokenMint: try SolanaSDK.PublicKey(string: swap.transitTokenMintPubkey)
                )
                instructions.append(
                    try Program.createTransitTokenAccountInstruction(
                        feePayer: feePayerAddress,
                        userAuthority: userAuthorityAddress,
                        transitTokenAccount: transitTokenAccountAddress,
                        transitTokenMint: try SolanaSDK.PublicKey(string: swap.transitTokenMintPubkey)
                    )
                )
                
                // Destination WSOL account funding
                expectedFee.accountBalances += minimumTokenAccountBalance
                
                // top up
                instructions.append(
                    try Program.topUpSwapInstruction(
                        topUpSwap: swap,
                        userAuthorityAddress: userAuthorityAddress,
                        userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                        feePayerAddress: feePayerAddress
                    )
                )
                
                // close transit token account
                instructions.append(
                    SolanaSDK.TokenProgram.closeAccountInstruction(
                        account: transitTokenAccountAddress,
                        destination: feePayerAddress,
                        owner: feePayerAddress
                    )
                )
                
                // transfer
                instructions.append(
                    try Program.transferSolInstruction(
                        topUpSwap: swap,
                        userAuthorityAddress: userAuthorityAddress,
                        recipient: feePayerAddress,
                        lamports: feeAmount
                    )
                )
            default:
                fatalError("unsupported swap type")
            }
            
            var transaction = SolanaSDK.Transaction()
            transaction.instructions = instructions
            transaction.feePayer = feePayerAddress
            transaction.recentBlockhash = blockhash
            let transactionFee = try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignature)
            expectedFee.transaction = transactionFee
            
            return (transaction, expectedFee)
        }
    }
}

extension FeeRelayer.Relay: FeeRelayerRelayType {}

private extension OrcaSwap.Pool {
    func getSwapData(
        transferAuthorityPubkey: SolanaSDK.PublicKey,
        amountIn: UInt64,
        minAmountOut: UInt64
    ) -> FeeRelayer.Relay.DirectSwapData {
        .init(
            programId: swapProgramId.base58EncodedString,
            accountPubkey: account,
            authorityPubkey: authority,
            transferAuthorityPubkey: transferAuthorityPubkey.base58EncodedString,
            sourcePubkey: tokenAccountA,
            destinationPubkey: tokenAccountB,
            poolTokenMintPubkey: poolTokenMint,
            poolFeeAccountPubkey: feeAccount,
            amountIn: amountIn,
            minimumAmountOut: minAmountOut
        )
    }
}
