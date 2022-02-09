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
        getRelayAccountStatus(reuseCache: true)
            .flatMap { [weak self] relayAccountStatus -> Single<TopUpAndActionPreparedParams> in
                guard let self = self else { throw FeeRelayer.Error.unknown }
                return self.prepareForTopUpAndSwap(
                    sourceToken: sourceToken,
                    destinationTokenMint: destinationTokenMint,
                    destinationAddress: destinationAddress,
                    payingFeeToken: payingFeeToken,
                    swapPools: swapPools,
                    relayAccountStatus: relayAccountStatus,
                    reuseCache: true
                )
            }
            .map { preparedParams in
                let topUpPools = preparedParams.topUpFeesAndPools?.poolsPair
                
                let feeAmountInSOL = preparedParams.actionFeesAndPools.fee
                var topUpAmount: SolanaSDK.Lamports?
                if let amount = preparedParams.topUpAmount {
                    topUpAmount = amount + (preparedParams.topUpFeesAndPools?.fee.accountBalances ?? 0)
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
            getRelayAccountStatus(reuseCache: false)
                .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
                .flatMap { [weak self] relayAccountStatus -> Single<TopUpAndActionPreparedParams> in
                    guard let self = self else { throw FeeRelayer.Error.unknown }
                    return self.prepareForTopUpAndSwap(
                        sourceToken: sourceToken,
                        destinationTokenMint: destinationTokenMint,
                        destinationAddress: destinationAddress,
                        payingFeeToken: payingFeeToken,
                        swapPools: swapPools,
                        relayAccountStatus: relayAccountStatus,
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
                guard let info = self.info else {
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
                    minimumTokenAccountBalance: info.minimumTokenAccountBalance,
                    needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount,
                    feePayerAddress: info.feePayerAddress,
                    lamportsPerSignature: info.lamportsPerSignature
                )
            }
            .observe(on: MainScheduler.instance)
    }
    
    // MARK: - Helpers
    func calculateSwappingFee(
        sourceToken: TokenInfo,
        destinationToken: TokenInfo,
        userDestinationAccountOwnerAddress: String?,
        pools: OrcaSwap.PoolsPair,
        needsCreateDestinationTokenAccount: Bool
    ) throws -> SolanaSDK.FeeAmount {
        guard let info = info else {throw FeeRelayer.Error.relayInfoMissing}
        let fee = try prepareSwapTransaction(
            network: .mainnetBeta, // fake
            sourceToken: sourceToken,
            destinationToken: destinationToken,
            userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress,
            pools: pools,
            inputAmount: 10000, //fake
            slippage: 0.05, // fake
            feeAmount: 0, // fake
            blockhash: "FR1GgH83nmcEdoNXyztnpUL2G13KkUv6iwJPwVfnqEgW", //fake
            minimumTokenAccountBalance: info.minimumTokenAccountBalance,
            needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount,
            feePayerAddress: info.feePayerAddress,
            lamportsPerSignature: info.lamportsPerSignature
        ).expectedFee
        return fee
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
        needsCreateDestinationTokenAccount: Bool,
        feePayerAddress: String,
        lamportsPerSignature: UInt64
    ) throws -> SolanaSDK.PreparedTransaction {
        // assertion
        guard let owner = accountStorage.account else {throw FeeRelayer.Error.unauthorized}
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
                    from: userAuthorityAddress,
                    toNewPubkey: sourceWSOLNewAccount!.publicKey,
                    lamports: inputAmount + minimumTokenAccountBalance
                ),
                SolanaSDK.TokenProgram.initializeAccountInstruction(
                    account: sourceWSOLNewAccount!.publicKey,
                    mint: .wrappedSOLMint,
                    owner: userAuthorityAddress
                )
            ])
            accountCreationFee += minimumTokenAccountBalance
            userSourceTokenAccountAddress = sourceWSOLNewAccount!.publicKey
        }
        
        // check destination
        var userDestinationTokenAccountAddress = destinationToken.address
        if needsCreateDestinationTokenAccount {
            let associatedAccount = try SolanaSDK.PublicKey.associatedTokenAddress(
                walletAddress: try SolanaSDK.PublicKey(string: destinationToken.address),
                tokenMintAddress: destinationTokenMintAddress
            )
            instructions.append(
                SolanaSDK.AssociatedTokenProgram
                    .createAssociatedTokenAccountInstruction(
                        mint: destinationTokenMintAddress,
                        associatedAccount: associatedAccount,
                        owner: try SolanaSDK.PublicKey(string: destinationToken.address),
                        payer: feePayerAddress
                    )
            )
            accountCreationFee += minimumTokenAccountBalance
            userDestinationTokenAccountAddress = associatedAccount.base58EncodedString
        }
        
        // swap
        let transitTokenMintPubkey = try getTransitTokenMintPubkey(pools: pools)
        let swap = try prepareSwapData(network: network, pools: pools, inputAmount: inputAmount, minAmountOut: nil, slippage: slippage, transitTokenMintPubkey: transitTokenMintPubkey)
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
            
            instructions.append(
                try Program.createTransitTokenAccountInstruction(
                    feePayer: feePayerAddress,
                    userAuthority: userAuthorityAddress,
                    transitTokenAccount: transitTokenAccountAddress,
                    transitTokenMint: transitTokenMint,
                    network: network
                )
            )
            
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
            
            // close transit token account
            instructions.append(
                SolanaSDK.TokenProgram.closeAccountInstruction(
                    account: transitTokenAccountAddress,
                    destination: feePayerAddress,
                    owner: feePayerAddress,
                    signers: []
                )
            )
            
        default:
            fatalError("unsupported swap type")
        }
        
        // WSOL close
        // close source
        if let newAccount = sourceWSOLNewAccount {
            instructions.append(
                SolanaSDK.TokenProgram.closeAccountInstruction(
                    account: newAccount.publicKey,
                    destination: userAuthorityAddress,
                    owner: userAuthorityAddress
                )
            )
            
            accountCreationFee -= minimumTokenAccountBalance
        }
        // close destination
        if destinationTokenMintAddress == .wrappedSOLMint {
            if let ownerAddress = try? SolanaSDK.PublicKey(string: userDestinationAccountOwnerAddress) {
                instructions.append(
                    SolanaSDK.TokenProgram.closeAccountInstruction(
                        account: try SolanaSDK.PublicKey(string: userDestinationTokenAccountAddress),
                        destination: ownerAddress,
                        owner: ownerAddress,
                        signers: []
                    )
                )
                
                instructions.append(
                    SolanaSDK.SystemProgram.transferInstruction(
                        from: ownerAddress,
                        to: feePayerAddress,
                        lamports: minimumTokenAccountBalance
                    )
                )
                
                accountCreationFee -= minimumTokenAccountBalance
            }
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
        reuseCache: Bool
    ) -> Single<TopUpAndActionPreparedParams> {
        // form request
        let request: Single<TopUpAndActionPreparedParams>
        if reuseCache, let cachedPreparedParams = cachedPreparedParams {
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
                    let userDestinationAccountOwnerAddress = destination.userDestinationAccountOwnerAddress
                    let needsCreateDestinationTokenAccount = destination.needsCreateDestinationTokenAccount
                    
                    let swappingFee = try self.calculateSwappingFee(
                        sourceToken: sourceToken,
                        destinationToken: destinationToken,
                        userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress?.base58EncodedString,
                        pools: swapPools,
                        needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount
                    )
                    
                    // TOP UP
                    let topUpFeesAndPools: FeesAndPools?
                    var topUpAmount: UInt64?
                    if let relayAccountBalance = relayAccountStatus.balance,
                       relayAccountBalance >= swappingFee.total {
                        topUpFeesAndPools = nil
                    }
                    // STEP 2.2: Else
                    else {
                        // Get best poolpairs for topping up
                        topUpAmount = swappingFee.total - (relayAccountStatus.balance ?? 0)
                        
                        // TODO: - Temporary solution, prefer direct swap to transitive swap to omit error Non-zero account can only be close if balance zero
                        let topUpPools: OrcaSwap.PoolsPair
                        if let directSwapPools = tradableTopUpPoolsPair.first(where: {$0.count == 1}) {
                            topUpPools = directSwapPools
                        } else if let transitiveSwapPools = try self.orcaSwapClient.findBestPoolsPairForEstimatedAmount(topUpAmount!, from: tradableTopUpPoolsPair)
                        {
                            topUpPools = transitiveSwapPools
                        } else {
                            throw FeeRelayer.Error.swapPoolsNotFound
                        }
                        let topUpFee = try self.calculateTopUpFee(topUpPools: topUpPools, relayAccountStatus: relayAccountStatus)
                        topUpFeesAndPools = .init(fee: topUpFee, poolsPair: topUpPools)
                    }
                    
                    return .init(
                        topUpFeesAndPools: topUpFeesAndPools,
                        actionFeesAndPools: .init(fee: swappingFee, poolsPair: swapPools),
                        topUpAmount: topUpAmount
                    )
                }
                .do(onSuccess: { [weak self] in
                    self?.locker.lock()
                    self?.cachedPreparedParams = $0
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
        guard let owner = accountStorage.account?.publicKey else { return .error(FeeRelayer.Error.unauthorized) }
        // Redefine destination
        let userDestinationAccountOwnerAddress: SolanaSDK.PublicKey?
        let destinationRequest: Single<SolanaSDK.SPLTokenDestinationAddress>
        
        if SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString == destinationTokenMint {
            // Swap to native SOL account
            userDestinationAccountOwnerAddress = owner
            destinationRequest = .just((destination: owner, isUnregisteredAsocciatedToken: true))
        } else {
            // Swap to other SPL
            userDestinationAccountOwnerAddress = nil
            destinationRequest = solanaClient.findSPLTokenDestinationAddress(
                mintAddress: destinationTokenMint,
                destinationAddress: owner.base58EncodedString
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
