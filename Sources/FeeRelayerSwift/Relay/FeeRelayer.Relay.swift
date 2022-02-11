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
            } else if cache?.relayAccountStatus == .notYetCreated {
                fee.transaction += getRelayAccountCreationCost() // TODO: - accountBalances or transaction?
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
                .flatMap { [weak self] relayAccountStatus, freeTransactionFeeLimit -> Single<(TopUpPreparedParams, RelayAccountStatus, FreeTransactionFeeLimit)> in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    
                    // Check fee
                    var expectedFee = preparedTransaction.expectedFee
                    
                    // User has free transaction
                    if freeTransactionFeeLimit.isFreeTransactionFeeAvailable(transactionFee: expectedFee.transaction)
                    {
                        // skip topup
                        return .just(
                            (.init(topUpFeesAndPools: nil, topUpAmount: nil), relayAccountStatus, freeTransactionFeeLimit))
                    }
                    
                    // if payingFeeToken is provided
                    if let payingFeeToken = payingFeeToken {
                        // if it is the first time user using fee relayer
                        if relayAccountStatus == .notYetCreated {
                            expectedFee.transaction += self.getRelayAccountCreationCost()
                        }
                        return self.prepareForTopUp(amount: expectedFee.total, payingFeeToken: payingFeeToken, relayAccountStatus: relayAccountStatus)
                            .map {($0, relayAccountStatus, freeTransactionFeeLimit)}
                    }
                    
                    // if not, make sure that relayAccountBalance is greater or equal to expected fee
                    if (relayAccountStatus.balance ?? 0) >= expectedFee.total {
                        // skip topup
                        return .just(
                            (.init(topUpFeesAndPools: nil, topUpAmount: nil), relayAccountStatus, freeTransactionFeeLimit))
                    }
                    
                    throw FeeRelayer.Error.feePayingTokenMissing
                }
                .flatMap { [weak self] params, relayAccountStatus, freeTransactionFeeLimit in
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
                    
                    // form transaction
                    let transfer: () throws -> Single<[String]> = { [weak self] in
                        guard let self = self else {return .error(FeeRelayer.Error.unknown)}
                        return self.apiClient.sendTransaction(
                            .relayTransaction(
                                try .init(preparedTransaction: preparedTransaction)
                            ),
                            decodedTo: [String].self
                        )
                    }
                    
                    // check if top up is needed
                    if let topUpFeesAndPools = params.topUpFeesAndPools,
                       let topUpAmount = params.topUpAmount,
                       let payingFeeToken = payingFeeToken
                    {
                        // STEP 2.2.1: Top up
                        return self.topUp(
                            needsCreateUserRelayAddress: relayAccountStatus == .notYetCreated,
                            sourceToken: payingFeeToken,
                            amount: topUpAmount,
                            topUpPools: topUpFeesAndPools.poolsPair,
                            topUpFee: topUpFeesAndPools.fee
                        )
                            // STEP 2.2.2: Swap
                            .flatMap { _ in try transfer() }
                    } else {
                        return try transfer()
                    }
                }
                .do(onSuccess: {[weak self] _ in
                    self?.locker.lock()
                    self?.cache?.freeTransactionFeeLimit?.currentUsage += 1
                    self?.locker.unlock()
                })
                .observe(on: MainScheduler.instance)
        }
    }
}
