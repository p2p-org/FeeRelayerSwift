// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SolanaSwift

/// A fee relayer configuration.
struct FeeRelayerConfiguration {
    let additionalPaybackFee: UInt64

    init(additionalPaybackFee: UInt64 = 0) {
        self.additionalPaybackFee = additionalPaybackFee
    }
}

/// The service that allows users to do gas-less transactions.
protocol FeeRelayer {
    var apiClient: SolanaAPIClient { get }
    
    var cache: Cache<String, Any>? { get }
    
    var account: Account { get throws }

    /// Fetch current usage status
    func getUsageStatus() async throws -> UsageStatus

    func topUpAndRelayTransaction(
        _ preparedTransaction: PreparedTransaction,
        fee payingFeeToken: Token?,
        config configuration: FeeRelayerConfiguration
    ) async throws -> TransactionID

    func topUpAndRelayTransaction(
        _ preparedTransaction: [PreparedTransaction],
        fee payingFeeToken: Token?,
        config configuration: FeeRelayerConfiguration
    ) async throws -> [TransactionID]
}

extension FeeRelayer {
    public func getRelayAccountStatus(_ address: String) async throws -> RelayAccountStatus {
        do {
            let ret: BufferInfo<EmptyInfo> = try await apiClient.getAccountInfo(account: address)!
            return .created(balance: ret.lamports)
        } catch let error  {
            if error.isEqualTo(.couldNotRetrieveAccountInfo) {
                return .notYetCreated
            }
            throw error
        }
    }
}

//topup
//func prepareForTopUp(
//    targetAmount: Lamports,
//    payingFeeToken: TokenInfo,
//    relayAccountStatus: RelayAccountStatus,
//    freeTransactionFeeLimit: FreeTransactionFeeLimit?,
//    checkIfBalanceHaveEnoughAmount: Bool = true,
//    forceUsingTransitiveSwap: Bool = false // true for testing purpose only
//) async throws -> TopUpPreparedParams? {
//    // form request
//    let tradableTopUpPoolsPair = try await orcaSwapClient.getTradablePoolsPairs(
//        fromMint: payingFeeToken.mint,
//        toMint: PublicKey.wrappedSOLMint.base58EncodedString
//    )
//
////        orcaSwapClient
////            .getTradablePoolsPairs(
////                fromMint: payingFeeToken.mint,
////                toMint: PublicKey.wrappedSOLMint.base58EncodedString
////            )
////            .map { [weak self] tradableTopUpPoolsPair in
////                guard let self = self else { throw FeeRelayer.Error.unknown }
//            // TOP UP
//            if checkIfBalanceHaveEnoughAmount,
//               let relayAccountBalance = relayAccountStatus.balance,
//               relayAccountBalance >= targetAmount
//            {
//                return nil
//            }
//            // STEP 2.2: Else
//            else {
//                // Get target amount for topping up
//                var targetAmount = targetAmount
//                if checkIfBalanceHaveEnoughAmount {
//                    targetAmount -= (relayAccountStatus.balance ?? 0)
//                }
//
//                // Get real amounts needed for topping up
//                let amounts = try self.calculateTopUpAmount(
//                    targetAmount: targetAmount,
//                    relayAccountStatus: relayAccountStatus,
//                    freeTransactionFeeLimit: freeTransactionFeeLimit
//                )
//                let topUpAmount = amounts.topUpAmount
//                let expectedFee = amounts.expectedFee
//
//                // Get pools for topping up
//                let topUpPools: PoolsPair
//
//                // force using transitive swap (for testing only)
//                if forceUsingTransitiveSwap {
//                    let pools = tradableTopUpPoolsPair.first(where: {$0.count == 2})!
//                    topUpPools = pools
//                }
//
//                // prefer direct swap to transitive swap
//                else if let directSwapPools = tradableTopUpPoolsPair.first(where: {$0.count == 1}) {
//                    topUpPools = directSwapPools
//                }
//
//                // if direct swap is not available, use transitive swap
//                else if let transitiveSwapPools = try self.orcaSwapClient.findBestPoolsPairForEstimatedAmount(topUpAmount, from: tradableTopUpPoolsPair)
//                {
//                    topUpPools = transitiveSwapPools
//                }
//
//                // no swap is available
//                else {
//                    throw FeeRelayer.Error.swapPoolsNotFound
//                }
//
//                // return needed amount and pools
//                return .init(amount: topUpAmount, expectedFee: expectedFee, poolsPair: topUpPools)
//            }
////            }
//}

//
///// Prepare transaction and expected fee for a given relay transaction
//private func prepareForTopUp(
//    network: Network,
//    sourceToken: TokenInfo,
//    userAuthorityAddress: PublicKey,
//    userRelayAddress: PublicKey,
//    topUpPools: PoolsPair,
//    targetAmount: UInt64,
//    expectedFee: UInt64,
//    blockhash: String,
//    minimumRelayAccountBalance: UInt64,
//    minimumTokenAccountBalance: UInt64,
//    needsCreateUserRelayAccount: Bool,
//    feePayerAddress: String,
//    lamportsPerSignature: UInt64,
//    freeTransactionFeeLimit: FreeTransactionFeeLimit?,
//    needsCreateTransitTokenAccount: Bool?,
//    transitTokenMintPubkey: PublicKey?,
//    transitTokenAccountAddress: PublicKey?
//) throws -> (swapData: FeeRelayerRelaySwapType, preparedTransaction: PreparedTransaction) {
//    // assertion
//    guard let userSourceTokenAccountAddress = try? PublicKey(string: sourceToken.address),
//          let sourceTokenMintAddress = try? PublicKey(string: sourceToken.mint),
//          let feePayerAddress = try? PublicKey(string: feePayerAddress),
//          let associatedTokenAddress = try? PublicKey.associatedTokenAddress(walletAddress: feePayerAddress, tokenMintAddress: sourceTokenMintAddress),
//          userSourceTokenAccountAddress != associatedTokenAddress
//    else { throw FeeRelayer.Error.wrongAddress }
//    
//    // forming transaction and count fees
//    var accountCreationFee: UInt64 = 0
//    var instructions = [TransactionInstruction]()
//    
//    // create user relay account
//    if needsCreateUserRelayAccount {
//        instructions.append(
//            SystemProgram.transferInstruction(
//                from: feePayerAddress,
//                to: userRelayAddress,
//                lamports: minimumRelayAccountBalance
//            )
//        )
//        accountCreationFee += minimumRelayAccountBalance
//    }
//    
//    // top up swap
//    let swap = try prepareSwapData(
//        network: network,
//        pools: topUpPools,
//        inputAmount: nil,
//        minAmountOut: targetAmount,
//        slippage: 0.01,
//        transitTokenMintPubkey: transitTokenMintPubkey,
//        needsCreateTransitTokenAccount: needsCreateTransitTokenAccount == true
//    )
//    let userTransferAuthority = swap.transferAuthorityAccount?.publicKey
//    
//    switch swap.swapData {
//    case let swap as DirectSwapData:
//        accountCreationFee += minimumTokenAccountBalance
//        // approve
//        if let userTransferAuthority = userTransferAuthority {
//            instructions.append(
//                TokenProgram.approveInstruction(account: userSourceTokenAccountAddress,
//                                                delegate: userTransferAuthority,
//                                                owner: userAuthorityAddress,
//                                                multiSigners: [],
//                                                amount: swap.amountIn)
////                    TokenProgram.approveInstruction(
////                        tokenProgramId: .tokenProgramId,
////                        account: userSourceTokenAccountAddress,
////                        delegate: userTransferAuthority,
////                        owner: userAuthorityAddress,
////                        amount: swap.amountIn
////                    )
//            )
//        }
//        
//        // top up
//        instructions.append(
//            try Program.topUpSwapInstruction(
//                network: network,
//                topUpSwap: swap,
//                userAuthorityAddress: userAuthorityAddress,
//                userSourceTokenAccountAddress: userSourceTokenAccountAddress,
//                feePayerAddress: feePayerAddress
//            )
//        )
//    case let swap as TransitiveSwapData:
//        // approve
//        if let userTransferAuthority = userTransferAuthority {
//            instructions.append(
//                TokenProgram.approveInstruction(account: userSourceTokenAccountAddress,
//                                                delegate: userTransferAuthority,
//                                                owner: userAuthorityAddress,
//                                                multiSigners: [],
//                                                amount: swap.from.amountIn)
////                    TokenProgram.approveInstruction(
////                        tokenProgramId: .tokenProgramId,
////                        account: userSourceTokenAccountAddress,
////                        delegate: userTransferAuthority,
////                        owner: userAuthorityAddress,
////                        amount: swap.from.amountIn
////                    )
//            )
//        }
//        
//        // create transit token account
//        if needsCreateTransitTokenAccount == true, let transitTokenAccountAddress = transitTokenAccountAddress {
//            instructions.append(
//                try Program.createTransitTokenAccountInstruction(
//                    feePayer: feePayerAddress,
//                    userAuthority: userAuthorityAddress,
//                    transitTokenAccount: transitTokenAccountAddress,
//                    transitTokenMint: try PublicKey(string: swap.transitTokenMintPubkey),
//                    network: network
//                )
//            )
//        }
//        
//        // Destination WSOL account funding
//        accountCreationFee += minimumTokenAccountBalance
//        
//        // top up
//        instructions.append(
//            try Program.topUpSwapInstruction(
//                network: network,
//                topUpSwap: swap,
//                userAuthorityAddress: userAuthorityAddress,
//                userSourceTokenAccountAddress: userSourceTokenAccountAddress,
//                feePayerAddress: feePayerAddress
//            )
//        )
//    default:
//        fatalError("unsupported swap type")
//    }
//    
//    // transfer
//    instructions.append(
//        try Program.transferSolInstruction(
//            userAuthorityAddress: userAuthorityAddress,
//            recipient: feePayerAddress,
//            lamports: expectedFee,
//            network: network
//        )
//    )
//    
//    var transaction = Transaction()
//    transaction.instructions = instructions
//    transaction.feePayer = feePayerAddress
//    transaction.recentBlockhash = blockhash
//    
//    // calculate fee first
//    let expectedFee = FeeAmount(
//        transaction: try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignature),
//        accountBalances: accountCreationFee
//    )
//    
//    // resign transaction
//    var signers = [owner]
//    if let tranferAuthority = swap.transferAuthorityAccount {
//        signers.append(tranferAuthority)
//    }
//    try transaction.sign(signers: signers)
//    
//    if let decodedTransaction = transaction.jsonString {
////            Logger.log(message: decodedTransaction, event: .info)
//    }
//    
//    return (
//        swapData: swap.swapData,
//        preparedTransaction: .init(
//            transaction: transaction,
//            signers: signers,
//            expectedFee: expectedFee
//        )
//    )
//}



/// Submits a signed top up swap transaction to the backend for processing
//func topUp(
//    needsCreateUserRelayAddress: Bool,
//    sourceToken: TokenInfo,
//    targetAmount: UInt64,
//    topUpPools: PoolsPair,
//    expectedFee: UInt64
//) -> [String] {
//    return []
//        let transitToken = try? getTransitToken(pools: topUpPools)
//        return Single.zip(
//            solanaClient.getRecentBlockhash(commitment: nil),
//            updateFreeTransactionFeeLimit().andThen(.just(())),
//            checkIfNeedsCreateTransitTokenAccount(transitToken: transitToken)
//        )
//            .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
//            .flatMap { [weak self] recentBlockhash, _, needsCreateTransitTokenAccount in
//                guard let self = self else {throw FeeRelayer.Error.unknown}
//                guard let minimumRelayAccountBalance = self.cache.minimumRelayAccountBalance,
//                      let minimumTokenAccountBalance = self.cache.minimumTokenAccountBalance,
//                      let feePayerAddress = self.cache.feePayerAddress,
//                      let lamportsPerSignature = self.cache.lamportsPerSignature,
//                      let freeTransactionFeeLimit = self.cache.freeTransactionFeeLimit
//                else { throw FeeRelayer.Error.relayInfoMissing }
//
//                // STEP 3: prepare for topUp
//                let topUpTransaction = try self.prepareForTopUp(
//                    network: self.solanaClient.endpoint.network,
//                    sourceToken: sourceToken,
//                    userAuthorityAddress: self.owner.publicKey,
//                    userRelayAddress: self.userRelayAddress,
//                    topUpPools: topUpPools,
//                    targetAmount: targetAmount,
//                    expectedFee: expectedFee,
//                    blockhash: recentBlockhash,
//                    minimumRelayAccountBalance: minimumRelayAccountBalance,
//                    minimumTokenAccountBalance: minimumTokenAccountBalance,
//                    needsCreateUserRelayAccount: needsCreateUserRelayAddress,
//                    feePayerAddress: feePayerAddress,
//                    lamportsPerSignature: lamportsPerSignature,
//                    freeTransactionFeeLimit: freeTransactionFeeLimit,
//                    needsCreateTransitTokenAccount: needsCreateTransitTokenAccount,
//                    transitTokenMintPubkey: try? PublicKey(string: transitToken?.mint),
//                    transitTokenAccountAddress: try? PublicKey(string: transitToken?.address)
//                )
//
//                // STEP 4: send transaction
//                let signatures = topUpTransaction.preparedTransaction.transaction.signatures
//                guard signatures.count >= 2 else {throw FeeRelayer.Error.invalidSignature}
//
//                // the second signature is the owner's signature
//                let ownerSignature = try signatures.getSignature(index: 1)
//
//                // the third signature (optional) is the transferAuthority's signature
//                let transferAuthoritySignature = try? signatures.getSignature(index: 2)
//
//                let topUpSignatures = SwapTransactionSignatures(
//                    userAuthoritySignature: ownerSignature,
//                    transferAuthoritySignature: transferAuthoritySignature
//                )
//
//                return self.apiClient.sendTransaction(
//                    .relayTopUpWithSwap(
//                        .init(
//                            userSourceTokenAccountPubkey: sourceToken.address,
//                            sourceTokenMintPubkey: sourceToken.mint,
//                            userAuthorityPubkey: self.owner.publicKey.base58EncodedString,
//                            topUpSwap: .init(topUpTransaction.swapData),
//                            feeAmount: expectedFee,
//                            signatures: topUpSignatures,
//                            blockhash: recentBlockhash
//                        )
//                    ),
//                    decodedTo: [String].self
//                )
//                    .retryWhenNeeded()
//                    .do(onSuccess: { [weak self] _ in
//                        guard let self = self else {return}
//                        Logger.log(message: "Top up \(targetAmount) into \(self.userRelayAddress) completed", event: .info)
//
//                        self.markTransactionAsCompleted(freeFeeAmountUsed: lamportsPerSignature * 2)
//                    }, onSubscribe: { [weak self] in
//                        guard let self = self else {return}
//                        Logger.log(message: "Top up \(targetAmount) into \(self.userRelayAddress) processing", event: .info)
//                    })
//            }
//            .observe(on: MainScheduler.instance)
//    }
