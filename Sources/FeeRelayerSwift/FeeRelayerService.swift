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
    private let feeCalculator: FeeRelayerCalculator

    init(
        account: Account,
        orcaSwap: OrcaSwap,
        solanaApiClient: SolanaAPIClient,
        orcaSwapAPIClient: OrcaSwapAPIClient,
        feeCalculator: FeeRelayerCalculator,
        feeRelayerAPIClient: FeeRelayerAPIClient
    ) {
        self.account = account
        self.solanaApiClient = solanaApiClient
        self.orcaSwapAPIClient = orcaSwapAPIClient
        self.feeCalculator = feeCalculator
        self.orcaSwap = orcaSwap
        self.feeRelayerAPIClient = feeRelayerAPIClient
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
        fatalError("topUpAndRelayTransaction(_:fee:config:) has not been implemented")
        // 1. create context
//        let expectedFees = transactions.map {$0.expectedFee}
//        return self.checkAndTopUp(
//            expectedFee: .init(
//                transaction: expectedFees.map {$0.transaction}.reduce(UInt64(0), +),
//                accountBalances: expectedFees.map {$0.accountBalances}.reduce(UInt64(0), +)
//            ),
//            payingFeeToken: payingFeeToken
//        )
        
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
            // TODO: Уточнить у Лонга
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
        
        let transitToken = try getTransitToken(pools: topUpPools) ?! FeeRelayerError.unknown
        let blockhash = try await solanaApiClient.getRecentBlockhash(commitment: nil)
        let needsCreateTransitTokenAccount = try await checkIfNeedsCreateTransitTokenAccount(transitToken)
        
        let minimumRelayAccountBalance = context.minimumRelayAccountBalance
        let minimumTokenAccountBalance = context.minimumTokenAccountBalance
        let feePayerAddress = context.feePayerAddress
        let lamportsPerSignature = context.lamportsPerSignature
        let freeTransactionFeeLimit = context.usageStatus
//    network: self.solanaClient.endpoint.network,
//    sourceToken: sourceToken,
//    userAuthorityAddress: self.owner.publicKey,
//    userRelayAddress: self.userRelayAddress,
//    topUpPools: topUpPools,
//    targetAmount: targetAmount,
//    expectedFee: expectedFee,
//    blockhash: blockhash,
//    minimumRelayAccountBalance: minimumRelayAccountBalance,
//    minimumTokenAccountBalance: minimumTokenAccountBalance,
//    needsCreateUserRelayAccount: needsCreateUserRelayAddress,
//    feePayerAddress: feePayerAddress,
//    lamportsPerSignature: lamportsPerSignature,
//    freeTransactionFeeLimit: freeTransactionFeeLimit,
//    needsCreateTransitTokenAccount: needsCreateTransitTokenAccount,
//    transitTokenMintPubkey: try? PublicKey(string: transitToken?.mint),
//    transitTokenAccountAddress: try? PublicKey(string: transitToken?.address)
//        // STEP 3: prepare for topUp
//        let topUpTransaction: (FeeRelayerRelaySwapType, PreparedTransaction) = try self.prepareForTopUp(
//            network: solanaApiClient.endpoint.network.toPublicKey(),
//            sourceToken: sourceToken,
//            userAuthorityAddress: account.publicKey,
//            userRelayAddress: user,
//            topUpPools: <#T##PoolsPair#>,
//            targetAmount: <#T##UInt64#>,
//            expectedFee: <#T##UInt64#>,
//            blockhash: <#T##String#>,
//            minimumRelayAccountBalance: <#T##UInt64#>,
//            minimumTokenAccountBalance: <#T##UInt64#>,
//            needsCreateUserRelayAccount: <#T##Bool#>,
//            feePayerAddress: <#T##String#>,
//            lamportsPerSignature: <#T##UInt64#>,
//            freeTransactionFeeLimit: <#T##UsageStatus?#>,
//            needsCreateTransitTokenAccount: <#T##Bool?#>,
//            transitTokenMintPubkey: <#T##PublicKey?#>,
//            transitTokenAccountAddress: <#T##PublicKey?#>
//        )
        
        fatalError()
    }
    
    internal func getTransitToken(pools: PoolsPair) throws -> TokenAccount? {
        guard let transitTokenMintPubkey = try getTransitTokenMintPubkey(pools: pools) else { return nil }

        let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
            user: account.publicKey,
            transitTokenMint: transitTokenMintPubkey,
            network: solanaApiClient.endpoint.network
        )

        return TokenAccount(
            address: transitTokenAccountAddress,
            mint: transitTokenMintPubkey
        )
    }
    
    internal func getTransitTokenMintPubkey(pools: PoolsPair) throws -> PublicKey? {
        guard pools.count == 2 else { return nil }
        let interTokenName = pools[0].tokenBName
        return try PublicKey(string: orcaSwap.getMint(tokenName: interTokenName))
    }
    
    private func checkIfNeedsCreateTransitTokenAccount(_ token: TokenAccount) async throws -> Bool? {
        do {
            let accountInfo: BufferInfo<AccountInfo>? = try await solanaApiClient.getAccountInfo(account: token.address.base58EncodedString)
            // TODO: Уточнить у Лонга
            // detect if destination address is already a SPLToken address
            return !(accountInfo?.data.mint == token.address)
        } catch {
            return true
        }
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
        feePayerAddress: String,
        lamportsPerSignature: UInt64,
        freeTransactionFeeLimit: UsageStatus?,
        needsCreateTransitTokenAccount: Bool?,
        transitTokenMintPubkey: PublicKey?,
        transitTokenAccountAddress: PublicKey?
    ) throws -> (swapData: FeeRelayerRelaySwapType, preparedTransaction: PreparedTransaction) {
        // assertion
        let userSourceTokenAccountAddress = sourceToken.address
        let sourceTokenMintAddress = sourceToken.mint
        let feePayerAddress = try PublicKey(string: feePayerAddress) ?! FeeRelayerError.unknown
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
