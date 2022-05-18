//
//  FeeRelayer.Relay+TopUp.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 07/02/2022.
//

import Foundation
import RxSwift
import SolanaSwift
import OrcaSwapSwift

extension FeeRelayer.Relay {
    /// Submits a signed top up swap transaction to the backend for processing
    func topUp(
        needsCreateUserRelayAddress: Bool,
        sourceToken: TokenInfo,
        targetAmount: UInt64,
        topUpPools: OrcaSwap.PoolsPair,
        expectedFee: UInt64
    ) -> Single<[String]> {
        let transitToken = try? getTransitToken(pools: topUpPools)
        return Single.zip(
            solanaClient.getRecentBlockhash(commitment: nil),
            updateFreeTransactionFeeLimit().andThen(.just(())),
            checkIfNeedsCreateTransitTokenAccount(transitToken: transitToken)
        )
            .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
            .flatMap { [weak self] recentBlockhash, _, needsCreateTransitTokenAccount in
                guard let self = self else {throw FeeRelayer.Error.unknown}
                guard let minimumRelayAccountBalance = self.cache.minimumRelayAccountBalance,
                      let minimumTokenAccountBalance = self.cache.minimumTokenAccountBalance,
                      let feePayerAddress = self.cache.feePayerAddress,
                      let lamportsPerSignature = self.cache.lamportsPerSignature,
                      let freeTransactionFeeLimit = self.cache.freeTransactionFeeLimit
                else { throw FeeRelayer.Error.relayInfoMissing }
                
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
                    transitTokenMintPubkey: try? SolanaSDK.PublicKey(string: transitToken?.mint),
                    transitTokenAccountAddress: try? SolanaSDK.PublicKey(string: transitToken?.address)
                )
                
                // STEP 4: send transaction
                let signatures = topUpTransaction.preparedTransaction.transaction.signatures
                guard signatures.count >= 2 else {throw FeeRelayer.Error.invalidSignature}
                
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
                            blockhash: recentBlockhash,
                            deviceType: self.deviceType,
                            buildNumber: self.buildNumber
                        )
                    ),
                    decodedTo: [String].self
                )
                    .retryWhenNeeded()
                    .do(onSuccess: { [weak self] _ in
                        guard let self = self else {return}
                        Logger.log(message: "Top up \(targetAmount) into \(self.userRelayAddress) completed", event: .info)
                        
                        self.markTransactionAsCompleted(freeFeeAmountUsed: lamportsPerSignature * 2)
                    }, onSubscribe: { [weak self] in
                        guard let self = self else {return}
                        Logger.log(message: "Top up \(targetAmount) into \(self.userRelayAddress) processing", event: .info)
                    })
            }
            .observe(on: MainScheduler.instance)
    }
    
    // MARK: - Helpers
    func prepareForTopUp(
        topUpAmount: SolanaSDK.Lamports,
        payingFeeToken: TokenInfo,
        relayAccountStatus: RelayAccountStatus,
        freeTransactionFeeLimit: FreeTransactionFeeLimit?,
        forceUsingTransitiveSwap: Bool = false // true for testing purpose only
    ) -> Single<TopUpPreparedParams?> {
        // form request
        orcaSwapClient
            .getTradablePoolsPairs(
                fromMint: payingFeeToken.mint,
                toMint: SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString
            )
            .map { [weak self] tradableTopUpPoolsPair in
                guard let self = self else { throw FeeRelayer.Error.unknown }
                // Get fee
                let expectedFee = try self.calculateExpectedFeeForTopUp(relayAccountStatus: relayAccountStatus, freeTransactionFeeLimit: freeTransactionFeeLimit)
                
                // Get pools for topping up
                let topUpPools: OrcaSwap.PoolsPair
                
                // force using transitive swap (for testing only)
                if forceUsingTransitiveSwap {
                    let pools = tradableTopUpPoolsPair.first(where: {$0.count == 2})!
                    topUpPools = pools
                }
                
                // prefer direct swap to transitive swap
                else if let directSwapPools = tradableTopUpPoolsPair.first(where: {$0.count == 1}) {
                    topUpPools = directSwapPools
                }
                
                // if direct swap is not available, use transitive swap
                else if let transitiveSwapPools = try self.orcaSwapClient.findBestPoolsPairForEstimatedAmount(topUpAmount, from: tradableTopUpPoolsPair)
                {
                    topUpPools = transitiveSwapPools
                }
                
                // no swap is available
                else {
                    throw FeeRelayer.Error.swapPoolsNotFound
                }
                
                // return needed amount and pools
                return .init(amount: topUpAmount, expectedFee: expectedFee, poolsPair: topUpPools)
            }
    }
    
    func calculateNeededTopUpAmount(
        expectedFee: SolanaSDK.FeeAmount,
        payingTokenMint: String?,
        freeTransactionFeeLimit: FreeTransactionFeeLimit,
        relayAccountStatus: RelayAccountStatus
    ) -> SolanaSDK.FeeAmount {
        var amount = calculateMinTopUpAmount(
            expectedFee: expectedFee,
            payingTokenMint: payingTokenMint,
            freeTransactionFeeLimit: freeTransactionFeeLimit,
            relayAccountStatus: relayAccountStatus
        )
        if amount.total > 0 && amount.total < 1000 {
            amount.transaction += 1000 - amount.total
        }
        print("needed topup amount: \(amount)")
        return amount
    }
    
    private func calculateMinTopUpAmount(
        expectedFee: SolanaSDK.FeeAmount,
        payingTokenMint: String?,
        freeTransactionFeeLimit: FreeTransactionFeeLimit,
        relayAccountStatus: RelayAccountStatus
    ) -> SolanaSDK.FeeAmount {
        var neededAmount = expectedFee
        
        // expected fees
        let expectedTopUpNetworkFee = 2 * (cache.lamportsPerSignature ?? 5000)
        let expectedTransactionNetworkFee = expectedFee.transaction
        
        // real fees
        var neededTopUpNetworkFee = expectedTopUpNetworkFee
        var neededTransactionNetworkFee = expectedTransactionNetworkFee
        
        // is Top up free
        if freeTransactionFeeLimit.isFreeTransactionFeeAvailable(transactionFee: expectedTopUpNetworkFee) {
            neededTopUpNetworkFee = 0
        }
        
        // is transaction free
        if freeTransactionFeeLimit.isFreeTransactionFeeAvailable(transactionFee: expectedTopUpNetworkFee + expectedTransactionNetworkFee, forNextTransaction: true)
        {
            neededTransactionNetworkFee = 0
        }
        
        neededAmount.transaction = neededTopUpNetworkFee + neededTransactionNetworkFee
        
        // transaction is totally free
        if neededAmount.total == 0 {
            return neededAmount
        }
        
        let neededAmountWithoutCheckingRelayAccount = neededAmount
        
        let minimumRelayAccountBalance = cache.minimumRelayAccountBalance ?? 890880
        
        // check if relay account current balance can cover part of needed amount
        if var relayAccountBalance = relayAccountStatus.balance {
            if relayAccountBalance < minimumRelayAccountBalance {
                neededAmount.transaction += minimumRelayAccountBalance - relayAccountBalance
            } else {
                relayAccountBalance -= minimumRelayAccountBalance
                
                // if relayAccountBalance has enough balance to cover transaction fee
                if relayAccountBalance >= neededAmount.transaction {
                    
                    neededAmount.transaction = 0
                    
                    // if relayAccountBlance has enough balance to cover accountBalances fee too
                    if relayAccountBalance - neededAmount.transaction >= neededAmount.accountBalances {
                        neededAmount.accountBalances = 0
                    }
                    
                    // Relay account balance can cover part of account creation fee
                    else {
                        neededAmount.accountBalances -= (relayAccountBalance - neededAmount.transaction)
                    }
                }
                // if not, relayAccountBalance can cover part of transaction fee
                else {
                    neededAmount.transaction -= relayAccountBalance
                }
            }
        } else {
            neededAmount.transaction += minimumRelayAccountBalance
        }
        
        // if relay account could not cover all fees and paying token is WSOL, the compensation will be done without the existense of relay account
        if neededAmount.total > 0, payingTokenMint == SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString {
            return neededAmountWithoutCheckingRelayAccount
        }
        
        return neededAmount
    }
    
    func calculateExpectedFeeForTopUp(
        relayAccountStatus: RelayAccountStatus,
        freeTransactionFeeLimit: FreeTransactionFeeLimit?
    ) throws -> UInt64 {
        // get cache
        guard let minimumRelayAccountBalance = cache.minimumRelayAccountBalance,
              let lamportsPerSignature = cache.lamportsPerSignature,
              let minimumTokenAccountBalance = cache.minimumTokenAccountBalance
        else {throw FeeRelayer.Error.relayInfoMissing}
        
        var expectedFee: UInt64 = 0
        if relayAccountStatus == .notYetCreated {
            expectedFee += minimumRelayAccountBalance
        }
        
        let transactionNetworkFee = 2 * lamportsPerSignature // feePayer, owner
        if freeTransactionFeeLimit?.isFreeTransactionFeeAvailable(transactionFee: transactionNetworkFee) == false {
            expectedFee += transactionNetworkFee
        }
        
        expectedFee += minimumTokenAccountBalance
        return expectedFee
    }
    
    /// Prepare transaction and expected fee for a given relay transaction
    private func prepareForTopUp(
        network: SolanaSDK.Network,
        sourceToken: TokenInfo,
        userAuthorityAddress: SolanaSDK.PublicKey,
        userRelayAddress: SolanaSDK.PublicKey,
        topUpPools: OrcaSwap.PoolsPair,
        targetAmount: UInt64,
        expectedFee: UInt64,
        blockhash: String,
        minimumRelayAccountBalance: UInt64,
        minimumTokenAccountBalance: UInt64,
        needsCreateUserRelayAccount: Bool,
        feePayerAddress: String,
        lamportsPerSignature: UInt64,
        freeTransactionFeeLimit: FreeTransactionFeeLimit?,
        needsCreateTransitTokenAccount: Bool?,
        transitTokenMintPubkey: SolanaSDK.PublicKey?,
        transitTokenAccountAddress: SolanaSDK.PublicKey?
    ) throws -> (swapData: FeeRelayerRelaySwapType, preparedTransaction: SolanaSDK.PreparedTransaction) {
        // assertion
        guard let userSourceTokenAccountAddress = try? SolanaSDK.PublicKey(string: sourceToken.address),
              let sourceTokenMintAddress = try? SolanaSDK.PublicKey(string: sourceToken.mint),
              let feePayerAddress = try? SolanaSDK.PublicKey(string: feePayerAddress),
              let associatedTokenAddress = try? SolanaSDK.PublicKey.associatedTokenAddress(walletAddress: feePayerAddress, tokenMintAddress: sourceTokenMintAddress),
              userSourceTokenAccountAddress != associatedTokenAddress
        else { throw FeeRelayer.Error.wrongAddress }
        
        // forming transaction and count fees
        var accountCreationFee: UInt64 = 0
        var instructions = [SolanaSDK.TransactionInstruction]()
        
        // create user relay account
        if needsCreateUserRelayAccount {
            instructions.append(
                SolanaSDK.SystemProgram.transferInstruction(
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
                    SolanaSDK.TokenProgram.approveInstruction(
                        tokenProgramId: .tokenProgramId,
                        account: userSourceTokenAccountAddress,
                        delegate: userTransferAuthority,
                        owner: userAuthorityAddress,
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
                    SolanaSDK.TokenProgram.approveInstruction(
                        tokenProgramId: .tokenProgramId,
                        account: userSourceTokenAccountAddress,
                        delegate: userTransferAuthority,
                        owner: userAuthorityAddress,
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
                        transitTokenMint: try SolanaSDK.PublicKey(string: swap.transitTokenMintPubkey),
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
        
        var transaction = SolanaSDK.Transaction()
        transaction.instructions = instructions
        transaction.feePayer = feePayerAddress
        transaction.recentBlockhash = blockhash
        
        // calculate fee first
        let expectedFee = SolanaSDK.FeeAmount(
            transaction: try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignature),
            accountBalances: accountCreationFee
        )
        
        // resign transaction
        var signers = [owner]
        if let tranferAuthority = swap.transferAuthorityAccount {
            signers.append(tranferAuthority)
        }
        try transaction.sign(signers: signers)
        
        if let decodedTransaction = transaction.jsonString {
            Logger.log(message: decodedTransaction, event: .info)
        }
        
        return (
            swapData: swap.swapData,
            preparedTransaction: .init(
                transaction: transaction,
                signers: signers,
                expectedFee: expectedFee
            )
        )
    }
}

private extension Array where Element == SolanaSDK.Transaction.Signature {
    func getSignature(index: Int) throws -> String {
        guard count > index else {throw FeeRelayer.Error.invalidSignature}
        guard let data = self[index].signature else {throw FeeRelayer.Error.invalidSignature}
        return Base58.encode(data)
    }
}
