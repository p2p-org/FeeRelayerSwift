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
                let topUpAmount = preparedParams.topUpAmount
                
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
    
    /// Top up (if needed) and swap
    public func topUpAndSwap(
        sourceToken: TokenInfo,
        destinationTokenMint: String,
        destinationAddress: String?,
        payingFeeToken: TokenInfo,
        swapPools: OrcaSwap.PoolsPair,
        inputAmount: UInt64,
        slippage: Double
    ) -> Single<[String]> {
        // get owner
        guard let owner = accountStorage.account else {
            return .error(FeeRelayer.Error.unauthorized)
        }
        
        // TODO: Remove later, currently does not support swap from native SOL
        guard sourceToken.address != owner.publicKey.base58EncodedString else {
            return .error(FeeRelayer.Error.unsupportedSwap)
        }
        
        // get fresh data by ignoring cache
        return getRelayAccountStatus(reuseCache: false)
            .flatMap { [weak self] relayAccountStatus -> Single<(RelayAccountStatus, TopUpAndActionPreparedParams)> in
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
                    .map { (relayAccountStatus, $0) }
            }
            .flatMap { [weak self] relayAccountStatus, preparedParams in
                guard let self = self else { throw FeeRelayer.Error.unknown }
                // get needed info
                guard let info = self.info else {
                    return .error(FeeRelayer.Error.relayInfoMissing)
                }
                
                let destination = try self.getFixedDestination(destinationTokenMint: destinationTokenMint, destinationAddress: destinationAddress)
                let destinationToken = destination.destinationToken
                let userDestinationAccountOwnerAddress = destination.userDestinationAccountOwnerAddress
                let needsCreateDestinationTokenAccount = destination.needsCreateDestinationTokenAccount
                
                let swapFeesAndPools = preparedParams.actionFeesAndPools
                let swappingFee = swapFeesAndPools.fee.total
                let swapPools = swapFeesAndPools.poolsPair
                
                // prepare handler
                let swap: () -> Single<[String]> = { [weak self] in
                    guard let self = self else { return .error(FeeRelayer.Error.unknown) }
                    return self.swap(
                        network: self.solanaClient.endpoint.network,
                        owner: owner,
                        sourceToken: sourceToken,
                        destinationToken: destinationToken,
                        userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress?.base58EncodedString,
                        pools: swapPools,
                        inputAmount: inputAmount,
                        slippage: slippage,
                        feeAmount: swappingFee,
                        minimumTokenAccountBalance: info.minimumTokenAccountBalance,
                        needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount,
                        feePayerAddress: info.feePayerAddress,
                        lamportsPerSignature: info.lamportsPerSignature
                    )
                }
                
                // STEP 2: Check if relay account has already had enough balance to cover swapping fee
                // STEP 2.1: If relay account has enough balance to cover swapping fee
                if let topUpFeesAndPools = preparedParams.topUpFeesAndPools,
                   let topUpAmount = preparedParams.topUpAmount {
                    // STEP 2.2.1: Top up
                    return self.topUp(
                        needsCreateUserRelayAddress: relayAccountStatus == .notYetCreated,
                        sourceToken: payingFeeToken,
                        amount: topUpAmount,
                        topUpPools: topUpFeesAndPools.poolsPair,
                        topUpFee: topUpFeesAndPools.fee
                    )
                        // STEP 2.2.2: Swap
                        .flatMap { _ in
                            swap()
                        }
                } else {
                    return swap()
                }
            }
            .observe(on: MainScheduler.instance)
    }
    
    // MARK: - Helpers
    /// Submits a signed token swap transaction to the backend for processing
    func swap(
        network: SolanaSDK.Network,
        owner: SolanaSDK.Account,
        sourceToken: TokenInfo,
        destinationToken: TokenInfo,
        userDestinationAccountOwnerAddress: String?,
        
        pools: OrcaSwap.PoolsPair,
        inputAmount: UInt64,
        slippage: Double,
        
        feeAmount: UInt64,
        minimumTokenAccountBalance: UInt64,
        needsCreateDestinationTokenAccount: Bool,
        feePayerAddress: String,
        lamportsPerSignature: UInt64
    ) -> Single<[String]> {
        solanaClient.getRecentBlockhash(commitment: nil)
            .flatMap { [weak self] blockhash in
                guard let self = self else {throw FeeRelayer.Error.unknown}
                let swapTransaction = try self.prepareForSwapping(
                    network: self.solanaClient.endpoint.network,
                    sourceToken: sourceToken,
                    destinationToken: destinationToken,
                    userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress,
                    pools: pools,
                    inputAmount: inputAmount,
                    slippage: slippage,
                    feeAmount: feeAmount,
                    blockhash: blockhash,
                    minimumTokenAccountBalance: minimumTokenAccountBalance,
                    needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount,
                    feePayerAddress: feePayerAddress,
                    lamportsPerSignature: lamportsPerSignature
                )
                
                let signatures = try self.getSignatures(
                    transaction: swapTransaction.transaction,
                    owner: owner,
                    transferAuthorityAccount: swapTransaction.transferAuthorityAccount
                )
                
                return self.apiClient.sendTransaction(
                    .relaySwap(.init(
                        userSourceTokenAccountPubkey: sourceToken.address,
                        userDestinationPubkey: destinationToken.address,
                        userDestinationAccountOwner: userDestinationAccountOwnerAddress,
                        sourceTokenMintPubkey: sourceToken.mint,
                        destinationTokenMintPubkey: destinationToken.mint,
                        userAuthorityPubkey: owner.publicKey.base58EncodedString,
                        userSwap: .init(swapTransaction.swapData),
                        feeAmount: feeAmount,
                        signatures: signatures,
                        blockhash: blockhash
                    )),
                    decodedTo: [String].self
                )
            }
    }
    
    func calculateSwappingFee(
        sourceToken: TokenInfo,
        destinationToken: TokenInfo,
        userDestinationAccountOwnerAddress: String?,
        pools: OrcaSwap.PoolsPair,
        needsCreateDestinationTokenAccount: Bool
    ) throws -> SolanaSDK.FeeAmount {
        guard let info = info else {throw FeeRelayer.Error.relayInfoMissing}
        let fee = try prepareForSwapping(
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
        ).feeAmount
        return fee
    }
    
    private func prepareForSwapping(
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
    ) throws -> PreparedParams {
        // assertion
        guard let userAuthorityAddress = accountStorage.account?.publicKey else {throw FeeRelayer.Error.unauthorized}
        guard let userSourceTokenAccountAddress = try? SolanaSDK.PublicKey(string: sourceToken.address),
              let sourceTokenMintAddress = try? SolanaSDK.PublicKey(string: sourceToken.mint),
              let feePayerAddress = try? SolanaSDK.PublicKey(string: feePayerAddress),
              let associatedTokenAddress = try? SolanaSDK.PublicKey.associatedTokenAddress(walletAddress: feePayerAddress, tokenMintAddress: sourceTokenMintAddress),
              userSourceTokenAccountAddress != associatedTokenAddress
        else { throw FeeRelayer.Error.wrongAddress }
        let destinationTokenMintAddress = try SolanaSDK.PublicKey(string: destinationToken.mint)
        
        // forming transaction and count fees
        var expectedFee = SolanaSDK.FeeAmount(transaction: 0, accountBalances: 0)
        var instructions = [SolanaSDK.TransactionInstruction]()
        
        // create destination address
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
            expectedFee.accountBalances += minimumTokenAccountBalance
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
        
        // IN CASE SWAPPING TO SOL
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
                
                expectedFee.accountBalances -= minimumTokenAccountBalance
            }
        }
        
        // Relay fee
        instructions.append(
            try Program.transferSolInstruction(
                userAuthorityAddress: userAuthorityAddress,
                recipient: feePayerAddress,
                lamports: feeAmount,
                network: network
            )
        )
        
        var transaction = SolanaSDK.Transaction()
        transaction.instructions = instructions
        transaction.feePayer = feePayerAddress
        transaction.recentBlockhash = blockhash
        let transactionFee = try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignature)
        expectedFee.transaction = transactionFee
        
        return .init(
            swapData: swap.swapData,
            transaction: transaction,
            feeAmount: expectedFee,
            transferAuthorityAccount: swap.transferAuthorityAccount
        )
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
            request = orcaSwapClient
                .getTradablePoolsPairs(
                    fromMint: payingFeeToken.mint,
                    toMint: SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString
                )
                .map { [weak self] tradableTopUpPoolsPair in
                    guard let self = self else { throw FeeRelayer.Error.unknown }
                    
                    // SWAP
                    let destination = try self.getFixedDestination(destinationTokenMint: destinationTokenMint, destinationAddress: destinationAddress)
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
                        
                        guard let topUpPools = try self.orcaSwapClient.findBestPoolsPairForEstimatedAmount(topUpAmount!, from: tradableTopUpPoolsPair) else {
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
    ) throws -> (destinationToken: TokenInfo, userDestinationAccountOwnerAddress: SolanaSDK.PublicKey?, needsCreateDestinationTokenAccount: Bool) {
        guard let owner = accountStorage.account?.publicKey else { throw FeeRelayer.Error.unauthorized }
        // Redefine destination
        let needsCreateDestinationTokenAccount: Bool
        let userDestinationAddress: String
        let userDestinationAccountOwnerAddress: SolanaSDK.PublicKey?
        
        if owner.base58EncodedString == destinationAddress {
            // Swap to native SOL account
            userDestinationAccountOwnerAddress = owner
            needsCreateDestinationTokenAccount = true
            userDestinationAddress = owner.base58EncodedString // placeholder, ignore it
        } else {
            // Swap to other SPL
            userDestinationAccountOwnerAddress = nil
            if let address = destinationAddress {
                // SPL token has ALREADY been created
                userDestinationAddress = address
                needsCreateDestinationTokenAccount = false
            } else {
                // SPL token has NOT been created
                userDestinationAddress = owner.base58EncodedString
                needsCreateDestinationTokenAccount = true
            }
        }
        
        let destinationToken = TokenInfo(address: userDestinationAddress, mint: destinationTokenMint)
        return (destinationToken: destinationToken, userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress, needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount)
    }
}
