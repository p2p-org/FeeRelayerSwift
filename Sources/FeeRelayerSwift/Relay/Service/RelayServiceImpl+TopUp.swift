import Foundation
import SolanaSwift
import OrcaSwapSwift

extension RelayServiceImpl {
    /// Check and top up (if needed)
    /// - Parameters:
    ///   - context: current context of Relay's service
    ///   - expectedFee: expected fee for a transaction
    ///   - payingFeeToken: token to pay fee
    /// - Returns: nil if top up is not needed, transactions' signatures if top up has been sent
    public func checkAndTopUp(
        _ context: RelayContext,
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
        var (params, needsCreateUserRelayAddress): (TopUpPreparedParams?, Bool)
        if topUpAmount.total <= 0 {
            // no need to top up
            (params, needsCreateUserRelayAddress) = (nil, context.relayAccountStatus == .notYetCreated)
        } else {
            // top up
            let prepareResult = try await prepareForTopUp(
                context,
                topUpAmount: topUpAmount.total,
                payingFeeToken: try payingFeeToken ?! FeeRelayerError.unknown
            )
            (params, needsCreateUserRelayAddress) = (prepareResult, context.relayAccountStatus == .notYetCreated)
        }

        if let topUpParams = params, let payingFeeToken = payingFeeToken {
            return try await topUp(
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
    
    /// Prepare parameters for top up
    /// - Parameters:
    ///   - context: current context of Relay's service
    ///   - topUpAmount: amount that needs to top up
    ///   - payingFeeToken: token to pay fee
    ///   - forceUsingTransitiveSwap: force using transitive swap (for testing purpose only)
    /// - Returns: Prepared params for top up
    func prepareForTopUp(
        _ context: RelayContext,
        topUpAmount: Lamports,
        payingFeeToken: TokenAccount,
        forceUsingTransitiveSwap: Bool = false // true for testing purpose only
    ) async throws -> TopUpPreparedParams {
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
    
    /// Top up to fill relay account before relaying any transaction
    /// - Parameters:
    ///   - context: current context of Relay's service
    ///   - needsCreateUserRelayAddress: indicate if creating user relay address is required
    ///   - sourceToken: token to top up from
    ///   - targetAmount: amount that needs to be topped up
    ///   - topUpPools: pools used to swap to top up
    ///   - expectedFee: expected fee of the transaction that requires top up
    /// - Returns: transaction's signature
    func topUp(
        _ context: RelayContext,
        needsCreateUserRelayAddress: Bool,
        sourceToken: TokenAccount,
        targetAmount: UInt64,
        topUpPools: PoolsPair,
        expectedFee: UInt64
    ) async throws -> [String] {
        
        let transitTokenAccountManager = TransitTokenAccountManagerImpl(
            owner: account.publicKey,
            solanaAPIClient: solanaApiClient,
            orcaSwap: orcaSwap
        )
        
        let transitToken = try transitTokenAccountManager.getTransitToken(
            pools: topUpPools
        )
        
        let needsCreateTransitTokenAccount = try await transitTokenAccountManager.checkIfNeedsCreateTransitTokenAccount(
            transitToken: transitToken
        )
        
        let blockhash = try await solanaApiClient.getRecentBlockhash(commitment: nil)
        let minimumRelayAccountBalance = context.minimumRelayAccountBalance
        let minimumTokenAccountBalance = context.minimumTokenAccountBalance
        let feePayerAddress = context.feePayerAddress
        let lamportsPerSignature = context.lamportsPerSignature
        let freeTransactionFeeLimit = context.usageStatus

        // STEP 3: prepare for topUp
        let topUpTransaction: (swapData: FeeRelayerRelaySwapType, preparedTransaction: PreparedTransaction) = try await self.prepareForTopUp(
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
                    buildNumber: self.buildNumber,
                    environment: self.environment
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
    ) async throws -> (swapData: FeeRelayerRelaySwapType, preparedTransaction: PreparedTransaction) {
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
        let swap = try await prepareSwapData(
            network: network,
            pools: topUpPools,
            inputAmount: nil,
            minAmountOut: targetAmount,
            slippage: FeeRelayerConstants.topUpSlippage,
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
                try RelayProgram.topUpSwapInstruction(
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
                        amount: swap.from.amountIn
                    )
                )
            }
            
            // create transit token account
            if needsCreateTransitTokenAccount == true, let transitTokenAccountAddress = transitTokenAccountAddress {
                instructions.append(
                    try RelayProgram.createTransitTokenAccountInstruction(
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
                try RelayProgram.topUpSwapInstruction(
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
            try RelayProgram.transferSolInstruction(
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
        
       if let decodedTransaction = transaction.jsonString {
           print(decodedTransaction)
       }
        
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
    ) async throws -> (swapData: FeeRelayerRelaySwapType, transferAuthorityAccount: Account?) {
        // preconditions
        guard pools.count > 0 && pools.count <= 2 else { throw FeeRelayerError.swapPoolsNotFound }
        guard !(inputAmount == nil && minAmountOut == nil) else { throw FeeRelayerError.invalidAmount }
        
        // create transferAuthority
        let transferAuthority = try await Account(network: network)
        
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
