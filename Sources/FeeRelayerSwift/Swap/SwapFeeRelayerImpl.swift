// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import OrcaSwapSwift
import SolanaSwift

class SwapFeeRelayerImpl: SwapFeeRelayer {
    private let userAccount: Account
    private let feeRelayerAPIClient: FeeRelayerAPIClient
    private let solanaApiClient: SolanaAPIClient
    private let orcaSwap: OrcaSwap

    private let swapCalculator: SwapFeeRelayerCalculator
    private var feeRelayerCalculator: FeeRelayerCalculator = DefaultFreeRelayerCalculator()

    init(
        userAccount: Account,
        feeRelayerAPIClient: FeeRelayerAPIClient,
        solanaApiClient: SolanaAPIClient,
        orcaSwap: OrcaSwap
    ) {
        self.userAccount = userAccount
        self.feeRelayerAPIClient = feeRelayerAPIClient
        self.solanaApiClient = solanaApiClient
        self.orcaSwap = orcaSwap

        swapCalculator = DefaultSwapFeeRelayerCalculator(
            solanaApiClient: solanaApiClient,
            userAccount: userAccount
        )
    }
    
    var calculator: SwapFeeRelayerCalculator { swapCalculator }

    func prepareSwapTransaction(
        _ context: FeeRelayerContext,
        sourceToken: TokenAccount,
        destinationTokenMint: PublicKey,
        destinationAddress: PublicKey?,
        fee: TokenAccount,
        swapPools: PoolsPair,
        inputAmount : UInt64,
        slippage: Double
    ) async throws
    -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
        let preparedParams = try await prepareForTopUpAndSwap(
            context,
            source: sourceToken,
            destinationTokenMint: destinationTokenMint,
            destinationAddress: destinationAddress,
            payingFeeToken: fee,
            swapPools: swapPools
        )
        
        let latestBlockhash = try await solanaApiClient.getRecentBlockhash(commitment: nil)
    
        var buildContext = SwapTransactionBuilder.BuildContext(
            feeRelayerContext: context,
            solanaApiClient: solanaApiClient,
            orcaSwap: orcaSwap,
            config: .init(
                userAccount: userAccount,
                pools:  preparedParams.actionFeesAndPools.poolsPair,
                inputAmount: inputAmount,
                slippage: slippage,
                sourceAccount: sourceToken,
                destinationTokenMint: destinationTokenMint,
                destinationAddress: destinationAddress,
                blockhash: latestBlockhash
            ),
            env: .init()
        )
        
        return try await SwapTransactionBuilder.prepareSwapTransaction(&buildContext)
    }

    func prepareForTopUpAndSwap(
        _ context: FeeRelayerContext,
        source: TokenAccount,
        destinationTokenMint: PublicKey,
        destinationAddress: PublicKey?,
        payingFeeToken: TokenAccount?,
        swapPools: PoolsPair
    ) async throws -> TopUpAndActionPreparedParams {
        let tradablePoolsPair: [PoolsPair]
        if let payingFeeToken = payingFeeToken {
            tradablePoolsPair = try await orcaSwap.getTradablePoolsPairs(
                fromMint: payingFeeToken.mint.base58EncodedString,
                toMint: PublicKey.wrappedSOLMint.base58EncodedString
            )
        } else {
            tradablePoolsPair = []
        }

        let swappingFee: FeeAmount = try await swapCalculator.calculateSwappingNetworkFees(
            context,
            swapPools: swapPools,
            sourceTokenMint: source.mint,
            destinationTokenMint: destinationTokenMint,
            destinationAddress: destinationAddress
        )

        // TOP UP
        let topUpPreparedParam: TopUpPreparedParams?
        if
            payingFeeToken?.mint != PublicKey.wrappedSOLMint,
            let balance = context.relayAccountStatus.balance,
            balance < swappingFee.total
        {
            let topUpAmount = try await feeRelayerCalculator.calculateNeededTopUpAmount(
                context,
                expectedFee: swappingFee,
                payingTokenMint: payingFeeToken?.mint
            ).total

            let expectedFee = try feeRelayerCalculator.calculateExpectedFeeForTopUp(context)

            // Get pools
            guard let topUpPools = try orcaSwap.findBestPoolsPairForEstimatedAmount(
                topUpAmount,
                from: tradablePoolsPair
            ) else {
                throw FeeRelayerError.swapPoolsNotFound
            }

            topUpPreparedParam = .init(amount: topUpAmount, expectedFee: expectedFee, poolsPair: topUpPools)
        } else {
            topUpPreparedParam = nil
        }

        return TopUpAndActionPreparedParams(
            topUpPreparedParam: topUpPreparedParam,
            actionFeesAndPools: .init(fee: swappingFee, poolsPair: swapPools)
        )
    }
}
