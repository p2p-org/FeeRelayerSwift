// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

class FeeRelayerService: FeeRelayer {
    private(set) var solanaApiClient: SolanaAPIClient
    private(set) var orcaSwapAPIClient: OrcaSwapAPIClient
    private(set) var cache: Cache<CacheKey, Any>?
    private(set) var account: Account

    private let feeCalculator: FeeRelayerCalculator

    init(
        account: Account,
        solanaApiClient: SolanaAPIClient,
        orcaSwapAPIClient: OrcaSwapAPIClient,
        feeCalculator: FeeRelayerCalculator,
        cache: Cache<CacheKey, Any>? = nil
    ) {
        self.account = account
        self.solanaApiClient = solanaApiClient
        self.orcaSwapAPIClient = orcaSwapAPIClient
        self.cache = cache
        self.feeCalculator = feeCalculator
    }

    func getUsageStatus() async throws -> UsageStatus {
        fatalError("getUsageStatus() has not been implemented")
    }

    func topUpAndRelayTransaction(
        _: PreparedTransaction,
        fee _: TokenAccount?,
        config _: FeeRelayerConfiguration
    ) async throws -> TransactionID {
        fatalError("topUpAndRelayTransaction(_:fee:config:) has not been implemented")
    }

    func topUpAndRelayTransaction(
        _: [PreparedTransaction],
        fee _: TokenAccount?,
        config _: FeeRelayerConfiguration
    ) async throws -> [TransactionID] { fatalError("topUpAndRelayTransaction(_:fee:config:) has not been implemented") }

    internal func getMinimumTokenAccountBalance() async -> UInt64 {
        // Return from cache
        // ...

        // Return from api client
        0
    }

    func prepareForTopUp(
        targetAmount _: Lamports,
        payingFeeToken _: TokenAccount,
        relayAccountStatus _: RelayAccountStatus,
        freeTransactionFeeLimit: UsageStatus?,
        checkIfBalanceHaveEnoughAmount _: Bool = true,
        forceUsingTransitiveSwap _: Bool = false // true for testing purpose only
    ) async throws -> TopUpPreparedParams? {
         // form request
//         let tradableTopUpPoolsPair = try await orcaSwapAPIClient.getTradablePoolsPairs(
//            fromMint: payingFeeToken.mint,
//            toMint: PublicKey.wrappedSOLMint.base58EncodedString
//         )
        fatalError()
//         // TOP UP
//         if checkIfBalanceHaveEnoughAmount,
//            let relayAccountBalance = relayAccountStatus.balance,
//            relayAccountBalance >= targetAmount  {
//             return nil
//         }
//         // STEP 2.2: Else
//         else {
//             // Get target amount for topping up
//             var targetAmount = targetAmount
//             if checkIfBalanceHaveEnoughAmount {
//                 targetAmount -= (relayAccountStatus.balance ?? 0)
//             }
//
//             // Get real amounts needed for topping up
//             let amounts = try self.calculateTopUpAmount(
//                 targetAmount: targetAmount,
//                 relayAccountStatus: relayAccountStatus,
//                 freeTransactionFeeLimit: freeTransactionFeeLimit
//             )
//             let topUpAmount = amounts.topUpAmount
//             let expectedFee = amounts.expectedFee
//
//             // Get pools for topping up
//             let topUpPools: PoolsPair
//
//             // force using transitive swap (for testing only)
//             if forceUsingTransitiveSwap {
//                 let pools = tradableTopUpPoolsPair.first(where: { $0.count == 2 })!
//                 topUpPools = pools
//             }
//
//             // prefer direct swap to transitive swap
//             else if let directSwapPools = tradableTopUpPoolsPair.first(where: { $0.count == 1 }) {
//                 topUpPools = directSwapPools
//             }
//
//             // if direct swap is not available, use transitive swap
//             else if let transitiveSwapPools = try orcaSwapAPIClient.findBestPoolsPairForEstimatedAmount(topUpAmount, from: tradableTopUpPoolsPair) {
//                 topUpPools = transitiveSwapPools
//             }
//
//             // no swap is available
//             else {
//                 throw FeeRelayerError.swapPoolsNotFound
//             }
//
//             // return needed amount and pools
//             return .init(amount: topUpAmount, expectedFee: expectedFee, poolsPair: topUpPools)
    }
}

/// Prepare transaction and expected fee for a given relay transaction
private func prepareForTopUp(
    network _: Network,
    sourceToken _: TokenInfo,
    userAuthorityAddress _: PublicKey,
    userRelayAddress _: PublicKey,
    topUpPools _: PoolsPair,
    targetAmount _: UInt64,
    expectedFee _: UInt64,
    blockhash _: String,
    minimumRelayAccountBalance _: UInt64,
    minimumTokenAccountBalance _: UInt64,
    needsCreateUserRelayAccount _: Bool,
    feePayerAddress _: String,
    lamportsPerSignature _: UInt64,
    freeTransactionFeeLimit _: FreeTransactionFeeLimit?,
    needsCreateTransitTokenAccount _: Bool?,
    transitTokenMintPubkey _: PublicKey?,
    transitTokenAccountAddress _: PublicKey?
) async throws -> (swapData: FeeRelayerRelaySwapType, preparedTransaction: PreparedTransaction) {
    fatalError("topUpAndRelayTransaction(_:fee:config:) has not been implemented")
    /*
             // assertion
             guard let userSourceTokenAccountAddress = try? PublicKey(string: sourceToken.address),
                   let sourceTokenMintAddress = try? PublicKey(string: sourceToken.mint),
                   let feePayerAddress = try? PublicKey(string: feePayerAddress),
                   let associatedTokenAddress = try? PublicKey.associatedTokenAddress(
                       walletAddress: feePayerAddress,
                       tokenMintAddress: sourceTokenMintAddress
                   ),
                   userSourceTokenAccountAddress != associatedTokenAddress
             else { throw FeeRelayer.Error.wrongAddress }

             // forming transaction and count fees
             var accountCreationFee: UInt64 = 0
             var instructions = [TransactionInstruction]()

             // create user relay account
             if needsCreateUserRelayAccount {
                 instructions.append(
                     SystemProgram.transferInstruction(
                         from: feePayerAddress,
                         to: userRelayAddress,
                         lamports: minimumRelayAccountBalance
                     )
                 )
                 accountCreationFee += minimumRelayAccountBalance
             }

             // top up swap
             let swap = try prepareSwapData(
                 network: network,
                 pools: topUpPools,
                 inputAmount: nil,
                 minAmountOut: targetAmount,
                 slippage: 0.01,
                 transitTokenMintPubkey: transitTokenMintPubkey,
                 needsCreateTransitTokenAccount: needsCreateTransitTokenAccount == true
             )
             let userTransferAuthority = swap.transferAuthorityAccount?.publicKey

             switch swap.swapData {
             case let swap as DirectSwapData:
                 accountCreationFee += minimumTokenAccountBalance
                 // approve
                 if let userTransferAuthority = userTransferAuthority {
                     instructions.append(
                         TokenProgram.approveInstruction(
                             account: userSourceTokenAccountAddress,
                             delegate: userTransferAuthority,
                             owner: userAuthorityAddress,
                             multiSigners: [],
                             amount: swap.amountIn
                         )
                     )
                 }

                 // top up
                 instructions.append(
                     try Program.topUpSwapInstruction(
                         network: network,
                         topUpSwap: swap,
                         userAuthorityAddress: userAuthorityAddress,
                         userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                         feePayerAddress: feePayerAddress
                     )
                 )
             case let swap as TransitiveSwapData:
                 // approve
                 if let userTransferAuthority = userTransferAuthority {
                     instructions.append(
                         TokenProgram.approveInstruction(
                             account: userSourceTokenAccountAddress,
                             delegate: userTransferAuthority,
                             owner: userAuthorityAddress,
                             multiSigners: [],
                             amount: swap.from.amountIn
                         )
                     )
                 }

                 // create transit token account
                 if needsCreateTransitTokenAccount == true, let transitTokenAccountAddress = transitTokenAccountAddress {
                     instructions.append(
                         try Program.createTransitTokenAccountInstruction(
                             feePayer: feePayerAddress,
                             userAuthority: userAuthorityAddress,
                             transitTokenAccount: transitTokenAccountAddress,
                             transitTokenMint: try PublicKey(string: swap.transitTokenMintPubkey),
                             network: network
                         )
                     )
                 }

                 // Destination WSOL account funding
                 accountCreationFee += minimumTokenAccountBalance

                 // top up
                 instructions.append(
                     try Program.topUpSwapInstruction(
                         network: network,
                         topUpSwap: swap,
                         userAuthorityAddress: userAuthorityAddress,
                         userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                         feePayerAddress: feePayerAddress
                     )
                 )
             default:
                 fatalError("unsupported swap type")
             }

             // transfer
             instructions.append(
                 try Program.transferSolInstruction(
                     userAuthorityAddress: userAuthorityAddress,
                     recipient: feePayerAddress,
                     lamports: expectedFee,
                     network: network
                 )
             )

             var transaction = Transaction()
             transaction.instructions = instructions
             transaction.feePayer = feePayerAddress
             transaction.recentBlockhash = blockhash

             // calculate fee first
             let expectedFee = FeeAmount(
                 transaction: try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignature),
                 accountBalances: accountCreationFee
             )

             // resign transaction
             var signers = [owner]
             if let tranferAuthority = swap.transferAuthorityAccount {
                 signers.append(tranferAuthority)
             }
             try transaction.sign(signers: signers)

     //        if let decodedTransaction = transaction.jsonString {
         //            Logger.log(message: decodedTransaction, event: .info)
     //        }

             return (
                 swapData: swap.swapData,
                 preparedTransaction: .init(
                     transaction: transaction,
                     signers: signers,
                     expectedFee: expectedFee
                 )
             )

              */

    // Submits a signed top up swap transaction to the backend for processing
    func topUp(
        needsCreateUserRelayAddress _: Bool,
        sourceToken _: TokenInfo,
        targetAmount _: UInt64,
        topUpPools _: PoolsPair,
        expectedFee _: UInt64
    ) async throws -> [String] {
        fatalError("topUpAndRelayTransaction(_:fee:config:) has not been implemented")
        /*
         let transitToken = try? getTransitToken(pools: topUpPools)
         let recentBlockhash: String
         do {
             let recentBlockhash = try await solanaApiClient.getRecentBlockhash(commitment: nil)
             _ = updateFreeTransactionFeeLimit()
             let needsCreateTransitTokenAccount = checkIfNeedsCreateTransitTokenAccount(transitToken: transitToken)
         } catch {
             throw FeeRelayerError.relayInfoMissing
         }

         // STEP 3: prepare for topUp
         let topUpTransaction = try self.prepareForTopUp(
             network: self.solanaClient.endpoint.network,
             sourceToken: sourceToken,
             userAuthorityAddress: self.owner.publicKey,
             userRelayAddress: self.userRelayAddress,
             topUpPools: topUpPools,
             targetAmount: targetAmount,
             expectedFee: expectedFee,
             blockhash: recentBlockhash,
             minimumRelayAccountBalance: minimumRelayAccountBalance,
             minimumTokenAccountBalance: minimumTokenAccountBalance,
             needsCreateUserRelayAccount: needsCreateUserRelayAddress,
             feePayerAddress: feePayerAddress,
             lamportsPerSignature: lamportsPerSignature,
             freeTransactionFeeLimit: freeTransactionFeeLimit,
             needsCreateTransitTokenAccount: needsCreateTransitTokenAccount,
             transitTokenMintPubkey: try? PublicKey(string: transitToken?.mint),
             transitTokenAccountAddress: try? PublicKey(string: transitToken?.address)
         )

         // STEP 4: send transaction
         let signatures = topUpTransaction.preparedTransaction.transaction.signatures
         guard signatures.count >= 2 else { throw FeeRelayerError.invalidSignature }

         // the second signature is the owner's signature
         let ownerSignature = try signatures.getSignature(index: 1)

         // the third signature (optional) is the transferAuthority's signature
         let transferAuthoritySignature = try? signatures.getSignature(index: 2)

         let topUpSignatures = SwapTransactionSignatures(
             userAuthoritySignature: ownerSignature,
             transferAuthoritySignature: transferAuthoritySignature
         )
         return self.apiClient.sendTransaction(
                     .relayTopUpWithSwap(
                         .init(
                             userSourceTokenAccountPubkey: sourceToken.address,
                             sourceTokenMintPubkey: sourceToken.mint,
                             userAuthorityPubkey: self.owner.publicKey.base58EncodedString,
                             topUpSwap: .init(topUpTransaction.swapData),
                             feeAmount: expectedFee,
                             signatures: topUpSignatures,
                             blockhash: recentBlockhash
                         )
                     )) as [String]
          */
    }
}

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

enum CacheKey: String {
    case minimumTokenAccountBalance
    case minimumRelayAccountBalance
    case lamportsPerSignature
    case relayAccountStatus
    case preparedParams
    case usageStatus
    case feePayerAddress
}
