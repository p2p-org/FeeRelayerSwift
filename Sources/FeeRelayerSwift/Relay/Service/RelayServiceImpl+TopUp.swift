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
        let params: TopUpPreparedParams?
        if topUpAmount.total <= 0 {
            // no need to top up
            params = nil
        } else {
            // top up
            params = try await prepareForTopUp(
                context,
                topUpAmount: topUpAmount.total,
                payingFeeToken: try payingFeeToken ?! FeeRelayerError.unknown
            )
        }

        if let topUpParams = params, let payingFeeToken = payingFeeToken {
            return try await topUp(
                context,
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
        let freeTransactionFeeLimit = context.usageStatus

        // STEP 3: prepare for topUp
        let topUpTransactionBuilder = TopUpTransactionBuilderImpl()
        let topUpTransaction: (swapData: FeeRelayerRelaySwapType, preparedTransaction: PreparedTransaction) =
            try await topUpTransactionBuilder.buildTopUpTransaction(
                account: account,
                context: context,
                network: solanaApiClient.endpoint.network,
                sourceToken: sourceToken,
                topUpPools: topUpPools,
                targetAmount: targetAmount,
                expectedFee: expectedFee,
                blockhash: blockhash,
                usageStatus: freeTransactionFeeLimit,
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
}
