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
    /// Expose current variable
    var cache: FeeRelayer.Relay.Cache {get}
    
    /// Load all needed info for relay operations, need to be completed before any operation
    func load() -> Completable
    
    /// Check if user has free transaction fee
    func getFreeTransactionFeeLimit(
    ) -> Single<FeeRelayer.Relay.FreeTransactionFeeLimit>
    
    /// Get info of relay account
    func getRelayAccountStatus(
    ) -> Single<FeeRelayer.Relay.RelayAccountStatus>
    
    /// Calculate needed top up amount for expected fee
    func calculateNeededTopUpAmount(
        expectedFee: SolanaSDK.FeeAmount,
        payingTokenMint: String?
    ) -> Single<SolanaSDK.FeeAmount>
    
    /// Calculate fee needed in paying token
    func calculateFeeInPayingToken(
        feeInSOL: SolanaSDK.FeeAmount,
        payingFeeTokenMint: String
    ) -> Single<SolanaSDK.FeeAmount?>
    
    /// Top up relay account (if needed) and relay transaction
    func topUpAndRelayTransaction(
        preparedTransaction: SolanaSDK.PreparedTransaction,
        payingFeeToken: FeeRelayer.Relay.TokenInfo?,
        additionalPaybackFee: UInt64
    ) -> Single<[String]>
    
    /// Top up relay account (if needed) and relay mutiple transactions
    func topUpAndRelayTransactions(
        preparedTransactions: [SolanaSDK.PreparedTransaction],
        payingFeeToken: FeeRelayer.Relay.TokenInfo?,
        additionalPaybackFee: UInt64
    ) -> Single<[String]>
    
    /// SPECIAL METHODS FOR SWAP NATIVELY
    /// Calculate needed top up amount, specially for swapping
    func calculateNeededTopUpAmount(
        swapTransactions: [OrcaSwap.PreparedSwapTransaction],
        payingTokenMint: String?
    ) -> Single<SolanaSDK.FeeAmount>
    
    /// Top up relay account and swap natively
    func topUpAndSwap(
        _ swapTransactions: [OrcaSwap.PreparedSwapTransaction],
        feePayer: SolanaSDK.PublicKey?,
        payingFeeToken: FeeRelayer.Relay.TokenInfo?
    ) -> Single<[String]>
    
    /// SPECIAL METHODS FOR SWAP WITH RELAY PROGRAM
    /// Calculate network fees for swapping
    func calculateSwappingNetworkFees(
        swapPools: OrcaSwap.PoolsPair?,
        sourceTokenMint: String,
        destinationTokenMint: String,
        destinationAddress: String?
    ) -> Single<SolanaSDK.FeeAmount>
    
    /// Prepare swap transaction for relay using RelayProgram
    func prepareSwapTransaction(
        sourceToken: FeeRelayer.Relay.TokenInfo,
        destinationTokenMint: String,
        destinationAddress: String?,
        payingFeeToken: FeeRelayer.Relay.TokenInfo?,
        swapPools: OrcaSwap.PoolsPair,
        inputAmount: UInt64,
        slippage: Double
    ) -> Single<(transactions: [SolanaSDK.PreparedTransaction], additionalPaybackFee: UInt64)>
}

public extension FeeRelayerRelayType {
    func topUpAndRelayTransaction(
        preparedTransaction: SolanaSDK.PreparedTransaction,
        payingFeeToken: FeeRelayer.Relay.TokenInfo?
    ) -> Single<[String]> {
        topUpAndRelayTransaction(
            preparedTransaction: preparedTransaction,
            payingFeeToken: payingFeeToken,
            additionalPaybackFee: 0
        )
    }
    
    func topUpAndRelayTransactions(
        preparedTransactions: [SolanaSDK.PreparedTransaction],
        payingFeeToken: FeeRelayer.Relay.TokenInfo?
    ) -> Single<[String]> {
        topUpAndRelayTransactions(
            preparedTransactions: preparedTransactions,
            payingFeeToken: payingFeeToken,
            additionalPaybackFee: 0
        )
    }
}

extension FeeRelayer {
    public class Relay: FeeRelayerRelayType {
        // MARK: - Dependencies
        let apiClient: FeeRelayerAPIClientType
        let solanaClient: FeeRelayerRelaySolanaClient
        let accountStorage: SolanaSDKAccountStorage
        let orcaSwapClient: OrcaSwapType
        
        // MARK: - Properties
        let locker = NSLock()
        public internal(set) var cache: Cache
        let owner: SolanaSDK.Account
        let userRelayAddress: SolanaSDK.PublicKey
        
        // MARK: - Initializers
        public init(
            apiClient: FeeRelayerAPIClientType,
            solanaClient: FeeRelayerRelaySolanaClient,
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
            self.cache = .init()
        }
        
        // MARK: - Methods
        /// Load all needed info for relay operations, need to be completed before any operation
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
                updateRelayAccountStatus().andThen(.just(())),
                // get free transaction fee limit
                updateFreeTransactionFeeLimit().andThen(.just(()))
            )
                .do(onSuccess: { [weak self] minimumTokenAccountBalance, minimumRelayAccountBalance, feePayerAddress, lamportsPerSignature, _, _ in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    self.locker.lock()
                    self.cache.minimumTokenAccountBalance = minimumTokenAccountBalance
                    self.cache.minimumRelayAccountBalance = minimumRelayAccountBalance
                    self.cache.feePayerAddress = feePayerAddress
                    self.cache.lamportsPerSignature = lamportsPerSignature
                    self.locker.unlock()
                })
                .asCompletable()
        }
        
        /// Check if user has free transaction fee
        public func getFreeTransactionFeeLimit() -> Single<FreeTransactionFeeLimit> {
            updateFreeTransactionFeeLimit()
                .andThen(.deferred { [weak self] in
                    guard let self = self, let cached = self.cache.freeTransactionFeeLimit else {throw Error.unknown}
                    return .just(cached)
                })
        }
        
        /// Get info of relay account
        public func getRelayAccountStatus() -> Single<RelayAccountStatus> {
            updateRelayAccountStatus()
                .andThen(.deferred { [weak self] in
                    guard let self = self, let cached = self.cache.relayAccountStatus else {throw Error.unknown}
                    return .just(cached)
                })
        }
        
        public func calculateNeededTopUpAmount(
            expectedFee: SolanaSDK.FeeAmount,
            payingTokenMint: String?
        ) -> Single<SolanaSDK.FeeAmount> {
            calculateMinNeededTopUpAmount(
                expectedFee: expectedFee,
                payingTokenMint: payingTokenMint
            ).map { amount -> SolanaSDK.FeeAmount in
                // Correct amount if it's too small
                var amount = amount
                if amount.total > 0 && amount.total < 1000 {
                    amount.transaction += 1000 - amount.total
                }
                return amount
            }
        }
        
        /// Calculate needed top up amount for expected fee
        private func calculateMinNeededTopUpAmount(
            expectedFee: SolanaSDK.FeeAmount,
            payingTokenMint: String?
        ) -> Single<SolanaSDK.FeeAmount> {
            var neededAmount = expectedFee
            
            // expected fees
            let expectedTopUpNetworkFee = 2 * (cache.lamportsPerSignature ?? 5000)
            let expectedTransactionNetworkFee = expectedFee.transaction
            
            // real fees
            var neededTopUpNetworkFee = expectedTopUpNetworkFee
            var neededTransactionNetworkFee = expectedTransactionNetworkFee
            
            // is Top up free
            if cache.freeTransactionFeeLimit?.isFreeTransactionFeeAvailable(transactionFee: expectedTopUpNetworkFee) == true {
                neededTopUpNetworkFee = 0
            }
            
            // is transaction free
            if cache.freeTransactionFeeLimit?.isFreeTransactionFeeAvailable(
                transactionFee: expectedTopUpNetworkFee + expectedTransactionNetworkFee,
                forNextTransaction: true
            ) == true {
                neededTransactionNetworkFee = 0
            }
            
            neededAmount.transaction = neededTopUpNetworkFee + neededTransactionNetworkFee
            
            // check relay account balance
            if neededAmount.total > 0 {
                let neededAmountWithoutCheckingRelayAccount = neededAmount
                 
                // for another token, check relay account status first
                return getRelayAccountStatus()
                    .map { [weak self] relayAccountStatus in
                        guard let self = self else { return expectedFee }
                        // TODO: - Unknown fee when first time using fee relayer
                        if relayAccountStatus == .notYetCreated {
                            if neededAmount.accountBalances > 0 {
                                neededAmount.accountBalances += self.getRelayAccountCreationCost()
                            } else {
                                neededAmount.transaction += self.getRelayAccountCreationCost()
                            }
                        }
                        
                        // Check account balance
                        if var relayAccountBalance = relayAccountStatus.balance,
                           relayAccountBalance > 0
                        {
                            // if relayAccountBalance has enough balance to cover transaction fee
                            if relayAccountBalance >= neededAmount.transaction {
                                
                                relayAccountBalance -= neededAmount.transaction
                                neededAmount.transaction = 0
                                
                                // if relayAccountBlance has enough balance to cover accountBalances fee too
                                if relayAccountBalance >= neededAmount.accountBalances {
                                    neededAmount.accountBalances = 0
                                }
                                
                                // Relay account balance can cover part of account creation fee
                                else {
                                    neededAmount.accountBalances -= relayAccountBalance
                                }
                            }
                            // if not, relayAccountBalance can cover part of transaction fee
                            else {
                                neededAmount.transaction -= relayAccountBalance
                            }
                        }
                        
                        // if relay account could not cover all fees and paying token is WSOL, the compensation will be done without the existense of relay account
                        if neededAmount.total > 0, payingTokenMint == SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString {
                            return neededAmountWithoutCheckingRelayAccount
                        }
                        
                        return neededAmount
                    }
                    .catchAndReturn(expectedFee)
            }
            
            return .just(neededAmount)
        }
        
        /// Calculate needed fee (count in payingToken)
        public func calculateFeeInPayingToken(
            feeInSOL: SolanaSDK.FeeAmount,
            payingFeeTokenMint: String
        ) -> Single<SolanaSDK.FeeAmount?> {
            if payingFeeTokenMint == SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString {
                return .just(feeInSOL)
            }
            return orcaSwapClient
                .getTradablePoolsPairs(
                    fromMint: payingFeeTokenMint,
                    toMint: SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString
                )
                .map { [weak self] tradableTopUpPoolsPair in
                    guard let self = self else { throw FeeRelayer.Error.unknown }
                    guard let topUpPools = try self.orcaSwapClient.findBestPoolsPairForEstimatedAmount(feeInSOL.total, from: tradableTopUpPoolsPair) else {
                        throw FeeRelayer.Error.swapPoolsNotFound
                    }
                    
                    let transactionFee = topUpPools.getInputAmount(minimumAmountOut: feeInSOL.transaction, slippage: 0.01)
                    let accountCreationFee = topUpPools.getInputAmount(minimumAmountOut: feeInSOL.accountBalances, slippage: 0.01)
                    
                    return .init(transaction: transactionFee ?? 0, accountBalances: accountCreationFee ?? 0)
                }
                .debug()
        }
        
        /// Generic function for sending transaction to fee relayer's relay
        public func topUpAndRelayTransaction(
            preparedTransaction: SolanaSDK.PreparedTransaction,
            payingFeeToken: TokenInfo?,
            additionalPaybackFee: UInt64
        ) -> Single<[String]> {
            topUpAndRelayTransactions(
                preparedTransactions: [preparedTransaction],
                payingFeeToken: payingFeeToken,
                additionalPaybackFee: additionalPaybackFee
            )
        }
        
        public func topUpAndRelayTransactions(
            preparedTransactions: [SolanaSDK.PreparedTransaction],
            payingFeeToken: TokenInfo?,
            additionalPaybackFee: UInt64
        ) -> Single<[String]> {
            Completable.zip(
                updateRelayAccountStatus(),
                updateFreeTransactionFeeLimit()
            )
                .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
                .andThen(Single<[String]?>.deferred { [weak self] in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    let expectedFees = preparedTransactions.map {$0.expectedFee}
                    return self.checkAndTopUp(
                        expectedFee: .init(
                            transaction: expectedFees.map {$0.transaction}.reduce(UInt64(0), +),
                            accountBalances: expectedFees.map {$0.accountBalances}.reduce(UInt64(0), +)
                        ),
                        payingFeeToken: payingFeeToken
                    )
                })
                .flatMap { [weak self] topUpTxIds in
                    // assertion
                    guard let self = self, preparedTransactions.count > 0 else {throw FeeRelayer.Error.unknown}
                    var request: Single<[String]> = try self.relayTransaction(
                        preparedTransaction: preparedTransactions[0],
                        payingFeeToken: payingFeeToken,
                        relayAccountStatus: self.cache.relayAccountStatus ?? .notYetCreated,
                        additionalPaybackFee: preparedTransactions.count == 1 ? additionalPaybackFee : 0
                    )
                    
                    if preparedTransactions.count == 2 {
                        request = request
                            .flatMap { [weak self] _ in
                                guard let self = self else {throw FeeRelayer.Error.unknown}
                                return try self.relayTransaction(
                                    preparedTransaction: preparedTransactions[1],
                                    payingFeeToken: payingFeeToken,
                                    relayAccountStatus: self.cache.relayAccountStatus ?? .notYetCreated,
                                    additionalPaybackFee: additionalPaybackFee
                                )
                            }
                    }
                    
                    return request
                        .catch { error in
                            if topUpTxIds != nil {
                                throw FeeRelayer.Error.topUpSuccessButTransactionThrows
                            }
                            throw error
                        }
                }
                .observe(on: MainScheduler.instance)
        }
        
        // MARK: - Helpers
        func checkAndTopUp(
            expectedFee: SolanaSDK.FeeAmount,
            payingFeeToken: TokenInfo?
        ) -> Single<[String]?> {
            // if paying fee token is solana, skip the top up
            if payingFeeToken?.mint == SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString {
                return .just(nil)
            }
            
            guard let freeTransactionFeeLimit = cache.freeTransactionFeeLimit,
                  let relayAccountStatus = cache.relayAccountStatus
            else {
                return .error(Error.relayInfoMissing)
            }
            
            // Check fee
            var expectedFee = expectedFee
            if freeTransactionFeeLimit.isFreeTransactionFeeAvailable(transactionFee: expectedFee.transaction) {
                expectedFee.transaction = 0
            }
                    
            let request: Single<TopUpPreparedParams?>
            
            // if payingFeeToken is provided
            if let payingFeeToken = payingFeeToken, expectedFee.total > 0 {
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
        
        func relayTransaction(
            preparedTransaction: SolanaSDK.PreparedTransaction,
            payingFeeToken: TokenInfo?,
            relayAccountStatus: RelayAccountStatus,
            additionalPaybackFee: UInt64
        ) throws -> Single<[String]> {
            guard let feePayer = cache.feePayerAddress,
                  let freeTransactionFeeLimit = cache.freeTransactionFeeLimit
            else { throw FeeRelayer.Error.unauthorized }
            
            // verify fee payer
            guard feePayer == preparedTransaction.transaction.feePayer?.base58EncodedString
            else {
                throw FeeRelayer.Error.invalidFeePayer
            }
            
            // Calculate the fee to send back to feePayer
            // Account creation fee (accountBalances) is a must-pay-back fee
            var paybackFee = additionalPaybackFee + preparedTransaction.expectedFee.accountBalances
            
            // The transaction fee, on the other hand, is only be paid if user used more than number of free transaction fee
            if !freeTransactionFeeLimit.isFreeTransactionFeeAvailable(transactionFee: preparedTransaction.expectedFee.transaction)
            {
                paybackFee += preparedTransaction.expectedFee.transaction
            }
            
            // transfer sol back to feerelayer's feePayer
            var preparedTransaction = preparedTransaction
            if paybackFee > 0 {
                if payingFeeToken?.mint == SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString,
                   (relayAccountStatus.balance ?? 0) < paybackFee
                {
                    preparedTransaction.transaction.instructions.append(
                        SolanaSDK.SystemProgram.transferInstruction(
                            from: owner.publicKey,
                            to: try SolanaSDK.PublicKey(string: feePayer),
                            lamports: paybackFee
                        )
                    )
                } else {
                    preparedTransaction.transaction.instructions.append(
                        try Program.transferSolInstruction(
                            userAuthorityAddress: owner.publicKey,
                            recipient: try SolanaSDK.PublicKey(string: feePayer),
                            lamports: paybackFee,
                            network: self.solanaClient.endpoint.network
                        )
                    )
                }
            }
            
            #if DEBUG
            if let decodedTransaction = preparedTransaction.transaction.jsonString {
                Logger.log(message: decodedTransaction, event: .info)
            }
            #endif
            
            // resign transaction
            try preparedTransaction.transaction.sign(signers: preparedTransaction.signers)
            
            return self.apiClient.sendTransaction(
                .relayTransaction(
                    try .init(preparedTransaction: preparedTransaction)
                ),
                decodedTo: [String].self
            )
                .do(onSuccess: {[weak self] _ in
                    self?.markTransactionAsCompleted(freeFeeAmountUsed: preparedTransaction.expectedFee.total + additionalPaybackFee - paybackFee)
                })
                .retryWhenNeeded()
        }
    }
}
