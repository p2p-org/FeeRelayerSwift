// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

/// Default implementation of RelayService
public class RelayServiceImpl: RelayService {

    // MARK: - Properties

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
        orcaSwap: OrcaSwapType,
        accountStorage: SolanaAccountStorage,
        solanaApiClient: SolanaAPIClient,
        feeCalculator: RelayFeeCalculator = DefaultRelayFeeCalculator(),
        feeRelayerAPIClient: FeeRelayerAPIClient,
        deviceType: StatsInfo.DeviceType,
        buildNumber: String?,
        environment: StatsInfo.Environment
    ) {
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
    ///   - context: current context of Relay's service
    ///   - transaction: transaction that needs to be relayed
    ///   - fee: token to pay fee
    ///   - config: relay's configuration
    /// - Returns: transaction's signature
    public func topUpAndRelayTransaction(
        _ context: RelayContext,
        _ transaction: PreparedTransaction,
        fee: TokenAccount?,
        config: FeeRelayerConfiguration
    ) async throws -> TransactionID {
        try await topUpAndRelayTransaction(context, [transaction], fee: fee, config: config).first
        ?! FeeRelayerError.unknown
    }
    
    /// Top up (if needed) and relay multiple transactions to RelayService
    /// - Parameters:
    ///   - context: current context of Relay's service
    ///   - transactions: transactions that need to be relayed
    ///   - fee: token to pay fee
    ///   - config: relay's configuration
    /// - Returns: transaction's signature
    public func topUpAndRelayTransaction(
        _ context: RelayContext,
        _ transactions: [PreparedTransaction],
        fee: TokenAccount?,
        config: FeeRelayerConfiguration
    ) async throws -> [TransactionID] {
        let expectedFees = transactions.map { $0.expectedFee }
        let res = try await checkAndTopUp(
            context,
            expectedFee: .init(
                transaction: expectedFees.map {$0.transaction}.reduce(UInt64(0), +),
                accountBalances: expectedFees.map {$0.accountBalances}.reduce(UInt64(0), +)
            ),
            payingFeeToken: fee
        )
        
        do {
            var trx: [String] = []
            
            // update context if top up has been completed
            var context = context
            let toppedUp = res != nil
            if toppedUp {
                // modify usage status
                context.usageStatus.currentUsage += 1
                context.usageStatus.amountUsed += context.lamportsPerSignature * 2 // fee for top up has been used
            }
            
            // relay transaction
            for (index, preparedTransaction) in transactions.enumerated() {
                let preparedRelayTransaction = try await prepareRelayTransaction(
                    context,
                    preparedTransaction: preparedTransaction,
                    payingFeeToken: fee,
                    relayAccountStatus: context.relayAccountStatus,
                    additionalPaybackFee: index == transactions.count - 1 ? config.additionalPaybackFee : 0,
                    operationType: config.operationType,
                    currency: config.currency,
                    autoPayback: config.autoPayback
                )
                let signatures = [try await feeRelayerAPIClient.sendTransaction(.relayTransaction(
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
                ))]
                
                trx.append(contentsOf: signatures)
                
                // update context for next transaction
                context.usageStatus.currentUsage += 1
                context.usageStatus.amountUsed += preparedTransaction.expectedFee.transaction
            }

            return trx
        } catch let error {
            if res != nil {
                throw FeeRelayerError.topUpSuccessButTransactionThrows
            }
            throw error
        }
    }
    
    // MARK: - FeeRelayer v2: get feePayer's signature only
    
    /// Top up (if needed) and get feePayer's signature for a transaction
    /// - Parameters:
    ///   - context: current context of Relay's service
    ///   - transaction: transaction that needs feePayer's signature
    ///   - fee: token to pay fee
    ///   - config: relay's configuration
    /// - Returns: feePayer's signature
    public func topUpAndSignRelayTransaction(
        _ context: RelayContext,
        _ transaction: PreparedTransaction,
        fee: TokenAccount?,
        config: FeeRelayerConfiguration
    ) async throws -> TransactionID {
        try await topUpAndSignRelayTransaction(context, [transaction], fee: fee, config: config).first
        ?! FeeRelayerError.unknown
    }
    
    /// Top up (if needed) and get feePayer's signature for multiple transactions
    /// - Parameters:
    ///   - context: current context of Relay's service
    ///   - transactions: transactions that needs feePayer's signature
    ///   - fee: token to pay fee
    ///   - config: relay's configuration
    /// - Returns: feePayer's signatures for transactions
    public func topUpAndSignRelayTransaction(
        _ context: RelayContext,
        _ transactions: [SolanaSwift.PreparedTransaction],
        fee: TokenAccount?,
        config: FeeRelayerConfiguration
    ) async throws -> [TransactionID] {
        let expectedFees = transactions.map { $0.expectedFee }
        let res = try await checkAndTopUp(
            context,
            expectedFee: .init(
                transaction: expectedFees.map {$0.transaction}.reduce(UInt64(0), +),
                accountBalances: expectedFees.map {$0.accountBalances}.reduce(UInt64(0), +)
            ),
            payingFeeToken: fee
        )
        
        do {
            var trx: [String] = []
            
            // update context if top up has been completed
            var context = context
            let toppedUp = res != nil
            if toppedUp {
                // modify usage status
                context.usageStatus.currentUsage += 1
                context.usageStatus.amountUsed += context.lamportsPerSignature * 2 // fee for top up has been used
            }
            
            // relay transaction
            for preparedTransaction in transactions {
                let preparedRelayTransaction = try await prepareRelayTransaction(
                    context,
                    preparedTransaction: preparedTransaction,
                    payingFeeToken: fee,
                    relayAccountStatus: context.relayAccountStatus,
                    additionalPaybackFee: transactions.count > 0 ? config.additionalPaybackFee : 0,
                    operationType: config.operationType,
                    currency: config.currency,
                    autoPayback: config.autoPayback
                )
                let signatures = [try await feeRelayerAPIClient.sendTransaction(.signRelayTransaction(
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
                ))]
                trx.append(contentsOf: signatures)
                
                // update context for next transaction
                context.usageStatus.currentUsage += 1
                context.usageStatus.amountUsed += preparedTransaction.expectedFee.transaction
            }

            return trx
        } catch let error {
            if res != nil {
                throw FeeRelayerError.topUpSuccessButTransactionThrows
            }
            throw error
        }
    }
    
    // MARK: - Helpers
    
    func prepareRelayTransaction(
        _ context: RelayContext,
        preparedTransaction: PreparedTransaction,
        payingFeeToken: TokenAccount?,
        relayAccountStatus: RelayAccountStatus,
        additionalPaybackFee: UInt64,
        operationType _: StatsInfo.OperationType,
        currency _: String?,
        autoPayback: Bool
    ) async throws -> PreparedTransaction {
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
