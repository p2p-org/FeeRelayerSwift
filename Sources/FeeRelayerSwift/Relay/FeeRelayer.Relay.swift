//
//  FeeRelayer+Relay.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 29/12/2021.
//

import Foundation
import RxSwift
import SolanaSwift
import OrcaSwapSwift

/// Top up and make a transaction
/// STEP 0: Prepare all information needed for the transaction
/// STEP 1: Calculate fee needed for transaction
/// STEP 1.1: Check free fee supported or not
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
    
    /// Check if user has free transaction fee
    func getFreeTransactionFeeLimit(
        useCache: Bool
    ) -> Single<FeeRelayer.Relay.FreeTransactionFeeLimit>
    
    /// Get info of relay account
    func getRelayAccountStatus(
        reuseCache: Bool
    ) -> Single<FeeRelayer.Relay.RelayAccountStatus>
    
    /// Calculate fee
    func calculateFee(
        preparedTransaction: SolanaSDK.PreparedTransaction
    ) -> SolanaSDK.FeeAmount
    
    /// Top up relay account (if needed) and relay transaction
    func topUpAndRelayTransaction(
        preparedTransaction: SolanaSDK.PreparedTransaction,
        payingFeeToken: FeeRelayer.Relay.TokenInfo?
    ) -> Single<[String]>
    
    /// Calculate fees
    func calculateFees(
        _ swapTransactions: [OrcaSwap.PreparedSwapTransaction]
    ) throws -> SolanaSDK.FeeAmount
    
    /// Native swap
    func topUpAndSwap(
        _ swapTransactions: [OrcaSwap.PreparedSwapTransaction],
        feePayer: SolanaSDK.PublicKey?,
        payingFeeToken: FeeRelayer.Relay.TokenInfo?
    ) -> Single<[String]>
    
    /// Calculate needed fee IN SOL
    func calculateFeeAndNeededTopUpAmountForSwapping(
        sourceToken: FeeRelayer.Relay.TokenInfo,
        destinationTokenMint: String,
        destinationAddress: String?,
        payingFeeToken: FeeRelayer.Relay.TokenInfo,
        swapPools: OrcaSwap.PoolsPair
    ) -> Single<FeeRelayer.Relay.FeesAndTopUpAmount>
    
    /// Prepare swap transaction for relay
    func prepareSwapTransaction(
        sourceToken: FeeRelayer.Relay.TokenInfo,
        destinationTokenMint: String,
        destinationAddress: String?,
        payingFeeToken: FeeRelayer.Relay.TokenInfo,
        swapPools: OrcaSwap.PoolsPair,
        inputAmount: UInt64,
        slippage: Double
    ) -> Single<SolanaSDK.PreparedTransaction>
    
    /// Calculate fee needed in paying token
    func calculateFeeInPayingToken(
        feeInSOL: SolanaSDK.Lamports,
        payingFeeToken: FeeRelayer.Relay.TokenInfo
    ) -> Single<SolanaSDK.Lamports?>
}

extension FeeRelayer {
    public class Relay: FeeRelayerRelayType {
        // MARK: - Dependencies
        let apiClient: FeeRelayerAPIClientType
        let solanaClient: SolanaSDK
        let accountStorage: SolanaSDKAccountStorage
        let orcaSwapClient: OrcaSwapType
        
        // MARK: - Properties
        let locker = NSLock()
        var cache: Cache? // All info needed to perform actions, works as a cache
        let owner: SolanaSDK.Account
        let userRelayAddress: SolanaSDK.PublicKey
        
        // MARK: - Initializers
        public init(
            apiClient: FeeRelayerAPIClientType,
            solanaClient: SolanaSDK,
            accountStorage: SolanaSDKAccountStorage,
            orcaSwapClient: OrcaSwapType
        ) throws {
            guard let owner = accountStorage.account else {throw Error.unauthorized}
            self.apiClient = apiClient
            self.solanaClient = solanaClient
            self.accountStorage = accountStorage
            self.orcaSwapClient = orcaSwapClient
            self.owner = owner
            self.userRelayAddress = try Program.getUserRelayAddress(user: owner.publicKey, network: self.solanaClient.endpoint.network)
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
                // get relayAccount status
                getRelayAccountStatus(reuseCache: false),
                // get free transaction fee limit
                getFreeTransactionFeeLimit(useCache: false)
            )
                .do(onSuccess: { [weak self] minimumTokenAccountBalance, minimumRelayAccountBalance, feePayerAddress, lamportsPerSignature, relayAccountStatus, freeTransactionFeeLimit in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    self.locker.lock()
                    self.cache = .init(
                        minimumTokenAccountBalance: minimumTokenAccountBalance,
                        minimumRelayAccountBalance: minimumRelayAccountBalance,
                        feePayerAddress: feePayerAddress,
                        lamportsPerSignature: lamportsPerSignature,
                        relayAccountStatus: relayAccountStatus,
                        freeTransactionFeeLimit: freeTransactionFeeLimit
                    )
                    self.locker.unlock()
                })
                .asCompletable()
        }
        
        public func getFreeTransactionFeeLimit(useCache: Bool) -> Single<FreeTransactionFeeLimit> {
            if useCache, let cachedUserAvailableInfo = cache?.freeTransactionFeeLimit {
                print("Hit cache")
                return .just(cachedUserAvailableInfo)
            }
    
            return apiClient
                .requestFreeFeeLimits(for: owner.publicKey.base58EncodedString)
                .map { [weak self] info in
                    let info = FreeTransactionFeeLimit(
                        maxUsage: info.limits.maxCount,
                        currentUsage: info.processedFee.count,
                        maxAmount: info.limits.maxAmount,
                        amountUsed: info.processedFee.totalAmount
                    )
                    self?.locker.lock()
                    self?.cache?.freeTransactionFeeLimit = info
                    self?.locker.unlock()
                    return info
                }
        }
        
        /// Get relayAccount status
        public func getRelayAccountStatus(reuseCache: Bool) -> Single<RelayAccountStatus> {
            if reuseCache,
               let cachedRelayAccountStatus = cache?.relayAccountStatus
            {
                return .just(cachedRelayAccountStatus)
            }
            
            return solanaClient.getRelayAccountStatus(userRelayAddress.base58EncodedString)
                .do(onSuccess: { [weak self] in
                    self?.locker.lock()
                    self?.cache?.relayAccountStatus = $0
                    self?.locker.unlock()
                })
        }
        
        /// Calculate fee for given transaction, including top up fee
        public func calculateFee(preparedTransaction: SolanaSDK.PreparedTransaction) -> SolanaSDK.FeeAmount {
            var fee = preparedTransaction.expectedFee
            if cache?.freeTransactionFeeLimit?.isFreeTransactionFeeAvailable(transactionFee: fee.transaction) == true
            {
                fee.transaction = 0
            } else {
                if cache?.relayAccountStatus == .notYetCreated {
                    fee.transaction += getRelayAccountCreationCost() // TODO: - accountBalances or transaction?
                } else {
                    fee.transaction += 2 * (cache?.lamportsPerSignature ?? 5000) // Top up network fee
                }
            }
            return fee
        }
        
        /// Generic function for sending transaction to fee relayer's relay
        public func topUpAndRelayTransaction(
            preparedTransaction: SolanaSDK.PreparedTransaction,
            payingFeeToken: TokenInfo?
        ) -> Single<[String]> {
            Single.zip(
                getRelayAccountStatus(reuseCache: false),
                getFreeTransactionFeeLimit(useCache: false)
            )
                .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
                .flatMap { [weak self] relayAccountStatus, freeTransactionFeeLimit -> Single<FreeTransactionFeeLimit> in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    return self.checkAndTopUp(
                        expectedFee: preparedTransaction.expectedFee,
                        payingFeeToken: payingFeeToken,
                        relayAccountStatus: relayAccountStatus,
                        freeTransactionFeeLimit: freeTransactionFeeLimit
                    )
                        .map {_ in freeTransactionFeeLimit}
                }
                .flatMap { [weak self] freeTransactionFeeLimit in
                    // assertion
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    guard let feePayer = self.cache?.feePayerAddress
                    else {throw FeeRelayer.Error.unauthorized}
                    
                    // verify fee payer
                    guard feePayer == preparedTransaction.transaction.feePayer?.base58EncodedString
                    else {
                        throw FeeRelayer.Error.invalidFeePayer
                    }
                    
                    // Calculate the fee to send back to feePayer
                    // Account creation fee (accountBalances) is a must-pay-back fee
                    var paybackFee = preparedTransaction.expectedFee.accountBalances
                    
                    // The transaction fee, on the other hand, is only be paid if user used more than number of free transaction fee
                    if !freeTransactionFeeLimit.isFreeTransactionFeeAvailable(transactionFee: preparedTransaction.expectedFee.transaction)
                    {
                        paybackFee += preparedTransaction.expectedFee.transaction
                    }
                    
                    // transfer sol back to feerelayer's feePayer
                    var preparedTransaction = preparedTransaction
                    if paybackFee > 0 {
                        preparedTransaction.transaction.instructions.append(
                            try Program.transferSolInstruction(
                                userAuthorityAddress: self.owner.publicKey,
                                recipient: try SolanaSDK.PublicKey(string: feePayer),
                                lamports: paybackFee,
                                network: self.solanaClient.endpoint.network
                            )
                        )
                    }
                    
                    // resign transaction
                    try preparedTransaction.transaction.sign(signers: preparedTransaction.signers)
                    
                    return self.apiClient.sendTransaction(
                        .relayTransaction(
                            try .init(preparedTransaction: preparedTransaction)
                        ),
                        decodedTo: [String].self
                    )
                }
                .do(onSuccess: {[weak self] _ in
                    self?.locker.lock()
                    self?.cache?.freeTransactionFeeLimit?.currentUsage += 1
                    self?.locker.unlock()
                })
                .observe(on: MainScheduler.instance)
        }
        
        public func calculateFees(
            _ swapTransactions: [OrcaSwap.PreparedSwapTransaction]
        ) throws -> SolanaSDK.FeeAmount {
            guard let cache = cache else {
                throw FeeRelayer.Error.relayInfoMissing
            }

            // transaction fee
            let transactionFee = UInt64(swapTransactions.count) * 2 * cache.lamportsPerSignature
            
            // account creation fee
            let accountCreationFee = swapTransactions.reduce(0, {$0+$1.accountCreationFee})
            
            return .init(transaction: transactionFee, accountBalances: accountCreationFee)
        }
        
        public func topUpAndSwap(
            _ swapTransactions: [OrcaSwap.PreparedSwapTransaction],
            feePayer: SolanaSDK.PublicKey?,
            payingFeeToken: FeeRelayer.Relay.TokenInfo?
        ) -> Single<[String]> {
            guard swapTransactions.count > 0 && swapTransactions.count <= 2 else {
                return .error(OrcaSwapError.invalidNumberOfTransactions)
            }
            var request = prepareAndSend(
                swapTransactions[0],
                feePayer: feePayer ?? owner.publicKey,
                payingFeeToken: payingFeeToken
            )
            if swapTransactions.count == 2 {
                request = request
                    .flatMap {[weak self] _ in
                        guard let self = self else {throw OrcaSwapError.unknown}
                        return self.prepareAndSend(
                            swapTransactions[1],
                            feePayer: feePayer ?? self.owner.publicKey,
                            payingFeeToken: payingFeeToken
                        )
                            .retry { errors in
                                errors.enumerated().flatMap{ (index, error) -> Observable<Int64> in
                                    if let error = error as? SolanaSDK.Error {
                                        switch error {
                                        case .invalidResponse(let error) where error.data?.logs?.contains("Program log: Error: InvalidAccountData") == true:
                                            return .timer(.seconds(1), scheduler: MainScheduler.instance)
                                        case .transactionError(_, logs: let logs) where logs.contains("Program log: Error: InvalidAccountData"):
                                            return .timer(.seconds(1), scheduler: MainScheduler.instance)
                                        default:
                                            break
                                        }
                                    }
                                    
                                    return .error(error)
                                }
                            }
                            .timeout(.seconds(60), scheduler: MainScheduler.instance)
                    }
            }
            return request
        }
        
        private func prepareAndSend(
            _ swapTransaction: OrcaSwap.PreparedSwapTransaction,
            feePayer: OrcaSwap.PublicKey,
            payingFeeToken: FeeRelayer.Relay.TokenInfo?
        ) -> Single<[String]> {
            solanaClient.prepareTransaction(
                instructions: swapTransaction.instructions,
                signers: swapTransaction.signers,
                feePayer: feePayer,
                accountsCreationFee: swapTransaction.accountCreationFee,
                recentBlockhash: nil,
                lamportsPerSignature: nil
            )
                .flatMap { [weak self] preparedTransaction in
                    guard let self = self else {throw OrcaSwapError.unknown}
                    return self.topUpAndRelayTransaction(
                        preparedTransaction: preparedTransaction,
                        payingFeeToken: payingFeeToken
                    )
                }
        }
        
        private func checkAndTopUp(
            expectedFee: SolanaSDK.FeeAmount,
            payingFeeToken: TokenInfo?,
            relayAccountStatus: RelayAccountStatus,
            freeTransactionFeeLimit: FreeTransactionFeeLimit
        ) -> Single<[String]?> {
            // Check fee
            var expectedFee = expectedFee
            if freeTransactionFeeLimit.isFreeTransactionFeeAvailable(transactionFee: expectedFee.transaction) {
                expectedFee.transaction = 0
            }
                    
            // if payingFeeToken is provided
            let request: Single<TopUpPreparedParams?>
            
            if let payingFeeToken = payingFeeToken {
                request = self.prepareForTopUp(targetAmount: expectedFee.total, payingFeeToken: payingFeeToken, relayAccountStatus: relayAccountStatus, freeTransactionFeeLimit: freeTransactionFeeLimit)
            }
            
            // if not, make sure that relayAccountBalance is greater or equal to expected fee
            else if (relayAccountStatus.balance ?? 0) >= expectedFee.total {
                // skip topup
                request = .just(nil)
            }
            
            // fee paying token is required but missing
            else {
                request = .error(FeeRelayer.Error.feePayingTokenMissing)
            }
            
            return request
                .flatMap { [weak self] params in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    if let topUpParams = params, let payingFeeToken = payingFeeToken {
                        return self.topUp(
                            needsCreateUserRelayAddress: relayAccountStatus == .notYetCreated,
                            sourceToken: payingFeeToken,
                            targetAmount: topUpParams.amount,
                            topUpPools: topUpParams.poolsPair,
                            expectedFee: topUpParams.expectedFee
                        )
                            .map(Optional.init)
                    }
                    return .just(nil)
                }
        }
    }
}
