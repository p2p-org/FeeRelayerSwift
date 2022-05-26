// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

class SwapFeeRelayerImpl: SwapFeeRelayer {
    private let accountStorage: SolanaAccountStorage
    private let feeRelayerAPIClient: FeeRelayerAPIClient
    private let solanaApiClient: SolanaAPIClient
    private let orcaSwap: OrcaSwap

    private let cache: Cache<CacheKey, Any>
    private let helper: FeeRelayHelper
    private let swapCalculator: SwapFeeRelayerCalculator
    
    // TODO: fix
    private let feeRelayerCalculator: FeeRelayerCalculator!

    init(
        accountStorage: SolanaAccountStorage,
        feeRelayerAPIClient: FeeRelayerAPIClient,
        solanaApiClient: SolanaAPIClient,
        orcaSwap: OrcaSwap,
        cache: Cache<CacheKey, Any>
    ) {
        self.accountStorage = accountStorage
        self.feeRelayerAPIClient = feeRelayerAPIClient
        self.solanaApiClient = solanaApiClient
        self.orcaSwap = orcaSwap
        self.cache = cache

        helper = FeeRelayHelper(
            cache: cache,
            accountStorage: accountStorage,
            feeRelayerAPIClient: feeRelayerAPIClient,
            solanaApiClient: solanaApiClient
        )

        swapCalculator = DefaultSwapFeeRelayerCalculator(
            solanaApiClient: solanaApiClient,
            accountStorage: accountStorage,
            helper: helper
        )
    }

    func prepareSwapTransaction(
        sourceToken _: TokenAccount,
        destinationTokenMint _: PublicKey,
        destinationAddress _: PublicKey?,
        fee _: TokenAccount,
        swapPools: PoolsPair,
        inputAmount _: UInt64,
        slippage _: Double
    ) async throws
    -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
        try await helper.clear()
        try await helper.warmUp()

        let transitToken = try? getTransitToken(pools: swapPools)

        fatalError(
            "prepareSwapTransaction(sourceToken:destinationTokenMint:destinationAddress:fee:swapPools:inputAmount:slippage:) has not been implemented"
        )
    }

    func prepareForTopUpAndSwap(
        source: TokenAccount,
        destinationTokenMint: PublicKey,
        destinationAddress: PublicKey?,
        payingFeeToken: TokenAccount?,
        swapPools: PoolsPair
    ) async throws {
        let relayAccountStatus = try await helper.getRelayAccountStatus()
        let usageStatus = try await helper.getUsageStatus()

        let tradablePoolsPair: [PoolsPair]
        if let payingFeeToken = payingFeeToken {
            tradablePoolsPair = try await orcaSwap.getTradablePoolsPairs(
                fromMint: payingFeeToken.mint.base58EncodedString,
                toMint: PublicKey.wrappedSOLMint.base58EncodedString
            )
        } else {
            tradablePoolsPair = []
        }

        let swappingFee = try await swapCalculator.calculateSwappingNetworkFees(
            swapPools: swapPools,
            sourceTokenMint: source.mint,
            destinationTokenMint: destinationTokenMint,
            destinationAddress: destinationAddress
        )

        // TOP UP
        let topUpPreparedParam: TopUpPreparedParams?
        if payingFeeToken?.mint == PublicKey.wrappedSOLMint {
            topUpPreparedParam = nil
        } else {
            if let relayAccountBalance = relayAccountStatus.balance, relayAccountBalance >= swappingFee.total {
                topUpPreparedParam = nil
            } else {
                // STEP 2.2: Else
                
                // Get real amounts needed for topping up
                let topUpAmount = try feeRelayerCalculator.calculateNeededTopUpAmount(
                    expectedFee: swappingFee,
                    payingTokenMint: payingFeeToken?.mint,
                    freeTransactionFeeLimit: freeTransactionFeeLimit,
                    relayAccountStatus: relayAccountStatus
                )
                    .total
                let expectedFee = try calculateExpectedFeeForTopUp(
                    relayAccountStatus: relayAccountStatus,
                    freeTransactionFeeLimit: freeTransactionFeeLimit
                )

                // Get pools
                let topUpPools: PoolsPair
                if let bestPools = try orcaSwapClient.findBestPoolsPairForEstimatedAmount(
                    topUpAmount,
                    from: tradableTopUpPoolsPair
                ) {
                    topUpPools = bestPools
                } else {
                    throw FeeRelayer.Error.swapPoolsNotFound
                }

                topUpPreparedParam = .init(
                    amount: topUpAmount,
                    expectedFee: expectedFee,
                    poolsPair: topUpPools
                )
            }
        }
    }

    internal func getTransitToken(pools: PoolsPair) throws -> TokenInfo? {
        guard let transitTokenMintPubkey = try getTransitTokenMintPubkey(pools: pools) else { return nil }

        let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
            user: try accountStorage.pubkey,
            transitTokenMint: transitTokenMintPubkey,
            network: solanaApiClient.endpoint.network
        )

        return TokenInfo(
            address: transitTokenAccountAddress.base58EncodedString,
            mint: transitTokenMintPubkey.base58EncodedString
        )
    }

    internal func getTransitTokenMintPubkey(pools: PoolsPair) throws -> PublicKey? {
        guard pools.count == 2 else { return nil }
        let interTokenName = pools[0].tokenBName
        return try PublicKey(string: orcaSwap.getMint(tokenName: interTokenName))
    }
}
