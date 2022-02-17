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
    /// Calculate fee and need amount for topup and swap
    public func calculateFeeAndNeededTopUpAmountForSwapping(
        sourceToken: FeeRelayer.Relay.TokenInfo,
        destinationTokenMint: String,
        destinationAddress: String?,
        payingFeeToken: FeeRelayer.Relay.TokenInfo,
        swapPools: OrcaSwap.PoolsPair
    ) -> Single<FeesAndTopUpAmount> {
        Single.zip(
            getRelayAccountStatus(reuseCache: true),
            getFreeTransactionFeeLimit(useCache: true)
        )
            .flatMap { [weak self] relayAccountStatus, freeTransactionFeeLimit -> Single<(TopUpAndActionPreparedParams, RelayAccountStatus)> in
                guard let self = self else { throw FeeRelayer.Error.unknown }
                return self.prepareForTopUpAndSwap(
                    sourceToken: sourceToken,
                    destinationTokenMint: destinationTokenMint,
                    destinationAddress: destinationAddress,
                    payingFeeToken: payingFeeToken,
                    swapPools: swapPools,
                    relayAccountStatus: relayAccountStatus,
                    freeTransactionFeeLimit: freeTransactionFeeLimit,
                    reuseCache: true
                ).map {($0, relayAccountStatus)}
            }
            .map { [weak self] preparedParams, relayAccountStatus in
                guard let self = self else { throw FeeRelayer.Error.unknown }
                let topUpPools = preparedParams.topUpPreparedParam?.poolsPair
                
                var feeAmountInSOL = preparedParams.actionFeesAndPools.fee
                
                if relayAccountStatus == .notYetCreated {
                    feeAmountInSOL.transaction += self.getRelayAccountCreationCost()
                }
                
                var topUpAmount: SolanaSDK.Lamports?
                if let amount = preparedParams.topUpPreparedParam?.amount {
                    topUpAmount = amount + (preparedParams.topUpPreparedParam?.expectedFee ?? 0)
                }
                
                var feeAmountInPayingToken: SolanaSDK.FeeAmount?
                var topUpAmountInPayingToken: UInt64?
                
                if let topUpPools = topUpPools {
                    if let transactionFee = topUpPools.getInputAmount(minimumAmountOut: feeAmountInSOL.transaction, slippage: 0.01),
                       let accountCreationFee = topUpPools.getInputAmount(minimumAmountOut: feeAmountInSOL.accountBalances, slippage: 0.01) {
                        feeAmountInPayingToken = .init(
                            transaction: transactionFee,
                            accountBalances: accountCreationFee
                        )
                    }
                    
                    if let topUpAmount = topUpAmount {
                        topUpAmountInPayingToken = topUpPools.getInputAmount(minimumAmountOut: topUpAmount, slippage: 0.01)
                    }
                }
                
                return .init(
                    feeInSOL: feeAmountInSOL,
                    topUpAmountInSOL: topUpAmount,
                    feeInPayingToken: feeAmountInPayingToken,
                    topUpAmountInPayingToen: topUpAmountInPayingToken
                )
            }
    }
    
    /// Calculate needed fee (count in payingToken)
    public func calculateFeeInPayingToken(
        feeInSOL: SolanaSDK.Lamports,
        payingFeeToken: TokenInfo
    ) -> Single<SolanaSDK.Lamports?> {
        orcaSwapClient
            .getTradablePoolsPairs(
                fromMint: payingFeeToken.mint,
                toMint: SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString
            )
            .map { [weak self] tradableTopUpPoolsPair in
                guard let self = self else { throw FeeRelayer.Error.unknown }
                guard let topUpPools = try self.orcaSwapClient.findBestPoolsPairForEstimatedAmount(feeInSOL, from: tradableTopUpPoolsPair) else {
                    throw FeeRelayer.Error.swapPoolsNotFound
                }
                
                return topUpPools.getInputAmount(minimumAmountOut: feeInSOL, slippage: 0.01)
            }
            .debug()
    }
    
    /// Prepare swap transaction for relay
    public func prepareSwapTransaction(
        sourceToken: TokenInfo,
        destinationTokenMint: String,
        destinationAddress: String?,
        payingFeeToken: TokenInfo,
        swapPools: OrcaSwap.PoolsPair,
        inputAmount: UInt64,
        slippage: Double
    ) -> Single<SolanaSDK.PreparedTransaction> {
        // get fresh data by ignoring cache
        Single.zip(
            Single.zip(
                getRelayAccountStatus(reuseCache: false),
                getFreeTransactionFeeLimit(useCache: false)
            )
                .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
                .flatMap { [weak self] relayAccountStatus, freeTransactionFeeLimit -> Single<TopUpAndActionPreparedParams> in
                    guard let self = self else { throw FeeRelayer.Error.unknown }
                    return self.prepareForTopUpAndSwap(
                        sourceToken: sourceToken,
                        destinationTokenMint: destinationTokenMint,
                        destinationAddress: destinationAddress,
                        payingFeeToken: payingFeeToken,
                        swapPools: swapPools,
                        relayAccountStatus: relayAccountStatus,
                        freeTransactionFeeLimit: freeTransactionFeeLimit,
                        reuseCache: false
                    )
                },
            getFixedDestination(destinationTokenMint: destinationTokenMint, destinationAddress: destinationAddress),
            solanaClient.getRecentBlockhash(commitment: nil)
        )
            .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
            .map { [weak self] preparedParams, destination, recentBlockhash in
                guard let self = self else { throw FeeRelayer.Error.unknown }
                // get needed info
                guard let cache = self.cache else {
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
                    minimumTokenAccountBalance: cache.minimumTokenAccountBalance,
                    needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount,
                    feePayerAddress: cache.feePayerAddress,
                    lamportsPerSignature: cache.lamportsPerSignature
                )
            }
            .observe(on: MainScheduler.instance)
    }
    
    // MARK: - Helpers
    private func calculateSwappingFee(
        sourceToken: TokenInfo,
        destinationToken: TokenInfo,
        needsCreateDestinationTokenAccount: Bool
    ) throws -> SolanaSDK.FeeAmount {
        guard let cache = cache else {throw FeeRelayer.Error.relayInfoMissing}
        var expectedFee = SolanaSDK.FeeAmount.zero
        
        // fee for payer's signature
        expectedFee.transaction += cache.lamportsPerSignature
        
        // fee for owner's signature
        expectedFee.transaction += cache.lamportsPerSignature
        
        // when source token is native SOL
        if sourceToken.mint == SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString {
            // WSOL's signature
            expectedFee.transaction += cache.lamportsPerSignature
            
            // TODO: - Account creation fee?
            expectedFee.accountBalances += cache.minimumTokenAccountBalance
        }
        
        // when needed to create destination
        if needsCreateDestinationTokenAccount && destinationToken.mint != SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString {
            expectedFee.accountBalances += cache.minimumTokenAccountBalance
        }
        
        // when destination is native SOL
        if destinationToken.mint == SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString {
            expectedFee.transaction += cache.lamportsPerSignature
        }
        
        return expectedFee
    }
    
    private func prepareSwapTransaction(
        network: SolanaSDK.Network,
        sourceToken: TokenInfo,
        destinationToken: TokenInfo,
        userDestinationAccountOwnerAddress: String?,
        
        pools: OrcaSwap.PoolsPair,
        inputAmount: UInt64,
        slippage: Double,
        
        feeAmount: UInt64,
        blockhash: String,
        minimumTokenAccountBalance: UInt64,
        needsCreateTransitTokenAccount: Bool,
        needsCreateDestinationTokenAccount: Bool,
        feePayerAddress: String,
        lamportsPerSignature: UInt64
    ) throws -> SolanaSDK.PreparedTransaction {
        // assertion
        let userAuthorityAddress = owner.publicKey
        guard var userSourceTokenAccountAddress = try? SolanaSDK.PublicKey(string: sourceToken.address),
              let sourceTokenMintAddress = try? SolanaSDK.PublicKey(string: sourceToken.mint),
              let feePayerAddress = try? SolanaSDK.PublicKey(string: feePayerAddress),
              let associatedTokenAddress = try? SolanaSDK.PublicKey.associatedTokenAddress(walletAddress: feePayerAddress, tokenMintAddress: sourceTokenMintAddress),
              userSourceTokenAccountAddress != associatedTokenAddress
        else { throw FeeRelayer.Error.wrongAddress }
        let destinationTokenMintAddress = try SolanaSDK.PublicKey(string: destinationToken.mint)
        
        // forming transaction and count fees
        var accountCreationFee: SolanaSDK.Lamports = 0
        var instructions = [SolanaSDK.TransactionInstruction]()
        
        // check source
        var sourceWSOLNewAccount: SolanaSDK.Account?
        if sourceToken.mint == SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString {
            sourceWSOLNewAccount = try SolanaSDK.Account(network: network)
            instructions.append(contentsOf: [
                SolanaSDK.SystemProgram.createAccountInstruction(
                    from: feePayerAddress,
                    toNewPubkey: sourceWSOLNewAccount!.publicKey,
                    lamports: inputAmount + minimumTokenAccountBalance
                ),
                SolanaSDK.TokenProgram.initializeAccountInstruction(
                    account: sourceWSOLNewAccount!.publicKey,
                    mint: .wrappedSOLMint,
                    owner: userAuthorityAddress
                )
            ])
            userSourceTokenAccountAddress = sourceWSOLNewAccount!.publicKey
        }
        
        // check destination
        var destinationNewAccount: SolanaSDK.Account?
        var userDestinationTokenAccountAddress = destinationToken.address
        if needsCreateDestinationTokenAccount {
            destinationNewAccount = try SolanaSDK.Account(network: network)
            instructions.append(contentsOf: [
                SolanaSDK.SystemProgram.createAccountInstruction(
                    from: feePayerAddress,
                    toNewPubkey: destinationNewAccount!.publicKey,
                    lamports: minimumTokenAccountBalance
                ),
                SolanaSDK.TokenProgram.initializeAccountInstruction(
                    account: destinationNewAccount!.publicKey,
                    mint: destinationTokenMintAddress,
                    owner: userAuthorityAddress
                )
            ])
            accountCreationFee += minimumTokenAccountBalance
            userDestinationTokenAccountAddress = destinationNewAccount!.publicKey.base58EncodedString
        }
        
        // swap
        let transitTokenMintPubkey = try getTransitTokenMintPubkey(pools: pools)
        let swap = try prepareSwapData(network: network, pools: pools, inputAmount: inputAmount, minAmountOut: nil, slippage: slippage, transitTokenMintPubkey: transitTokenMintPubkey, needsCreateTransitTokenAccount: needsCreateTransitTokenAccount)
        let userTransferAuthority = swap.transferAuthorityAccount?.publicKey
        
        switch swap.swapData {
        case let swap as DirectSwapData:
            guard let pool = pools.first else {throw FeeRelayer.Error.swapPoolsNotFound}
            
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
            
            // swap
            instructions.append(
                try pool.createSwapInstruction(
                    userTransferAuthorityPubkey: userTransferAuthority ?? userAuthorityAddress,
                    sourceTokenAddress: userSourceTokenAccountAddress,
                    destinationTokenAddress: try SolanaSDK.PublicKey(string: userDestinationTokenAccountAddress),
                    amountIn: swap.amountIn,
                    minAmountOut: swap.minimumAmountOut
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
            let transitTokenMint = try SolanaSDK.PublicKey(string: swap.transitTokenMintPubkey)
            let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
                user: userAuthorityAddress,
                transitTokenMint: transitTokenMint,
                network: network
            )
            
            if needsCreateTransitTokenAccount {
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
                    destinationAddressPubkey: try SolanaSDK.PublicKey(string: userDestinationTokenAccountAddress),
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
                SolanaSDK.TokenProgram.closeAccountInstruction(
                    account: newAccount.publicKey,
                    destination: userAuthorityAddress,
                    owner: userAuthorityAddress
                ),
                SolanaSDK.SystemProgram.transferInstruction(
                    from: userAuthorityAddress,
                    to: feePayerAddress,
                    lamports: minimumTokenAccountBalance
                )
            ])
        }
        // close destination
        if let newAccount = destinationNewAccount, destinationTokenMintAddress == .wrappedSOLMint {
            instructions.append(contentsOf: [
                SolanaSDK.TokenProgram.closeAccountInstruction(
                    account: newAccount.publicKey,
                    destination: userAuthorityAddress,
                    owner: userAuthorityAddress
                ),
                SolanaSDK.SystemProgram.transferInstruction(
                    from: userAuthorityAddress,
                    to: feePayerAddress,
                    lamports: minimumTokenAccountBalance
                )
            ])
            accountCreationFee -= minimumTokenAccountBalance
        }
        
        var transaction = SolanaSDK.Transaction()
        transaction.instructions = instructions
        transaction.recentBlockhash = blockhash
        transaction.feePayer = feePayerAddress
        
        // calculate fee first
        let expectedFee = SolanaSDK.FeeAmount(
            transaction: try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignature),
            accountBalances: accountCreationFee
        )
        
        // resign transaction
        var signers = [owner]
        if let sourceWSOLNewAccount = sourceWSOLNewAccount {
            signers.append(sourceWSOLNewAccount)
        }
        if let destinationNewAccount = destinationNewAccount {
            signers.append(destinationNewAccount)
        }
        try transaction.sign(signers: signers)
        
        if let decodedTransaction = transaction.jsonString {
            Logger.log(message: decodedTransaction, event: .info)
        }
        
        return .init(transaction: transaction, signers: signers, expectedFee: expectedFee)
    }
    
    private func prepareForTopUpAndSwap(
        sourceToken: TokenInfo,
        destinationTokenMint: String,
        destinationAddress: String?,
        payingFeeToken: TokenInfo,
        swapPools: OrcaSwap.PoolsPair,
        relayAccountStatus: RelayAccountStatus,
        freeTransactionFeeLimit: FreeTransactionFeeLimit,
        reuseCache: Bool
    ) -> Single<TopUpAndActionPreparedParams> {
        // form request
        let request: Single<TopUpAndActionPreparedParams>
        if reuseCache, let cachedPreparedParams = cache?.preparedParams {
            request = .just(cachedPreparedParams)
        } else {
            request = Single.zip(
                orcaSwapClient
                    .getTradablePoolsPairs(
                        fromMint: payingFeeToken.mint,
                        toMint: SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString
                    ),
                getFixedDestination(destinationTokenMint: destinationTokenMint, destinationAddress: destinationAddress)
            )
                .map { [weak self] tradableTopUpPoolsPair, destination in
                    guard let self = self else { throw FeeRelayer.Error.unknown }
                    
                    // SWAP
                    let destinationToken = destination.destinationToken
                    let needsCreateDestinationTokenAccount = destination.needsCreateDestinationTokenAccount
                    
                    let swappingFee = try self.calculateSwappingFee(
                        sourceToken: sourceToken,
                        destinationToken: destinationToken,
                        needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount
                    )
                    
                    // TOP UP
                    let topUpPreparedParam: TopUpPreparedParams?
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
                        // TODO: - Temporary solution, prefer direct swap to transitive swap to omit error Non-zero account can only be close if balance zero
                        let topUpPools: OrcaSwap.PoolsPair
                        if let directSwapPools = tradableTopUpPoolsPair.first(where: {$0.count == 1}) {
                            topUpPools = directSwapPools
                        } else if let transitiveSwapPools = try self.orcaSwapClient.findBestPoolsPairForEstimatedAmount(topUpAmount, from: tradableTopUpPoolsPair)
                        {
                            topUpPools = transitiveSwapPools
                        } else {
                            throw FeeRelayer.Error.swapPoolsNotFound
                        }
                        
                        topUpPreparedParam = .init(amount: topUpAmount, expectedFee: expectedFee, poolsPair: topUpPools)
                    }
                    
                    return .init(
                        topUpPreparedParam: topUpPreparedParam,
                        actionFeesAndPools: .init(fee: swappingFee, poolsPair: swapPools)
                    )
                }
                .do(onSuccess: { [weak self] in
                    self?.locker.lock()
                    self?.cache?.preparedParams = $0
                    self?.locker.unlock()
                })
        }
        
        // get tradable poolspair for top up
        return request
    }
    
    /// Get fixed destination
    private func getFixedDestination(
        destinationTokenMint: String,
        destinationAddress: String?
    ) -> Single<(destinationToken: TokenInfo, userDestinationAccountOwnerAddress: SolanaSDK.PublicKey?, needsCreateDestinationTokenAccount: Bool)> {
        // Redefine destination
        let userDestinationAccountOwnerAddress: SolanaSDK.PublicKey?
        let destinationRequest: Single<SolanaSDK.SPLTokenDestinationAddress>
        
        if SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString == destinationTokenMint {
            // Swap to native SOL account
            userDestinationAccountOwnerAddress = owner.publicKey
            destinationRequest = .just((destination: owner.publicKey, isUnregisteredAsocciatedToken: true))
        } else {
            // Swap to other SPL
            userDestinationAccountOwnerAddress = nil
            destinationRequest = solanaClient.findSPLTokenDestinationAddress(
                mintAddress: destinationTokenMint,
                destinationAddress: owner.publicKey.base58EncodedString
            )
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
