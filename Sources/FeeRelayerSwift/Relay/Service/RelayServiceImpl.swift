// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

/// Default implementation of RelayService
public class RelayServiceImpl: RelayService {

    // MARK: - Properties
    
    /// RelayContext manager
    let contextManager: RelayContextManager

    /// Client that interacts with fee relayer service
    private(set) var feeRelayerAPIClient: FeeRelayerAPIClient

    /// Client that interacts with solana rpc client
    private(set) var solanaApiClient: SolanaAPIClient

    /// Swap provider client
    private(set) var orcaSwap: OrcaSwapType
    
    /// Account storage that hold solana account
    private(set) var accountStorage: SolanaAccountStorage
    
    /// Fee calculator for RelayService
    public let feeCalculator: RelayFeeCalculator
    
    /// Device type for analysis
    let deviceType: StatsInfo.DeviceType
    
    /// Build number for analysis
    let buildNumber: String?
    
    /// Environment for analysis
    let environment: StatsInfo.Environment
    
    /// Solana account
    public var account: Account {
        accountStorage.account!
    }
    
    // MARK: - Initializer
    
    /// RelayServiceImpl initializer
    public init(
        contextManager: RelayContextManager,
        orcaSwap: OrcaSwapType,
        accountStorage: SolanaAccountStorage,
        solanaApiClient: SolanaAPIClient,
        feeCalculator: RelayFeeCalculator = DefaultRelayFeeCalculator(),
        feeRelayerAPIClient: FeeRelayerAPIClient,
        deviceType: StatsInfo.DeviceType,
        buildNumber: String?,
        environment: StatsInfo.Environment
    ) {
        self.contextManager = contextManager
        self.solanaApiClient = solanaApiClient
        self.accountStorage = accountStorage
        self.feeCalculator = feeCalculator
        self.orcaSwap = orcaSwap
        self.feeRelayerAPIClient = feeRelayerAPIClient
        self.deviceType = deviceType
        self.buildNumber = buildNumber
        self.environment = environment
    }
    
    // MARK: - FeeRelayer v1: relay transaction directly
    
    /// Relay transaction to RelayService without topup
    /// - Parameters:
    ///   - preparedTransaction: preparedTransaction that have to be relayed
    ///   - configuration: relay's configuration
    /// - Returns: transaction's signature
    public func relayTransaction(
        _ preparedTransaction: PreparedTransaction,
        config configuration: FeeRelayerConfiguration
    ) async throws -> String {
        try await feeRelayerAPIClient.sendTransaction(.relayTransaction(
            try .init(
                preparedTransaction: preparedTransaction,
                statsInfo: .init(
                    operationType: configuration.operationType,
                    deviceType: deviceType,
                    currency: configuration.currency,
                    build: buildNumber,
                    environment: environment
                )
            )
        ))
    }
    
    /// Top up (if needed) and relay transaction to RelayService
    /// - Parameters:
    ///   - transaction: transaction that needs to be relayed
    ///   - fee: token to pay fee
    ///   - config: relay's configuration
    /// - Returns: transaction's signature
    public func topUpAndRelayTransaction(
        _ transaction: PreparedTransaction,
        fee: TokenAccount?,
        config: FeeRelayerConfiguration
    ) async throws -> TransactionID {
        try await topUpAndRelayTransaction([transaction], fee: fee, config: config).first
        ?! FeeRelayerError.unknown
    }
    
    /// Top up (if needed) and relay multiple transactions to RelayService
    /// - Parameters:
    ///   - transactions: transactions that need to be relayed
    ///   - fee: token to pay fee
    ///   - config: relay's configuration
    /// - Returns: transaction's signature
    public func topUpAndRelayTransaction(
        _ transactions: [PreparedTransaction],
        fee: TokenAccount?,
        config: FeeRelayerConfiguration
    ) async throws -> [TransactionID] {
        try await topUpAndRelayTransactions(transactions, getSignatureOnly: false, fee: fee, config: config)
    }
    
    // MARK: - FeeRelayer v2: get feePayer's signature only
    
    /// Top up (if needed) and get feePayer's signature for a transaction
    /// - Parameters:
    ///   - transaction: transaction that needs feePayer's signature
    ///   - fee: token to pay fee
    ///   - config: relay's configuration
    /// - Returns: feePayer's signature
    public func topUpAndSignRelayTransaction(
        _ transaction: PreparedTransaction,
        fee: TokenAccount?,
        config: FeeRelayerConfiguration
    ) async throws -> TransactionID {
        try await topUpAndSignRelayTransaction([transaction], fee: fee, config: config).first
        ?! FeeRelayerError.unknown
    }
    
    /// Top up (if needed) and get feePayer's signature for multiple transactions
    /// - Parameters:
    ///   - transactions: transactions that needs feePayer's signature
    ///   - fee: token to pay fee
    ///   - config: relay's configuration
    /// - Returns: feePayer's signatures for transactions
    public func topUpAndSignRelayTransaction(
        _ transactions: [SolanaSwift.PreparedTransaction],
        fee: TokenAccount?,
        config: FeeRelayerConfiguration
    ) async throws -> [TransactionID] {
        try await topUpAndRelayTransactions(transactions, getSignatureOnly: true, fee: fee, config: config)
    }
    
    // MARK: - Helpers
    
    private func topUpAndRelayTransactions(
        _ transactions: [SolanaSwift.PreparedTransaction],
        getSignatureOnly: Bool,
        fee: TokenAccount?,
        config: FeeRelayerConfiguration
    ) async throws -> [String]  {
        // update and get current context
        try await contextManager.update()
        var context = contextManager.currentContext!
        
        // get expected fee
        let expectedFees = transactions.map { $0.expectedFee }
        
        // do top up
        let res = try await checkAndTopUp(
            expectedFee: .init(
                transaction: expectedFees.map {$0.transaction}.reduce(UInt64(0), +),
                accountBalances: expectedFees.map {$0.accountBalances}.reduce(UInt64(0), +)
            ),
            payingFeeToken: fee
        )
        
        // check if topped up
        let toppedUp = res != nil
        
        // update context locally after topping up
        if toppedUp {
            context.usageStatus.currentUsage += 1
            context.usageStatus.amountUsed += context.lamportsPerSignature * 2 // fee for top up has been used
            contextManager.replaceContext(by: context)
        }
        
        do {
            var trx: [String] = []
            
            // relay transactions
            for (index, preparedTransaction) in transactions.enumerated() {
                // relay each transactions
                let preparedRelayTransaction = try await prepareRelayTransaction(
                    preparedTransaction: preparedTransaction,
                    payingFeeToken: fee,
                    relayAccountStatus: context.relayAccountStatus,
                    additionalPaybackFee: index == transactions.count - 1 ? config.additionalPaybackFee : 0,
                    operationType: config.operationType,
                    currency: config.currency,
                    autoPayback: config.autoPayback
                )
                
                let signature: String
                
                if getSignatureOnly {
                    signature = try await feeRelayerAPIClient.sendTransaction(.signRelayTransaction(
                        try .init(
                            preparedTransaction: preparedRelayTransaction,
                            statsInfo: .init(
                                operationType: config.operationType,
                                deviceType: deviceType,
                                currency: config.currency,
                                build: buildNumber,
                                environment: environment
                            )
                        )
                    ))
                } else {
                    signature = try await feeRelayerAPIClient.sendTransaction(.relayTransaction(
                        try .init(
                            preparedTransaction: preparedRelayTransaction,
                            statsInfo: .init(
                                operationType: config.operationType,
                                deviceType: deviceType,
                                currency: config.currency,
                                build: buildNumber,
                                environment: environment
                            )
                        )
                    ))
                }
                
                trx.append(signature)
                
                // update context for next transaction
                context.usageStatus.currentUsage += 1
                context.usageStatus.amountUsed += preparedTransaction.expectedFee.transaction
                contextManager.replaceContext(by: context)

                // wait for transaction to finish if transaction is not the last one
                if !getSignatureOnly, index < transactions.count - 1 {
                    try await solanaApiClient.waitForConfirmation(signature: signature, ignoreStatus: true)
                }
            }

            return trx
        } catch let error {
            if toppedUp {
                throw FeeRelayerError.topUpSuccessButTransactionThrows
            }
            throw error
        }
    }
    
    private func prepareRelayTransaction(
        preparedTransaction: PreparedTransaction,
        payingFeeToken: TokenAccount?,
        relayAccountStatus: RelayAccountStatus,
        additionalPaybackFee: UInt64,
        operationType _: StatsInfo.OperationType,
        currency _: String?,
        autoPayback: Bool
    ) async throws -> PreparedTransaction {
        // get current context
        guard let context = contextManager.currentContext else {
            throw RelayContextManagerError.invalidContext
        }
        let feePayer = context.feePayerAddress
        
        // verify fee payer
        guard feePayer == preparedTransaction.transaction.feePayer else {
            throw FeeRelayerError.invalidFeePayer
        }
        
        // Calculate the fee to send back to feePayer
        // Account creation fee (accountBalances) is a must-pay-back fee
        var paybackFee = additionalPaybackFee + preparedTransaction.expectedFee.accountBalances
        
        // The transaction fee, on the other hand, is only be paid if user used more than number of free transaction fee
        if !context.usageStatus.isFreeTransactionFeeAvailable(transactionFee: preparedTransaction.expectedFee.transaction) {
            paybackFee += preparedTransaction.expectedFee.transaction
        }
        
        // transfer sol back to feerelayer's feePayer
        var preparedTransaction = preparedTransaction
        if autoPayback, paybackFee > 0 {
            // if payingFeeToken is native sol, use SystemProgram
            if payingFeeToken?.mint == PublicKey.wrappedSOLMint,
               (relayAccountStatus.balance ?? 0) < paybackFee
            {
                preparedTransaction.transaction.instructions.append(
                    SystemProgram.transferInstruction(
                        from: account.publicKey,
                        to: feePayer,
                        lamports: paybackFee
                    )
                )
            }
            
            // if payingFeeToken is SPL token, use RelayProgram
            else {
                // return paybackFee (WITHOUT additionalPaybackFee) to Fee payer
                preparedTransaction.transaction.instructions.append(
                    try RelayProgram.transferSolInstruction(
                        userAuthorityAddress: account.publicKey,
                        recipient: feePayer,
                        lamports: paybackFee - additionalPaybackFee, // Important: MINUS additionalPaybackFee
                        network: solanaApiClient.endpoint.network
                    )
                )
                
                // Return additional payback fee from USER ACCOUNT to FeePayer using SystemProgram
                if additionalPaybackFee > 0 {
                    preparedTransaction.transaction.instructions.append(
                        SystemProgram.transferInstruction(
                            from: account.publicKey,
                            to: feePayer,
                            lamports: paybackFee
                        )
                    )
                }
            }
        }
        
        #if DEBUG
//        if let decodedTransaction = preparedTransaction.transaction.jsonString {
//            Logger.log(message: decodedTransaction, event: .info)
//        }
        print(preparedTransaction.transaction.jsonString!)
        #endif
        
        // resign transaction if needed
        if !preparedTransaction.signers.isEmpty {
            try preparedTransaction.transaction.sign(signers: preparedTransaction.signers)
        }
        
        // return prepared transaction
        return preparedTransaction
    }
    
}

enum CacheKey: String {
    case minimumTokenAccountBalance
    case minimumRelayAccountBalance
    case lamportsPerSignature
    case relayAccountStatus
    case preparedParams
    case usageStatus
    case feePayerAddress
}
