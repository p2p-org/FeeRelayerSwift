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
    
    /// Get info of relay account
    func getRelayAccountStatus(reuseCache: Bool) -> Single<FeeRelayer.Relay.RelayAccountStatus>
    
    /// Get first-time account creation cost
    func getRelayAccountCreationCost() -> UInt64
    
    // MARK: - TopUpAndSwap
    
    /// Calculate needed fee IN SOL
    func calculateFeeAndNeededTopUpAmountForSwapping(
        sourceToken: FeeRelayer.Relay.TokenInfo,
        destinationTokenMint: String,
        destinationAddress: String?,
        payingFeeToken: FeeRelayer.Relay.TokenInfo,
        swapPools: OrcaSwap.PoolsPair
    ) -> Single<FeeRelayer.Relay.FeesAndTopUpAmount>
    
    /// Top up relay account (if needed) and swap
    func topUpAndSwap(
        sourceToken: FeeRelayer.Relay.TokenInfo,
        destinationTokenMint: String,
        destinationAddress: String?,
        payingFeeToken: FeeRelayer.Relay.TokenInfo,
        swapPools: OrcaSwap.PoolsPair,
        inputAmount: UInt64,
        slippage: Double
    ) -> Single<[String]>
    
    /// Calculate fee needed in paying token
    func calculateFeeInPayingToken(
        feeInSOL: SolanaSDK.Lamports,
        payingFeeToken: FeeRelayer.Relay.TokenInfo
    ) -> Single<SolanaSDK.Lamports?>
    
    /// Top up relay account (if needed) and relay transaction
    func topUpAndRelayTransaction(
        preparedTransaction: SolanaSDK.PreparedTransaction,
        payingFeeToken: FeeRelayer.Relay.TokenInfo
    ) -> Single<[String]>
    
    func canUseFeeRelayer(useCache: Bool) -> Single<FeeRelayer.Relay.UserAvailableInfo>
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
        let userRelayAddress: SolanaSDK.PublicKey
        var info: RelayInfo? // All info needed to perform actions, works as a cache
        private var cachedRelayAccountStatus: RelayAccountStatus?
        var cachedPreparedParams: TopUpAndActionPreparedParams?
        
        // MARK: - Initializers
        public init(
            apiClient: FeeRelayerAPIClientType,
            solanaClient: SolanaSDK,
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
        private var cachedUserAvailableInfo: UserAvailableInfo? = nil
        public func canUseFeeRelayer(useCache: Bool) -> Single<UserAvailableInfo> {
            if useCache, let cachedUserAvailableInfo = cachedUserAvailableInfo {
                print("Hit cache")
                return .just(cachedUserAvailableInfo)
            }
    
            // TODO: Check fee relay account.
            guard let account = accountStorage.account else { return .error(FeeRelayer.Error.unauthorized) }
            return apiClient
                .requestFreeFeeLimits(for: account.publicKey.base58EncodedString)
                .map { [weak self] info in
                    let info = UserAvailableInfo(maxUsage: info.limits.maxCount, currentUsage: info.processedFee.count)
                    self?.cachedUserAvailableInfo = info
                    return info
                }
        }
    
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
                getRelayAccountStatus(reuseCache: false)
            )
                .do(onSuccess: { [weak self] minimumTokenAccountBalance, minimumRelayAccountBalance, feePayerAddress, lamportsPerSignature, _ in
                    self?.locker.lock()
                    self?.info = .init(
                        minimumTokenAccountBalance: minimumTokenAccountBalance,
                        minimumRelayAccountBalance: minimumRelayAccountBalance,
                        feePayerAddress: feePayerAddress,
                        lamportsPerSignature: lamportsPerSignature
                    )
                    self?.locker.unlock()
                })
                .asCompletable()
        }
        
        /// Get relayAccount status
        public func getRelayAccountStatus(reuseCache: Bool) -> Single<RelayAccountStatus> {
            // form request
            let request: Single<RelayAccountStatus>
            if reuseCache,
               let cachedRelayAccountStatus = cachedRelayAccountStatus {
                request = .just(cachedRelayAccountStatus)
            } else {
                request = solanaClient.getRelayAccountStatus(userRelayAddress.base58EncodedString)
                    .do(onSuccess: { [weak self] in
                        self?.locker.lock()
                        self?.cachedRelayAccountStatus = $0
                        self?.locker.unlock()
                    })
            }
            
            // get relayAccount's status
            return request
        }
        
        public func getRelayAccountCreationCost() -> UInt64 {
            guard let info = info else {
                return 0
            }
            return 2 * info.lamportsPerSignature // TODO: - Temporary solution
        }
        
        /// Generic function for sending transaction to fee relayer's relay
        public func topUpAndRelayTransaction(
            preparedTransaction: SolanaSDK.PreparedTransaction,
            payingFeeToken: TokenInfo
        ) -> Single<[String]> {
            getRelayAccountStatus(reuseCache: false)
                .flatMap { [weak self] relayAccountStatus -> Single<(TopUpPreparedParams, RelayAccountStatus)> in
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    return self.prepareForTopUp(amount: preparedTransaction.expectedFee, payingFeeToken: payingFeeToken, relayAccountStatus: relayAccountStatus)
                        .map {($0, relayAccountStatus)}
                }
                .flatMap { [weak self] params, relayAccountStatus in
                    // assertion
                    guard let self = self else {throw FeeRelayer.Error.unknown}
                    guard let owner = self.accountStorage.account,
                          let feePayer = self.info?.feePayerAddress
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
                    // TODO: - if free transaction fee is available
//                    if isFreeTransactionFee {
//                        paybackFee = preparedTransaction.expectedFee.transaction
//                    }
                    
                    // transfer sol back to feerelayer's feePayer
                    var preparedTransaction = preparedTransaction
                    if paybackFee > 0 {
                        preparedTransaction.transaction.instructions.append(
                            try Program.transferSolInstruction(
                                userAuthorityAddress: owner.publicKey,
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
                       let topUpAmount = params.topUpAmount {
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
        }
    }
}
