//
//  FeeRelayer.Relay+Swap.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 07/02/2022.
//

import Foundation
import RxSwift
import SolanaSwift
import OrcaSwapSwift

extension FeeRelayer.Relay {
    /// Prepare swap transaction for relay
    public func prepareSwapTransaction(
        sourceToken: TokenInfo,
        destinationTokenMint: String,
        destinationAddress: String?,
        payingFeeToken: TokenInfo?,
        swapPools: PoolsPair,
        inputAmount: UInt64,
        slippage: Double
    ) async throws -> Single<(transactions: [PreparedTransaction], additionalPaybackFee: UInt64)> {
        let transitToken = try? getTransitToken(pools: swapPools)
        // get fresh data by ignoring cache
        try await updateRelayAccountStatus()
        try await updateFreeTransactionFeeLimit()
        let preparedParams = try await prepareForTopUpAndSwap(
            sourceToken: sourceToken,
            destinationTokenMint: destinationTokenMint,
            destinationAddress: destinationAddress,
            payingFeeToken: payingFeeToken,
            swapPools: swapPools,
            reuseCache: false
        )
        
        return Single.zip(
//            Completable.zip(
//                updateRelayAccountStatus(),
//                updateFreeTransactionFeeLimit()
//            )
//                .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
//                .andThen(Single<TopUpAndActionPreparedParams>.deferred { [weak self] in
//                    guard let self = self else { throw FeeRelayer.Error.unknown }
//                    return try await self.prepareForTopUpAndSwap(
//                        sourceToken: sourceToken,
//                        destinationTokenMint: destinationTokenMint,
//                        destinationAddress: destinationAddress,
//                        payingFeeToken: payingFeeToken,
//                        swapPools: swapPools,
//                        reuseCache: false
//                    )
//                }),
            getFixedDestination(destinationTokenMint: destinationTokenMint, destinationAddress: destinationAddress),
            solanaClient.getRecentBlockhash(commitment: nil),
            checkIfNeedsCreateTransitTokenAccount(transitToken: transitToken)
        )
            .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
            .map { [weak self] destination, recentBlockhash, needsCreateTransitTokenAccount in
                guard let self = self else { throw FeeRelayer.Error.unknown }
                // get needed info
                guard let minimumTokenAccountBalance = self.cache.minimumTokenAccountBalance,
                      let feePayerAddress = self.cache.feePayerAddress,
                      let lamportsPerSignature = self.cache.lamportsPerSignature
                else {
                    throw FeeRelayer.Error.relayInfoMissing
                }
                
                let destinationToken = destination.destinationToken
                let userDestinationAccountOwnerAddress = destination.userDestinationAccountOwnerAddress
                let needsCreateDestinationTokenAccount = destination.needsCreateDestinationTokenAccount

                let swapFeesAndPools = preparedParams.actionFeesAndPools
                let swappingFee = swapFeesAndPools.fee.total
                let swapPools = swapFeesAndPools.poolsPair
                
                return try self.prepareSwapTransaction(
                    network: self.solanaClient.endpoint.network,
                    sourceToken: sourceToken,
                    destinationToken: destinationToken,
                    userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress?.base58EncodedString,
                    pools: swapPools,
                    inputAmount: inputAmount,
                    slippage: slippage,
                    feeAmount: swappingFee,
                    blockhash: recentBlockhash,
                    minimumTokenAccountBalance: minimumTokenAccountBalance,
                    needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount,
                    feePayerAddress: feePayerAddress,
                    lamportsPerSignature: lamportsPerSignature,
                    needsCreateTransitTokenAccount: needsCreateTransitTokenAccount,
                    transitTokenMintPubkey: try? PublicKey(string: transitToken?.mint),
                    transitTokenAccountAddress: try? PublicKey(string: transitToken?.address)
                )
            }
            .observe(on: MainScheduler.instance)
    }
    
    // MARK: - Helpers
    public func calculateSwappingNetworkFees(
        swapPools: PoolsPair?,
        sourceTokenMint: String,
        destinationTokenMint: String,
        destinationAddress: String?
    ) -> Single<FeeAmount> {
        getFixedDestination(destinationTokenMint: destinationTokenMint, destinationAddress: destinationAddress)
            .map { [weak self] destination in
                guard let self = self,
                      let lamportsPerSignature = self.cache.lamportsPerSignature,
                      let minimumTokenAccountBalance = self.cache.minimumTokenAccountBalance
                else {throw FeeRelayer.Error.relayInfoMissing}
                
                let needsCreateDestinationTokenAccount = destination.needsCreateDestinationTokenAccount
                
                var expectedFee = FeeAmount.zero
                
                // fee for payer's signature
                expectedFee.transaction += lamportsPerSignature
                
                // fee for owner's signature
                expectedFee.transaction += lamportsPerSignature
                
                // when source token is native SOL
                if sourceTokenMint == PublicKey.wrappedSOLMint.base58EncodedString {
                    // WSOL's signature
                    expectedFee.transaction += lamportsPerSignature
                }
                
                // when needed to create destination
                if needsCreateDestinationTokenAccount && destinationTokenMint != PublicKey.wrappedSOLMint.base58EncodedString {
                    expectedFee.accountBalances += minimumTokenAccountBalance
                }
                
                // when destination is native SOL
                if destinationTokenMint == PublicKey.wrappedSOLMint.base58EncodedString {
                    expectedFee.transaction += lamportsPerSignature
                }
                
                // in transitive swap, there will be situation when swapping from SOL -> SPL that needs spliting transaction to 2 transactions
                if swapPools?.count == 2 &&
                    sourceTokenMint == PublicKey.wrappedSOLMint.base58EncodedString &&
                    destinationAddress == nil
                {
                    expectedFee.transaction += lamportsPerSignature * 2
                }
                
                return expectedFee
            }
    }
    
    private func prepareSwapTransaction(
        network: Network,
        sourceToken: TokenInfo,
        destinationToken: TokenInfo,
        userDestinationAccountOwnerAddress: String?,
        pools: PoolsPair,
        inputAmount: UInt64,
        slippage: Double,
        feeAmount: UInt64,
        blockhash: String,
        minimumTokenAccountBalance: UInt64,
        needsCreateDestinationTokenAccount: Bool,
        feePayerAddress: String,
        lamportsPerSignature: UInt64,
        needsCreateTransitTokenAccount: Bool?,
        transitTokenMintPubkey: PublicKey?,
        transitTokenAccountAddress: PublicKey?
    ) throws -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
        // assertion
        let userAuthorityAddress = owner.publicKey
        guard var userSourceTokenAccountAddress = try? PublicKey(string: sourceToken.address),
              let sourceTokenMintAddress = try? PublicKey(string: sourceToken.mint),
              let feePayerAddress = try? PublicKey(string: feePayerAddress),
              let associatedTokenAddress = try? PublicKey.associatedTokenAddress(walletAddress: feePayerAddress, tokenMintAddress: sourceTokenMintAddress),
              userSourceTokenAccountAddress != associatedTokenAddress
        else { throw FeeRelayer.Error.wrongAddress }
        let destinationTokenMintAddress = try PublicKey(string: destinationToken.mint)
        
        // forming transaction and count fees
        var additionalTransaction: PreparedTransaction?
        var accountCreationFee: Lamports = 0
        var instructions = [TransactionInstruction]()
        var additionalPaybackFee: UInt64 = 0
        
        // check source
        var sourceWSOLNewAccount: Account?
        if sourceToken.mint == PublicKey.wrappedSOLMint.base58EncodedString {
            sourceWSOLNewAccount = try Account(network: network)
            instructions.append(contentsOf: [
                SystemProgram.transferInstruction(
                    from: userAuthorityAddress,
                    to: feePayerAddress,
                    lamports: inputAmount
                ),
                SystemProgram.createAccountInstruction(from: feePayerAddress,
                                                       toNewPubkey: sourceWSOLNewAccount!.publicKey,
                                                       lamports: minimumTokenAccountBalance + inputAmount,
                                                       space: AccountInfo.BUFFER_LENGTH,
                                                       programId: TokenProgram.id),
//                SystemProgram.createAccountInstruction(
//                    from: feePayerAddress,
//                    toNewPubkey: sourceWSOLNewAccount!.publicKey,
//                    lamports: minimumTokenAccountBalance + inputAmount
//                ),
                TokenProgram.initializeAccountInstruction(
                    account: sourceWSOLNewAccount!.publicKey,
                    mint: .wrappedSOLMint,
                    owner: userAuthorityAddress
                )
            ])
            userSourceTokenAccountAddress = sourceWSOLNewAccount!.publicKey
            additionalPaybackFee += minimumTokenAccountBalance
        }
        
        // check destination
        var destinationNewAccount: Account?
        var userDestinationTokenAccountAddress = destinationToken.address
        if needsCreateDestinationTokenAccount {
            if destinationTokenMintAddress == .wrappedSOLMint {
                // For native solana, create and initialize WSOL
                destinationNewAccount = try Account(network: network)
                instructions.append(contentsOf: [
                    SystemProgram.createAccountInstruction(from: feePayerAddress,
                                                           toNewPubkey: destinationNewAccount!.publicKey,
                                                           lamports: minimumTokenAccountBalance,
                                                           space: AccountInfo.BUFFER_LENGTH,
                                                           programId: TokenProgram.id),
                    TokenProgram.initializeAccountInstruction(
                        account: destinationNewAccount!.publicKey,
                        mint: destinationTokenMintAddress,
                        owner: userAuthorityAddress
                    )
                ])
                userDestinationTokenAccountAddress = destinationNewAccount!.publicKey.base58EncodedString
                accountCreationFee += minimumTokenAccountBalance
            } else {
                // For other token, create associated token address
                let associatedAddress = try PublicKey.associatedTokenAddress(
                    walletAddress: userAuthorityAddress,
                    tokenMintAddress: destinationTokenMintAddress
                )
                
//                let instruction = AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
//                    mint: destinationTokenMintAddress,
//                    associatedAccount: associatedAddress,
//                    owner: userAuthorityAddress,
//                    payer: feePayerAddress
//                )
                let instruction = try AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
                    mint: destinationTokenMintAddress,
                    owner: userAuthorityAddress,
                    payer: feePayerAddress
                )
                
                // SPECIAL CASE WHEN WE SWAP FROM SOL TO NON-CREATED SPL TOKEN, THEN WE NEEDS ADDITIONAL TRANSACTION BECAUSE TRANSACTION IS TOO LARGE
                if sourceWSOLNewAccount != nil {
                    additionalTransaction = try prepareTransaction(
                        instructions: [instruction],
                        signers: [owner],
                        blockhash: blockhash,
                        feePayerAddress: feePayerAddress,
                        accountCreationFee: minimumTokenAccountBalance,
                        lamportsPerSignature: lamportsPerSignature
                    )
                } else {
                    instructions.append(instruction)
                    accountCreationFee += minimumTokenAccountBalance
                }
                userDestinationTokenAccountAddress = associatedAddress.base58EncodedString
            }
        }
        
        // swap
        let swap = try prepareSwapData(network: network, pools: pools, inputAmount: inputAmount, minAmountOut: nil, slippage: slippage, transitTokenMintPubkey: transitTokenMintPubkey, needsCreateTransitTokenAccount: needsCreateTransitTokenAccount == true)
        let userTransferAuthority = swap.transferAuthorityAccount?.publicKey
        
        switch swap.swapData {
        case let swap as DirectSwapData:
            guard let pool = pools.first else {throw FeeRelayer.Error.swapPoolsNotFound}
            
            // approve
            if let userTransferAuthority = userTransferAuthority {
                instructions.append(
                    TokenProgram.approveInstruction(account: userSourceTokenAccountAddress,
                                                    delegate: userTransferAuthority,
                                                    owner: userAuthorityAddress,
                                                    multiSigners: [],
                                                    amount: swap.amountIn)
                )
            }
            
            // swap
            instructions.append(
                try pool.createSwapInstruction(
                    userTransferAuthorityPubkey: userTransferAuthority ?? userAuthorityAddress,
                    sourceTokenAddress: userSourceTokenAccountAddress,
                    destinationTokenAddress: try PublicKey(string: userDestinationTokenAccountAddress),
                    amountIn: swap.amountIn,
                    minAmountOut: swap.minimumAmountOut
                )
            )
        case let swap as TransitiveSwapData:
            // approve
            if let userTransferAuthority = userTransferAuthority {
                instructions.append(
                    TokenProgram.approveInstruction(account: userSourceTokenAccountAddress,
                                                    delegate: userTransferAuthority,
                                                    owner: userAuthorityAddress,
                                                    multiSigners: [],
                                                    amount: swap.from.amountIn)
                )
            }
            
            // create transit token account
            let transitTokenMint = try PublicKey(string: swap.transitTokenMintPubkey)
            let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
                user: userAuthorityAddress,
                transitTokenMint: transitTokenMint,
                network: network
            )
            
            if needsCreateTransitTokenAccount == true {
                instructions.append(
                    try Program.createTransitTokenAccountInstruction(
                        feePayer: feePayerAddress,
                        userAuthority: userAuthorityAddress,
                        transitTokenAccount: transitTokenAccountAddress,
                        transitTokenMint: transitTokenMint,
                        network: network
                    )
                )
            }
            
            // relay swap
            instructions.append(
                try Program.createRelaySwapInstruction(
                    transitiveSwap: swap,
                    userAuthorityAddressPubkey: userAuthorityAddress,
                    sourceAddressPubkey: userSourceTokenAccountAddress,
                    transitTokenAccount: transitTokenAccountAddress,
                    destinationAddressPubkey: try PublicKey(string: userDestinationTokenAccountAddress),
                    feePayerPubkey: feePayerAddress,
                    network: network
                )
            )
            
        default:
            fatalError("unsupported swap type")
        }
        
        // WSOL close
        // close source
        if let newAccount = sourceWSOLNewAccount {
            instructions.append(contentsOf: [
                TokenProgram.closeAccountInstruction(
                    account: newAccount.publicKey,
                    destination: userAuthorityAddress,
                    owner: userAuthorityAddress
                )
            ])
        }
        // close destination
        if let newAccount = destinationNewAccount, destinationTokenMintAddress == .wrappedSOLMint {
            instructions.append(contentsOf: [
                TokenProgram.closeAccountInstruction(
                    account: newAccount.publicKey,
                    destination: userAuthorityAddress,
                    owner: userAuthorityAddress
                ),
                SystemProgram.transferInstruction(
                    from: userAuthorityAddress,
                    to: feePayerAddress,
                    lamports: minimumTokenAccountBalance
                )
            ])
            accountCreationFee -= minimumTokenAccountBalance
        }
        
        // resign transaction
        var signers = [owner]
        if let sourceWSOLNewAccount = sourceWSOLNewAccount {
            signers.append(sourceWSOLNewAccount)
        }
        if let destinationNewAccount = destinationNewAccount {
            signers.append(destinationNewAccount)
        }
        
        var transactions = [PreparedTransaction]()
        
        if let additionalTransaction = additionalTransaction {
            transactions.append(additionalTransaction)
        }
        transactions.append(
            try prepareTransaction(
                instructions: instructions,
                signers: signers,
                blockhash: blockhash,
                feePayerAddress: feePayerAddress,
                accountCreationFee: accountCreationFee,
                lamportsPerSignature: lamportsPerSignature
            )
        )
        
        return (transactions: transactions, additionalPaybackFee: additionalPaybackFee)
    }
    
    private func prepareTransaction(
        instructions: [TransactionInstruction],
        signers: [Account],
        blockhash: String,
        feePayerAddress: PublicKey,
        accountCreationFee: UInt64,
        lamportsPerSignature: UInt64
    ) throws -> PreparedTransaction {
        var transaction = Transaction()
        transaction.instructions = instructions
        transaction.recentBlockhash = blockhash
        transaction.feePayer = feePayerAddress
    
        try transaction.sign(signers: signers)
        
        // calculate fee first
        let expectedFee = FeeAmount(
            transaction: try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignature),
            accountBalances: accountCreationFee
        )
        
        if let decodedTransaction = transaction.jsonString {
//            Logger.log(message: decodedTransaction, event: .info)
        }
        
        return .init(transaction: transaction, signers: signers, expectedFee: expectedFee)
    }
    
    private func prepareForTopUpAndSwap(
        sourceToken: TokenInfo,
        destinationTokenMint: String,
        destinationAddress: String?,
        payingFeeToken: TokenInfo?,
        swapPools: PoolsPair,
        reuseCache: Bool
    ) async throws -> TopUpAndActionPreparedParams {
        return .init(topUpPreparedParam: .none, actionFeesAndPools: .init(fee: .zero, poolsPair: .init()))
        /*
        guard let relayAccountStatus = cache.relayAccountStatus,
              let freeTransactionFeeLimit = cache.freeTransactionFeeLimit
        else {
            throw FeeRelayer.Error.relayInfoMissing
        }
        
        // form request
        let request: TopUpAndActionPreparedParams
        if reuseCache, let cachedPreparedParams = cache.preparedParams {
            request = cachedPreparedParams
        } else {
            let tradablePoolsPairRequest: [PoolsPair]
//            if let payingFeeToken = payingFeeToken {
//                tradablePoolsPairRequest = orcaSwapClient
//                    .getTradablePoolsPairs(
//                        fromMint: payingFeeToken.mint,
//                        toMint: PublicKey.wrappedSOLMint.base58EncodedString
//                    )
//            } else {
//                tradablePoolsPairRequest = .just([])
//            }
            
//            request = Single.zip(
//                tradablePoolsPairRequest,
            request = calculateSwappingNetworkFees(
                    swapPools: swapPools,
                    sourceTokenMint: sourceToken.mint,
                    destinationTokenMint: destinationTokenMint,
                    destinationAddress: destinationAddress
                )
//            )
                .map { [weak self] swappingFee in
                    let tradablePoolsPairRequest: [PoolsPair] = try await orcaSwapClient.getTradablePoolsPairs(
                        fromMint: payingFeeToken.mint,
                        toMint: PublicKey.wrappedSOLMint.base58EncodedString
                    )
                    guard let self = self else { throw FeeRelayer.Error.unknown }
                    
                    // TOP UP
                    let topUpPreparedParam: TopUpPreparedParams?
                    
                    if payingFeeToken?.mint == PublicKey.wrappedSOLMint.base58EncodedString {
                        topUpPreparedParam = nil
                    } else {
                        if let relayAccountBalance = relayAccountStatus.balance,
                           relayAccountBalance >= swappingFee.total {
                            topUpPreparedParam = nil
                        }
                        // STEP 2.2: Else
                        else {
                            // Get best poolpairs for topping up
                            let targetAmount = swappingFee.total - (relayAccountStatus.balance ?? 0)
                            
                            // Get real amounts needed for topping up
                            let amounts = try self.calculateTopUpAmount(targetAmount: targetAmount, relayAccountStatus: relayAccountStatus, freeTransactionFeeLimit: freeTransactionFeeLimit)
                            let topUpAmount = amounts.topUpAmount
                            let expectedFee = amounts.expectedFee
                            
                            // Get pools
                            let topUpPools: PoolsPair
                            if let bestPools = try self.orcaSwapClient.findBestPoolsPairForEstimatedAmount(topUpAmount, from: tradableTopUpPoolsPair)
                            {
                                topUpPools = bestPools
                            } else {
                                throw FeeRelayer.Error.swapPoolsNotFound
                            }
                            
                            topUpPreparedParam = .init(amount: topUpAmount, expectedFee: expectedFee, poolsPair: topUpPools)
                        }
                    }
                    
                    return .init(
                        topUpPreparedParam: topUpPreparedParam,
                        actionFeesAndPools: .init(fee: swappingFee, poolsPair: swapPools)
                    )
                }
                .do(onSuccess: { [weak self] in
                    self?.locker.lock()
                    self?.cache.preparedParams = $0
                    self?.locker.unlock()
                })*/
//        }
        
        // get tradable poolspair for top up
//        return request
    }
    
    /// Get fixed destination
    private func getFixedDestination(
        destinationTokenMint: String,
        destinationAddress: String?
    ) -> Single<(destinationToken: TokenInfo, userDestinationAccountOwnerAddress: PublicKey?, needsCreateDestinationTokenAccount: Bool)> {
        // Redefine destination
        let userDestinationAccountOwnerAddress: PublicKey?
        let destinationRequest: Single  <SPLTokenDestinationAddress>
        
        if PublicKey.wrappedSOLMint.base58EncodedString == destinationTokenMint {
            // Swap to native SOL account
            userDestinationAccountOwnerAddress = owner.publicKey
            destinationRequest = .just((destination: owner.publicKey, isUnregisteredAsocciatedToken: true))
        } else {
            // Swap to other SPL
            userDestinationAccountOwnerAddress = nil
            
            if let destinationAddress = try? PublicKey(string: destinationAddress) {
                destinationRequest = .just((destination: destinationAddress, isUnregisteredAsocciatedToken: false))
            } else {
                destinationRequest = solanaClient.findSPLTokenDestinationAddress(
                    mintAddress: destinationTokenMint,
                    destinationAddress: owner.publicKey.base58EncodedString
                )
            }
        }
        
        return destinationRequest
            .map { destination, isUnregisteredAsocciatedToken in
                return (
                    destinationToken: .init(address: destination.base58EncodedString, mint: destinationTokenMint),
                    userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress,
                    needsCreateDestinationTokenAccount: isUnregisteredAsocciatedToken
                )
            }
    }
}
