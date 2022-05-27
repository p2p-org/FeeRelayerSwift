// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

class FeeRelayerService: FeeRelayer {
    private(set) var feeRelayerAPIClient: FeeRelayerAPIClient
    private(set) var solanaApiClient: SolanaAPIClient
    private(set) var orcaSwapAPIClient: OrcaSwapAPIClient
    private(set) var orcaSwap: OrcaSwap
    private(set) var account: Account
    private(set) var accountStorage: SolanaAccountStorage
    private let feeCalculator: FeeRelayerCalculator
    private let deviceType: StatsInfo.DeviceType
    private let buildNumber: String?
    

    init(
        account: Account,
        orcaSwap: OrcaSwap,
        accountStorage: SolanaAccountStorage,
        solanaApiClient: SolanaAPIClient,
        orcaSwapAPIClient: OrcaSwapAPIClient,
        feeCalculator: FeeRelayerCalculator = DefaultFreeRelayerCalculator(),
        feeRelayerAPIClient: FeeRelayerAPIClient,
        deviceType: StatsInfo.DeviceType,
        buildNumber: String?
    ) {
        self.account = account
        self.solanaApiClient = solanaApiClient
        self.orcaSwapAPIClient = orcaSwapAPIClient
        self.accountStorage = accountStorage
        self.feeCalculator = feeCalculator
        self.orcaSwap = orcaSwap
        self.feeRelayerAPIClient = feeRelayerAPIClient
        self.deviceType = deviceType
        self.buildNumber = buildNumber
    }

    func topUpAndRelayTransaction(
        _ transaction: PreparedTransaction,
        fee: TokenAccount?,
        config: FeeRelayerConfiguration
    ) async throws -> TransactionID {
        try await topUpAndRelayTransaction([transaction], fee: fee, config: config).first
        ?! FeeRelayerError.unknown
    }

    func topUpAndRelayTransaction(
        _ transactions: [PreparedTransaction],
        fee: TokenAccount?,
        config: FeeRelayerConfiguration
    ) async throws -> [TransactionID] {
        // 1. create context
        let context = try await FeeRelayerContext.create(
            userAccount: account,
            solanaAPIClient: solanaApiClient,
            feeRelayerAPIClient: feeRelayerAPIClient
        )
        let expectedFees = transactions.map { $0.expectedFee }
        let res = try await checkAndTopUp(
            context,
            expectedFee: .init(
                transaction: expectedFees.map {$0.transaction}.reduce(UInt64(0), +),
                accountBalances: expectedFees.map {$0.accountBalances}.reduce(UInt64(0), +)
            ),
            payingFeeToken: fee
        )
        
        guard let firstTx = transactions.first else { throw FeeRelayerError.unknown }
        
        do {
            let request = try await relayTransaction(
                context,
                preparedTransaction: firstTx,
                payingFeeToken: fee,
                relayAccountStatus: context.relayAccountStatus,
                additionalPaybackFee: transactions.count == 1 ? config.additionalPaybackFee : 0,
                operationType: config.operationType,
                currency: config.currency
            )
            return request
        } catch let error {
            if res != nil {
                throw FeeRelayerError.topUpSuccessButTransactionThrows
            }
            throw error
        }
    }
    
    private func checkAndTopUp(
        _ context: FeeRelayerContext,
        expectedFee: FeeAmount,
        payingFeeToken: TokenAccount?
    ) async throws -> [String]? {
        
        // if paying fee token is solana, skip the top up
        if payingFeeToken?.mint == PublicKey.wrappedSOLMint {
            return nil
        }
        let topUpAmount = try await feeCalculator.calculateNeededTopUpAmount(
            context,
            expectedFee: expectedFee,
            payingTokenMint: payingFeeToken?.mint
        )
        // no need to top up
        var (params, needsCreateUserRelayAddress): (TopUpPreparedParams?, Bool)
        if topUpAmount.total <= 0 {
            (params, needsCreateUserRelayAddress) = (nil, context.relayAccountStatus == .notYetCreated)
        }

        // top up
        let prepareResult = try await prepareForTopUp(
            context,
            topUpAmount: topUpAmount.total,
            payingFeeToken: try payingFeeToken ?! FeeRelayerError.unknown,
            relayAccountStatus: context.relayAccountStatus
        )
        (params, needsCreateUserRelayAddress) = (prepareResult, context.relayAccountStatus == .notYetCreated)
        
        if let topUpParams = params, let payingFeeToken = payingFeeToken {
            return try await self.topUp(
                context,
                needsCreateUserRelayAddress: needsCreateUserRelayAddress,
                sourceToken: payingFeeToken,
                targetAmount: topUpParams.amount,
                topUpPools: topUpParams.poolsPair,
                expectedFee: topUpParams.expectedFee
            )
        }
        return nil
    }
    func prepareForTopUp(
        _ context: FeeRelayerContext,
        topUpAmount: Lamports,
        payingFeeToken: TokenAccount,
        relayAccountStatus: RelayAccountStatus,
        forceUsingTransitiveSwap: Bool = false // true for testing purpose only
    ) async throws -> TopUpPreparedParams? {
        // form request
        let tradableTopUpPoolsPair = try await orcaSwap.getTradablePoolsPairs(
            fromMint: payingFeeToken.mint.base58EncodedString,
            toMint: PublicKey.wrappedSOLMint.base58EncodedString
        )
        // Get fee
        let expectedFee = try feeCalculator.calculateExpectedFeeForTopUp(context)
        // Get pools for topping up
        let topUpPools: PoolsPair
        // force using transitive swap (for testing only)
        if forceUsingTransitiveSwap {
            let pools = tradableTopUpPoolsPair.first(where: {$0.count == 2})!
            topUpPools = pools
        }
        // prefer direct swap to transitive swap
        else if let directSwapPools = tradableTopUpPoolsPair.first(where: {$0.count == 1}) {
            topUpPools = directSwapPools
        }
        // if direct swap is not available, use transitive swap
        else if let transitiveSwapPools = try orcaSwap.findBestPoolsPairForEstimatedAmount(topUpAmount, from: tradableTopUpPoolsPair) {
            topUpPools = transitiveSwapPools
        }
        // no swap is available
        else {
            throw FeeRelayerError.swapPoolsNotFound
        }
        // return needed amount and pools
        return .init(amount: topUpAmount, expectedFee: expectedFee, poolsPair: topUpPools)
    }
    
    func topUp(
        _ context: FeeRelayerContext,
        needsCreateUserRelayAddress: Bool,
        sourceToken: TokenAccount,
        targetAmount: UInt64,
        topUpPools: PoolsPair,
        expectedFee: UInt64
    ) async throws -> [String] {
        
        let transitToken = try TransitTokenAccountAnalysator.getTransitToken(
            solanaApiClient: solanaApiClient,
            orcaSwap: orcaSwap,
            account: account,
            pools: topUpPools
        )
        
        let needsCreateTransitTokenAccount = try await TransitTokenAccountAnalysator.checkIfNeedsCreateTransitTokenAccount(
            solanaApiClient: solanaApiClient,
            transitToken: transitToken
        )
        
        let blockhash = try await solanaApiClient.getRecentBlockhash(commitment: nil)
        let minimumRelayAccountBalance = context.minimumRelayAccountBalance
        let minimumTokenAccountBalance = context.minimumTokenAccountBalance
        let feePayerAddress = context.feePayerAddress
        let lamportsPerSignature = context.lamportsPerSignature
        let freeTransactionFeeLimit = context.usageStatus

        // STEP 3: prepare for topUp
        let topUpTransaction: (swapData: FeeRelayerRelaySwapType, preparedTransaction: PreparedTransaction) = try self.prepareForTopUp(
            network: solanaApiClient.endpoint.network,
            sourceToken: sourceToken,
            userAuthorityAddress: account.publicKey,
            userRelayAddress: RelayProgram.getUserRelayAddress(user: account.publicKey, network: solanaApiClient.endpoint.network),
            topUpPools: topUpPools,
            targetAmount: targetAmount,
            expectedFee: expectedFee,
            blockhash: blockhash,
            minimumRelayAccountBalance: minimumRelayAccountBalance,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            needsCreateUserRelayAccount: needsCreateUserRelayAddress,
            feePayerAddress: feePayerAddress,
            lamportsPerSignature: lamportsPerSignature,
            freeTransactionFeeLimit: freeTransactionFeeLimit,
            needsCreateTransitTokenAccount: needsCreateTransitTokenAccount,
            transitTokenMintPubkey: transitToken?.mint,
            transitTokenAccountAddress: transitToken?.address
        )
        
        // STEP 4: send transaction
        let signatures = topUpTransaction.preparedTransaction.transaction.signatures
        guard signatures.count >= 2 else { throw FeeRelayerError.invalidSignature }
        
        // the second signature is the owner's signature
        let ownerSignature = try signatures.getSignature(index: 1)
        
        // the third signature (optional) is the transferAuthority's signature
        let transferAuthoritySignature = try? signatures.getSignature(index: 2)
        
        let topUpSignatures = SwapTransactionSignatures(
            userAuthoritySignature: ownerSignature,
            transferAuthoritySignature: transferAuthoritySignature
        )
        let result = try await self.feeRelayerAPIClient.sendTransaction(
            .relayTopUpWithSwap(
                .init(
                    userSourceTokenAccount: sourceToken.address,
                    sourceTokenMint: sourceToken.mint,
                    userAuthority: account.publicKey,
                    topUpSwap: .init(topUpTransaction.swapData),
                    feeAmount: expectedFee,
                    signatures: topUpSignatures,
                    blockhash: blockhash,
                    deviceType: self.deviceType,
                    buildNumber: self.buildNumber
                )
            )
        )
        return [result]
    }
 
    /// Prepare transaction and expected fee for a given relay transaction
    private func prepareForTopUp(
        network: Network,
        sourceToken: TokenAccount,
        userAuthorityAddress: PublicKey,
        userRelayAddress: PublicKey,
        topUpPools: PoolsPair,
        targetAmount: UInt64,
        expectedFee: UInt64,
        blockhash: String,
        minimumRelayAccountBalance: UInt64,
        minimumTokenAccountBalance: UInt64,
        needsCreateUserRelayAccount: Bool,
        feePayerAddress: PublicKey,
        lamportsPerSignature: UInt64,
        freeTransactionFeeLimit: UsageStatus?,
        needsCreateTransitTokenAccount: Bool?,
        transitTokenMintPubkey: PublicKey?,
        transitTokenAccountAddress: PublicKey?
    ) throws -> (swapData: FeeRelayerRelaySwapType, preparedTransaction: PreparedTransaction) {
        // assertion
        let userSourceTokenAccountAddress = sourceToken.address
        let sourceTokenMintAddress = sourceToken.mint
        let feePayerAddress = feePayerAddress
        let associatedTokenAddress = try PublicKey.associatedTokenAddress(
            walletAddress: feePayerAddress,
            tokenMintAddress: sourceTokenMintAddress
        ) ?! FeeRelayerError.unknown
        
        guard userSourceTokenAccountAddress != associatedTokenAddress else {
            throw FeeRelayerError.unknown
        }
        
        // forming transaction and count fees
        var accountCreationFee: UInt64 = 0
        var instructions = [TransactionInstruction]()
        
        // create user relay account
        if needsCreateUserRelayAccount {
            instructions.append(
                SystemProgram.transferInstruction(
                    from: feePayerAddress,
                    to: userRelayAddress,
                    lamports: minimumRelayAccountBalance
                )
            )
            accountCreationFee += minimumRelayAccountBalance
        }
        
        // top up swap
        let swap = try prepareSwapData(
            network: network,
            pools: topUpPools,
            inputAmount: nil,
            minAmountOut: targetAmount,
            slippage: 0.01,
            transitTokenMintPubkey: transitTokenMintPubkey,
            needsCreateTransitTokenAccount: needsCreateTransitTokenAccount == true
        )
        let userTransferAuthority = swap.transferAuthorityAccount?.publicKey
        
        switch swap.swapData {
        case let swap as DirectSwapData:
            accountCreationFee += minimumTokenAccountBalance
            // approve
            if let userTransferAuthority = userTransferAuthority {
                instructions.append(
                    TokenProgram.approveInstruction(
                        account: userSourceTokenAccountAddress,
                        delegate: userTransferAuthority,
                        owner: userAuthorityAddress,
                        multiSigners: [],
                        amount: swap.amountIn
                    )
                )
            }
            
            // top up
            instructions.append(
                try Program.topUpSwapInstruction(
                    network: network,
                    topUpSwap: swap,
                    userAuthorityAddress: userAuthorityAddress,
                    userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                    feePayerAddress: feePayerAddress
                )
            )
        case let swap as TransitiveSwapData:
            // approve
            if let userTransferAuthority = userTransferAuthority {
                instructions.append(
                    TokenProgram.approveInstruction(
                        account: userSourceTokenAccountAddress,
                        delegate: userTransferAuthority,
                        owner: userAuthorityAddress,
                        multiSigners: [],
                        amount: swap.to.amountIn
                    )
                )
            }
            
            // create transit token account
            if needsCreateTransitTokenAccount == true, let transitTokenAccountAddress = transitTokenAccountAddress {
                instructions.append(
                    try Program.createTransitTokenAccountInstruction(
                        feePayer: feePayerAddress,
                        userAuthority: userAuthorityAddress,
                        transitTokenAccount: transitTokenAccountAddress,
                        transitTokenMint: try PublicKey(string: swap.transitTokenMintPubkey),
                        network: network
                    )
                )
            }
            
            // Destination WSOL account funding
            accountCreationFee += minimumTokenAccountBalance
            
            // top up
            instructions.append(
                try Program.topUpSwapInstruction(
                    network: network,
                    topUpSwap: swap,
                    userAuthorityAddress: userAuthorityAddress,
                    userSourceTokenAccountAddress: userSourceTokenAccountAddress,
                    feePayerAddress: feePayerAddress
                )
            )
        default:
            fatalError("unsupported swap type")
        }
        
        // transfer
        instructions.append(
            try Program.transferSolInstruction(
                userAuthorityAddress: userAuthorityAddress,
                recipient: feePayerAddress,
                lamports: expectedFee,
                network: network
            )
        )
        
        var transaction = Transaction()
        transaction.instructions = instructions
        transaction.feePayer = feePayerAddress
        transaction.recentBlockhash = blockhash
        
        // calculate fee first
        let expectedFee = FeeAmount(
            transaction: try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignature),
            accountBalances: accountCreationFee
        )
        
        // resign transaction
        var signers = [account]
        if let tranferAuthority = swap.transferAuthorityAccount {
            signers.append(tranferAuthority)
        }
        try transaction.sign(signers: signers)
        
//        if let decodedTransaction = transaction.jsonString {
//            Logger.log(message: decodedTransaction, event: .info)
//        }
        
        return (
            swapData: swap.swapData,
            preparedTransaction: .init(
                transaction: transaction,
                signers: signers,
                expectedFee: expectedFee
            )
        )
    }
    
    /// Prepare swap data from swap pools
    func prepareSwapData(
        network: Network,
        pools: PoolsPair,
        inputAmount: UInt64?,
        minAmountOut: UInt64?,
        slippage: Double,
        transitTokenMintPubkey: PublicKey? = nil,
        newTransferAuthority: Bool = false,
        needsCreateTransitTokenAccount: Bool
    ) throws -> (swapData: FeeRelayerRelaySwapType, transferAuthorityAccount: Account?) {
        // preconditions
        guard pools.count > 0 && pools.count <= 2 else { throw FeeRelayerError.swapPoolsNotFound }
        guard !(inputAmount == nil && minAmountOut == nil) else { throw FeeRelayerError.invalidAmount }
        
        // create transferAuthority
        let transferAuthority = try Account(network: network)
        
        // form topUp params
        if pools.count == 1 {
            let pool = pools[0]
            
            guard let amountIn = try inputAmount ?? pool.getInputAmount(minimumReceiveAmount: minAmountOut!, slippage: slippage),
                  let minAmountOut = try minAmountOut ?? pool.getMinimumAmountOut(inputAmount: inputAmount!, slippage: slippage)
            else { throw FeeRelayerError.invalidAmount }
            
            let directSwapData = pool.getSwapData(
                transferAuthorityPubkey: newTransferAuthority ? transferAuthority.publicKey: account.publicKey,
                amountIn: amountIn,
                minAmountOut: minAmountOut
            )
            return (swapData: directSwapData, transferAuthorityAccount: newTransferAuthority ? transferAuthority: nil)
        } else {
            let firstPool = pools[0]
            let secondPool = pools[1]
            
            guard let transitTokenMintPubkey = transitTokenMintPubkey else {
                throw FeeRelayerError.transitTokenMintNotFound
            }
            
            // if input amount is provided
            var firstPoolAmountIn = inputAmount
            var secondPoolAmountIn: UInt64?
            var secondPoolAmountOut = minAmountOut
            
            if let inputAmount = inputAmount {
                secondPoolAmountIn = try firstPool.getMinimumAmountOut(inputAmount: inputAmount, slippage: slippage) ?? 0
                secondPoolAmountOut = try secondPool.getMinimumAmountOut(inputAmount: secondPoolAmountIn!, slippage: slippage)
            } else if let minAmountOut = minAmountOut {
                secondPoolAmountIn = try secondPool.getInputAmount(minimumReceiveAmount: minAmountOut, slippage: slippage) ?? 0
                firstPoolAmountIn = try firstPool.getInputAmount(minimumReceiveAmount: secondPoolAmountIn!, slippage: slippage)
            }
            
            guard let firstPoolAmountIn = firstPoolAmountIn,
                  let secondPoolAmountIn = secondPoolAmountIn,
                  let secondPoolAmountOut = secondPoolAmountOut
            else {
                throw FeeRelayerError.invalidAmount
            }
            
            let transitiveSwapData = TransitiveSwapData(
                from: firstPool.getSwapData(
                    transferAuthorityPubkey: newTransferAuthority ? transferAuthority.publicKey: account.publicKey,
                    amountIn: firstPoolAmountIn,
                    minAmountOut: secondPoolAmountIn
                ),
                to: secondPool.getSwapData(
                    transferAuthorityPubkey: newTransferAuthority ? transferAuthority.publicKey: account.publicKey,
                    amountIn: secondPoolAmountIn,
                    minAmountOut: secondPoolAmountOut
                ),
                transitTokenMintPubkey: transitTokenMintPubkey.base58EncodedString,
                needsCreateTransitTokenAccount: needsCreateTransitTokenAccount
            )
            return (swapData: transitiveSwapData, transferAuthorityAccount: newTransferAuthority ? transferAuthority: nil)
        }
    }
    
    func relayTransaction(
        _ context: FeeRelayerContext,
        preparedTransaction: PreparedTransaction,
        payingFeeToken: TokenAccount?,
        relayAccountStatus: RelayAccountStatus,
        additionalPaybackFee: UInt64,
        operationType: StatsInfo.OperationType,
        currency: String?
    ) async throws -> [String] {
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
        if paybackFee > 0 {
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
            } else {
                preparedTransaction.transaction.instructions.append(
                    try Program.transferSolInstruction(
                        userAuthorityAddress: account.publicKey,
                        recipient: feePayer,
                        lamports: paybackFee,
                        network: solanaApiClient.endpoint.network
                    )
                )
            }
        }
        
        #if DEBUG
//        if let decodedTransaction = preparedTransaction.transaction.jsonString {
//            Logger.log(message: decodedTransaction, event: .info)
//        }
        #endif
        
        // resign transaction
        try preparedTransaction.transaction.sign(signers: preparedTransaction.signers)
        return [try await feeRelayerAPIClient.sendTransaction(.relayTransaction(
            try .init(preparedTransaction: preparedTransaction)
        ))]
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
