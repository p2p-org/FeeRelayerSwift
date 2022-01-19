//
//  FeeRelayer+Relay.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 29/12/2021.
//

import Foundation
import RxSwift
import SolanaSwift

/// Top up and make a transaction
/// STEP 0: Prepare all information needed for the transaction
/// STEP 1: Calculate fee needed for transaction
    // STEP 1.1: Check free fee supported or not
/// STEP 2: Check if relay account has already had enough balance to cover transaction fee
    /// STEP 2.1: If relay account has not been created or has not have enough balance, do top up
        /// STEP 2.1.1: Top up with needed amount
        /// STEP 2.1.2: Make transaction
    /// STEP 2.2: Else, skip top up
        /// STEP 2.2.1: Make transaction
/// - Returns: Array of strings contain transactions' signatures

public protocol FeeRelayerRelayType {
    /// Load all needed info for relay operations, need to be completed before any operation
    func load() -> Completable
    
    // MARK: - TopUpAndSwap
    /// Calculate prepared params, get all pools, fees, topUp amount for swapping
    func prepareForTopUpAndSwap(
        sourceToken: FeeRelayer.Relay.TokenInfo,
        destinationTokenMint: String,
        destinationAddress: String?,
        payingFeeToken: FeeRelayer.Relay.TokenInfo,
        swapPools: OrcaSwap.PoolsPair
    ) -> Single<FeeRelayer.Relay.TopUpAndActionPreparedParams>
    
    /// Calculate needed fee that needs to be taken from payingToken
    func calculateNeededFee(
        preparedParams: FeeRelayer.Relay.TopUpAndActionPreparedParams
    ) -> UInt64?
    
    /// Top up relay account (if needed) and swap
    func topUpAndSwap(
        sourceToken: FeeRelayer.Relay.TokenInfo,
        destinationTokenMint: String,
        destinationAddress: String?,
        payingFeeToken: FeeRelayer.Relay.TokenInfo,
        preparedParams: FeeRelayer.Relay.TopUpAndActionPreparedParams,
        inputAmount: UInt64,
        slippage: Double
    ) -> Single<[String]>
    
    func topUpAndSend(
        sourceToken: FeeRelayer.Relay.TokenInfo,
        destinationAddress: String,
        tokenMint: String,
        payingFeeToken: FeeRelayer.Relay.TokenInfo,
        preparedParams: FeeRelayer.Relay.TopUpAndActionPreparedParams,
        inputAmount: UInt64,
        slippage: Double
    ) -> Single<[String]>
}

extension FeeRelayer {
    public class Relay: FeeRelayerRelayType {
        // MARK: - Properties
        var info: RelayInfo? // All info needed to perform actions, works as a cache
        private let userRelayAddress: SolanaSDK.PublicKey
        private let apiClient: FeeRelayerAPIClientType
        private let solanaClient: FeeRelayerRelaySolanaClient
        let accountStorage: SolanaSDKAccountStorage
        let orcaSwapClient: OrcaSwapType
        
        // MARK: - Initializers
        public init(
            apiClient: FeeRelayerAPIClientType,
            solanaClient: FeeRelayerRelaySolanaClient,
            accountStorage: SolanaSDKAccountStorage,
            orcaSwapClient: OrcaSwapType
        ) throws {
            guard let owner = accountStorage.account else { throw FeeRelayer.Error.unauthorized }
            self.apiClient = apiClient
            self.solanaClient = solanaClient
            self.accountStorage = accountStorage
            self.orcaSwapClient = orcaSwapClient
            let userRelayAddress = try Program.getUserRelayAddress(user: owner.publicKey, network: solanaClient.endpoint.network)
            self.userRelayAddress = userRelayAddress
        }
        
        // MARK: - Methods
        public func load() -> Completable {
            Single.zip(
                // get minimum token account balance
                solanaClient.getMinimumBalanceForRentExemption(span: 165),
                // get minimum relay account balance
                solanaClient.getMinimumBalanceForRentExemption(span: 0),
                // get fee payer address
                apiClient.getFeePayerPubkey(),
                // get lamportsPerSignature
                solanaClient.getLamportsPerSignature(),
                // get relayAccount's status
                solanaClient.getRelayAccountStatus(userRelayAddress.base58EncodedString)
            )
                .observe(on: MainScheduler.instance)
                .do(onSuccess: { [weak self] minimumTokenAccountBalance, minimumRelayAccountBalance, feePayerAddress, lamportsPerSignature, relayAccountStatus in
                    self?.info = .init(
                        minimumTokenAccountBalance: minimumTokenAccountBalance,
                        minimumRelayAccountBalance: minimumRelayAccountBalance,
                        feePayerAddress: feePayerAddress,
                        lamportsPerSignature: lamportsPerSignature,
                        relayAccountStatus: relayAccountStatus
                    )
                })
                .asCompletable()
        }
        
        public func prepareForTopUpAndSwap(
            sourceToken: TokenInfo,
            destinationTokenMint: String,
            destinationAddress: String?,
            payingFeeToken: TokenInfo,
            swapPools: OrcaSwap.PoolsPair
        ) -> Single<TopUpAndActionPreparedParams> {
            // get tradable poolspair for top up
            orcaSwapClient
                .getTradablePoolsPairs(
                    fromMint: payingFeeToken.mint,
                    toMint: SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString
                )
                .map { [weak self] tradableTopUpPoolsPair in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    guard let info = self.info else {throw FeeRelayer.Error.relayInfoMissing}
                    
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
                    if let relayAccountBalance = info.relayAccountStatus.balance,
                       relayAccountBalance >= swappingFee.total
                    {
                        topUpFeesAndPools = nil
                    }
                    // STEP 2.2: Else
                    else {
                        // Get best poolpairs for topping up
                        topUpAmount = swappingFee.total - (info.relayAccountStatus.balance ?? 0)
                        
                        guard let topUpPools = try self.orcaSwapClient.findBestPoolsPairForEstimatedAmount(topUpAmount!, from: tradableTopUpPoolsPair) else {
                            throw FeeRelayer.Error.swapPoolsNotFound
                        }
                        let topUpFee = try self.calculateTopUpFee(topUpPools: topUpPools)
                        topUpFeesAndPools = .init(fee: topUpFee, poolsPair: topUpPools)
                    }
                    
                    return .init(
                        topUpFeesAndPools: topUpFeesAndPools,
                        actionFeesAndPools: .init(fee: swappingFee, poolsPair: swapPools),
                        topUpAmount: topUpAmount
                    )
                }
        }
        
        public func calculateNeededFee(
            preparedParams: TopUpAndActionPreparedParams
        ) -> UInt64? {
            guard let amountInSOL = preparedParams.topUpAmount else {return nil}
            return preparedParams.topUpFeesAndPools?.poolsPair.getInputAmount(minimumAmountOut: amountInSOL, slippage: 0.01)
        }
        
        public func topUpAndSwap(
            sourceToken: TokenInfo,
            destinationTokenMint: String,
            destinationAddress: String?,
            payingFeeToken: TokenInfo,
            preparedParams: TopUpAndActionPreparedParams,
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
            
            // reload needed info
            return load()
                .andThen(Single<Void>.just(()))
                .flatMap { [weak self] in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
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
                        guard let self = self else {return .error(FeeRelayer.Error.unknown)}
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
                       let topUpAmount = preparedParams.topUpAmount
                    {
                        // STEP 2.2.1: Top up
                        return self.topUp(
                            owner: owner,
                            needsCreateUserRelayAddress: info.relayAccountStatus == .notYetCreated,
                            sourceToken: payingFeeToken,
                            amount: topUpAmount,
                            topUpPools: topUpFeesAndPools.poolsPair,
                            topUpFee: topUpFeesAndPools.fee.total
                        )
                        // STEP 2.2.2: Swap
                            .flatMap {_ in swap()}
                    } else {
                        return swap()
                    }
                }
                .observe(on: MainScheduler.instance)
        }
        
        /// Submits a signed top up swap transaction to the backend for processing
        func topUp(
            owner: SolanaSDK.Account,
            needsCreateUserRelayAddress: Bool,
            sourceToken: TokenInfo,
            amount: UInt64,
            topUpPools: OrcaSwap.PoolsPair,
            topUpFee: UInt64
        ) -> Single<[String]> {
            // get recent blockhash
            solanaClient.getRecentBlockhash(commitment: nil)
                .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
                .flatMap { [weak self] recentBlockhash in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    guard let info = self.info else { throw FeeRelayer.Error.relayInfoMissing }
                    
                    // STEP 3: prepare for topUp
                    let topUpTransaction = try self.prepareForTopUp(
                        network: self.solanaClient.endpoint.network,
                        sourceToken: sourceToken,
                        userAuthorityAddress: owner.publicKey,
                        userRelayAddress: self.userRelayAddress,
                        topUpPools: topUpPools,
                        amount: amount,
                        feeAmount: topUpFee,
                        blockhash: recentBlockhash,
                        minimumRelayAccountBalance: info.minimumRelayAccountBalance,
                        minimumTokenAccountBalance: info.minimumTokenAccountBalance,
                        needsCreateUserRelayAccount: needsCreateUserRelayAddress,
                        feePayerAddress: info.feePayerAddress,
                        lamportsPerSignature: info.lamportsPerSignature
                    )
                    
                    // STEP 4: send transaction
                    let signatures = try self.getSignatures(
                        transaction: topUpTransaction.transaction,
                        owner: owner,
                        transferAuthorityAccount: topUpTransaction.transferAuthorityAccount
                    )
                    return self.apiClient.sendTransaction(
                        .relayTopUpWithSwap(
                            .init(
                                userSourceTokenAccountPubkey: sourceToken.address,
                                sourceTokenMintPubkey: sourceToken.mint,
                                userAuthorityPubkey: owner.publicKey.base58EncodedString,
                                topUpSwap: .init(topUpTransaction.swapData),
                                feeAmount: topUpFee,
                                signatures: signatures,
                                blockhash: recentBlockhash
                            )
                        ),
                        decodedTo: [String].self
                    )
                }
                .observe(on: MainScheduler.instance)
        }
        
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
        
        /// Get signature from transaction
        private func getSignatures(
            transaction: SolanaSDK.Transaction,
            owner: SolanaSDK.Account,
            transferAuthorityAccount: SolanaSDK.Account
        ) throws -> SwapTransactionSignatures {
            var transaction = transaction
            
            try transaction.sign(signers: [owner, transferAuthorityAccount])
            guard let ownerSignatureData = transaction.findSignature(pubkey: owner.publicKey)?.signature,
                  let transferAuthoritySignatureData = transaction.findSignature(pubkey: transferAuthorityAccount.publicKey)?.signature
                else {
                throw FeeRelayer.Error.invalidSignature
            }
            
            if let decodedTransaction = transaction.jsonString {
                Logger.log(message: decodedTransaction, event: .info)
            }
            
            let ownerSignature = Base58.encode(ownerSignatureData.bytes)
            let transferAuthoritySignature = Base58.encode(transferAuthoritySignatureData.bytes)
            
            return .init(userAuthoritySignature: ownerSignature, transferAuthoritySignature: transferAuthoritySignature)
        }
        
        /// Get fixed destination
        private func getFixedDestination(
            destinationTokenMint: String,
            destinationAddress: String?
        ) throws -> (destinationToken: TokenInfo, userDestinationAccountOwnerAddress: SolanaSDK.PublicKey?, needsCreateDestinationTokenAccount: Bool) {
            guard let owner = accountStorage.account?.publicKey else {throw FeeRelayer.Error.unauthorized}
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
                    userDestinationAddress = try SolanaSDK.PublicKey.associatedTokenAddress(
                        walletAddress: owner,
                        tokenMintAddress: try SolanaSDK.PublicKey(string: destinationTokenMint)
                    ).base58EncodedString
                    needsCreateDestinationTokenAccount = true
                }
            }
            
            let destinationToken = TokenInfo(address: userDestinationAddress, mint: destinationTokenMint)
            return (destinationToken: destinationToken, userDestinationAccountOwnerAddress: userDestinationAccountOwnerAddress, needsCreateDestinationTokenAccount: needsCreateDestinationTokenAccount)
        }
        
        public func topUpAndSend(
            sourceToken: TokenInfo,
            destinationAddress: String,
            tokenMint: String,
            payingFeeToken: TokenInfo,
            preparedParams: TopUpAndActionPreparedParams,
            inputAmount: UInt64,
            slippage: Double) -> Single<[String]> {
            guard let owner = accountStorage.account else {
                return .error(FeeRelayer.Error.unauthorized)
            }
            
            return load()
                .andThen(Single<Void>.just(()))
                .flatMap { [weak self] in
                    guard let self = self else { throw FeeRelayer.Error.unknown }
                    // get needed info
                    guard let info = self.info else {
                        return .error(FeeRelayer.Error.relayInfoMissing)
                    }
                    
                    let transfer: () -> Single<[String]> = { [weak self] in
                        guard let self = self else { return .error(FeeRelayer.Error.unknown) }
                        return self.transfer()
                    }
                    
                    // STEP 2: Check if relay account has already had enough balance to cover swapping fee
                    // STEP 2.1: If relay account has enough balance to cover transfer fee
                    if let topUpFeesAndPools = preparedParams.topUpFeesAndPools,
                       let topUpAmount = preparedParams.topUpAmount {
                        return self.topUp(
                                owner: owner,
                                needsCreateUserRelayAddress: info.relayAccountStatus == .notYetCreated,
                                sourceToken: payingFeeToken,
                                amount: topUpAmount,
                                topUpPools: topUpFeesAndPools.poolsPair,
                                topUpFee: topUpFeesAndPools.fee.total
                            )
                            // STEP 2.2.2: Swap
                            .flatMap { _ in transfer() }
                    } else {
                        return transfer()
                    }
                }
        }
        
        public func transfer(
            network: SolanaSDK.Network,
            owner: SolanaSDK.Account,
            sourceToken: TokenInfo,
            recipientPubkey: String,
            inputAmount: UInt64,
            slippage: Double
        ) throws -> Single<[String]> {
            // Calculate fee
            var expectedFee = FeeRelayer.FeeAmount(transaction: 0, accountBalances: 0)
            var instructions = [SolanaSDK.TransactionInstruction]()
    
            
            instructions.append(
                SolanaSDK.TokenProgram.transferInstruction(
                    tokenProgramId: .tokenProgramId,
                    source: try SolanaSDK.PublicKey(string: sourceToken.address),
                    destination: try SolanaSDK.PublicKey(string: recipientPubkey),
                    owner: owner.publicKey,
                    amount: inputAmount)
            )
    
            instructions.append(
                try Program.transferSolInstruction(
                    userAuthorityAddress: userAuthorityAddress,
                    recipient: feePayerAddress,
                    lamports: feeAmount,
                    network: network
                )
            )
            
            Single.just([])
        }
    }
}

extension Encodable {
    var jsonString: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
