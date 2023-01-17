//
//  File.swift
//
//
//  Created by Giang Long Tran on 10.01.2023.
//

import Foundation
import OrcaSwapSwift
import SolanaSwift

public class RelayServiceV2Impl: RelayService {
    // MARK: - Properties

    private(set) var feeRelayerAPIClient: FeeRelayerAPIClient
    private(set) var solanaApiClient: SolanaAPIClient
    private(set) var orcaSwap: OrcaSwapType
    private(set) var accountStorage: SolanaAccountStorage
    public let feeCalculator: RelayFeeCalculator
    private let deviceType: StatsInfo.DeviceType
    private let buildNumber: String?
    private let environment: StatsInfo.Environment

    public var account: Account {
        accountStorage.account!
    }

    // MARK: - Initializer

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

    public func checkAndTopUp(_ context: RelayContext, expectedFee: SolanaSwift.FeeAmount, payingFeeToken: TokenAccount?) async throws -> [String]? {
        fatalError()
    }

    public func relayTransaction(_ preparedTransaction: SolanaSwift.PreparedTransaction, config configuration: FeeRelayerConfiguration) async throws -> String {
        fatalError()
    }

    public func topUpAndRelayTransaction(_ context: RelayContext, _ preparedTransaction: SolanaSwift.PreparedTransaction, fee payingFeeToken: TokenAccount?, config configuration: FeeRelayerConfiguration) async throws -> SolanaSwift.TransactionID {
        // Paying fee in token
        guard let payingFeeToken = payingFeeToken else { throw FeeRelayerError.feePayingTokenMissing }

        var relayInstructions: [TransactionInstruction] = []

        // The amount should convert complet a relay transaction
        let expectedFee: FeeAmount = try await feeCalculator.calculateNeededTopUpAmount(
            context,
            expectedFee: preparedTransaction.expectedFee,
            payingTokenMint: payingFeeToken.mint
        )

        if expectedFee.total > 0 {
            // Step 1
            // Check relay account. If account doesn't exists we have to create it.
            if case .notYetCreated = context.relayAccountStatus {
                relayInstructions.append(
                    SystemProgram.transferInstruction(
                        from: context.feePayerAddress,
                        to: try RelayProgram.getUserRelayAddress(
                            user: account.publicKey,
                            network: solanaApiClient.endpoint.network
                        ),
                        lamports: context.minimumRelayAccountBalance
                    )
                )
            }

            // Step 2
            let topUpPools: PoolsPair

            // Find pool pair from paying fee token to SOL
            try await orcaSwap.load()
            let tradableTopUpPoolsPair = try await orcaSwap.getTradablePoolsPairs(
                fromMint: payingFeeToken.mint.base58EncodedString,
                toMint: PublicKey.wrappedSOLMint.base58EncodedString
            )

            if let directSwapPools = tradableTopUpPoolsPair.first(where: { $0.count == 1 }) {
                topUpPools = directSwapPools
            } else if let transitiveSwapPools = try orcaSwap.findBestPoolsPairForEstimatedAmount(expectedFee.total, from: tradableTopUpPoolsPair) {
                // if direct swap is not available, use transitive swap
                topUpPools = transitiveSwapPools
            } else {
                throw FeeRelayerError.swapPoolsNotFound
            }

            // Step 3
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

            let topUpTransactions = try await prepareForTopUp(
                network: solanaApiClient.endpoint.network,
                sourceToken: payingFeeToken,
                userAuthorityAddress: account.publicKey,
                userRelayAddress: RelayProgram.getUserRelayAddress(user: account.publicKey, network: solanaApiClient.endpoint.network),
                topUpPools: topUpPools,
                targetAmount: expectedFee.total,
                minimumRelayAccountBalance: context.minimumRelayAccountBalance,
                minimumTokenAccountBalance: context.minimumTokenAccountBalance,
                needsCreateUserRelayAccount: context.relayAccountStatus == .notYetCreated,
                feePayerAddress: context.feePayerAddress,
                lamportsPerSignature: context.lamportsPerSignature,
                freeTransactionFeeLimit: context.usageStatus,
                needsCreateTransitTokenAccount: needsCreateTransitTokenAccount,
                transitTokenMintPubkey: transitToken?.mint,
                transitTokenAccountAddress: transitToken?.address
            )

            relayInstructions.append(contentsOf: topUpTransactions)
        }

        relayInstructions.append(contentsOf: preparedTransaction.transaction.instructions)

        if expectedFee.total > 0 {
            relayInstructions.append(
                try RelayProgram.transferSolInstruction(
                    userAuthorityAddress: account.publicKey,
                    recipient: context.feePayerAddress,
                    lamports: expectedFee.total,
                    network: solanaApiClient.endpoint.network
                )
            )
        }

//        var relayTransaction: Transaction = .init(
//            instructions: relayInstructions,
//            recentBlockhash: try await solanaApiClient.getRecentBlockhash(),
//            feePayer: context.feePayerAddress
//        )

        let feePayer: Account = try .init(
            secretKey: Data(Base58.decode("5xiGSmCkMLw3Y3uW9qhPCkxS3jWt5qNwL7MkS29TEPPRTptcBTzYe1EUcfUCqbsg9uA2JFu2vynQDLpPmf7stPq7"))
        )

        let (createLookUpInstruction, lookupTable) = try LookUpTableProgram.createLookupTable(
            authority: feePayer.publicKey,
            payer: feePayer.publicKey,
            recentSlot: try await solanaApiClient.getSlot()
        )

        let insertAddressIntoLookUpTable = LookUpTableProgram.extendLookupTable(
            lookupTable: lookupTable,
            authority: feePayer.publicKey,
            payer: feePayer.publicKey, addresses: [
                try! PublicKey(string: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"),
                try! PublicKey(string: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
                try! PublicKey(string: "SysvarRent111111111111111111111111111111111"),
                try! PublicKey(string: "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP"),
                try! PublicKey(string: "12YKFL4mnZz6CBEGePrf293mEzueQM3h8VLPUJsKpGs9"),
                try! PublicKey(string: "11111111111111111111111111111111"),
                try! PublicKey(string: "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj"),
                try! PublicKey(string: "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj"),
            ]
        )

//        var setupLookupTableTrx: VersionedTransaction = .init(
//            message: .v0(
//                try TransactionMessage(
//                    instructions: [createLookUpInstruction, insertAddressIntoLookUpTable],
//                    recentBlockhash: try await solanaApiClient.getRecentBlockhash(),
//                    payerKey: context.feePayerAddress
//                ).compileToV0Message()
//            )
//        )
//
//        try setupLookupTableTrx.sign(signers: [feePayer])
//        let serializedTransaction1 = try setupLookupTableTrx.serialize().base64EncodedString()
//        print(serializedTransaction1)
//        let signature = try await solanaApiClient.sendTransaction(transaction: serializedTransaction1, configs: .init(encoding: "base64")!)
//        try await solanaApiClient.waitForConfirmation(signature: signature, ignoreStatus: false)

        var lookupTableAccount = try await solanaApiClient.getAddressLookupTable(accountKey: try PublicKey(string: "8hqDMHNDNr6vG7MoDX1QtkDbQKQLG3x1SSPTZcXxBpWN"))!

        var relayTransactionWithTable: VersionedTransaction = .init(
            message: .v0(
                try TransactionMessage(
                    instructions: relayInstructions,
                    recentBlockhash: try await solanaApiClient.getRecentBlockhash(),
                    payerKey: context.feePayerAddress
                ).compileToV0Message(addressLookupTableAccounts: [lookupTableAccount])
            )
        )

        var relayTransactionWithoutTable: VersionedTransaction = .init(
            message: .legacy(
                try TransactionMessage(
                    instructions: relayInstructions,
                    recentBlockhash: try await solanaApiClient.getRecentBlockhash(),
                    payerKey: context.feePayerAddress
                ).compileToLegacyMessage()
            )
        )

        try relayTransactionWithTable.sign(signers: [
            account,
            feePayer,
        ])

        try relayTransactionWithoutTable.sign(signers: [
            account,
            feePayer,
        ])

        print((try relayTransactionWithTable.serialize()).count)
        print((try relayTransactionWithoutTable.serialize()).count)

        let serializedTransaction2 = try relayTransactionWithTable.serialize().base64EncodedString()
        print(serializedTransaction2)
        return try await solanaApiClient.sendTransaction(transaction: serializedTransaction2, configs: .init(encoding: "base64")!)

//        var preparedTrx = SolanaSwift.PreparedTransaction(transaction: relayTransaction, signers: [account], expectedFee: expectedFee)
//        try preparedTrx.sign()

//        print(try relayTransaction.serialize(requiredAllSignatures: false).base64EncodedString())

//        do {
//            return try await feeRelayerAPIClient.sendTransaction(
//                .relayTransaction(
//                    .init(
//                        preparedTransaction: preparedTrx,
//                        statsInfo: .init(
//                            operationType: configuration.operationType,
//                            deviceType: deviceType,
//                            currency: configuration.currency,
//                            build: buildNumber,
//                            environment: environment
//                        )
//                    )
//                )
//            )
//        } catch {
//            print(error)
//            throw error
//        }
    }

    public func topUpAndRelayTransaction(_ context: RelayContext, _ preparedTransaction: [SolanaSwift.PreparedTransaction], fee payingFeeToken: TokenAccount?, config configuration: FeeRelayerConfiguration) async throws -> [SolanaSwift.TransactionID] {
        fatalError()
    }

    public func topUpAndSignRelayTransaction(_ context: RelayContext, _ preparedTransaction: SolanaSwift.PreparedTransaction, fee payingFeeToken: TokenAccount?, config configuration: FeeRelayerConfiguration) async throws -> SolanaSwift.TransactionID {
        fatalError()
    }

    public func topUpAndSignRelayTransaction(_ context: RelayContext, _ preparedTransaction: [SolanaSwift.PreparedTransaction], fee payingFeeToken: TokenAccount?, config configuration: FeeRelayerConfiguration) async throws -> [SolanaSwift.TransactionID] {
        fatalError()
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
                transferAuthorityPubkey: newTransferAuthority ? transferAuthority.publicKey : account.publicKey,
                amountIn: amountIn,
                minAmountOut: minAmountOut
            )
            return (swapData: directSwapData, transferAuthorityAccount: newTransferAuthority ? transferAuthority : nil)
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
                    transferAuthorityPubkey: newTransferAuthority ? transferAuthority.publicKey : account.publicKey,
                    amountIn: firstPoolAmountIn,
                    minAmountOut: secondPoolAmountIn
                ),
                to: secondPool.getSwapData(
                    transferAuthorityPubkey: newTransferAuthority ? transferAuthority.publicKey : account.publicKey,
                    amountIn: secondPoolAmountIn,
                    minAmountOut: secondPoolAmountOut
                ),
                transitTokenMintPubkey: transitTokenMintPubkey.base58EncodedString,
                needsCreateTransitTokenAccount: needsCreateTransitTokenAccount
            )
            return (swapData: transitiveSwapData, transferAuthorityAccount: newTransferAuthority ? transferAuthority : nil)
        }
    }

    // TODO: Dublicated
    private func prepareForTopUp(
        network: Network,
        sourceToken: TokenAccount,
        userAuthorityAddress: PublicKey,
        userRelayAddress: PublicKey,
        topUpPools: PoolsPair,
        targetAmount: UInt64,
        minimumRelayAccountBalance: UInt64,
        minimumTokenAccountBalance: UInt64,
        needsCreateUserRelayAccount: Bool,
        feePayerAddress: PublicKey,
        lamportsPerSignature: UInt64,
        freeTransactionFeeLimit: UsageStatus?,
        needsCreateTransitTokenAccount: Bool?,
        transitTokenMintPubkey: PublicKey?,
        transitTokenAccountAddress: PublicKey?
    ) async throws -> [TransactionInstruction] {
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
            // TODO: Replace fatal error.
            fatalError("unsupported swap type")
        }

        return instructions
    }
}

public extension RelayServiceV2Impl {
    class RelayCalculator: DefaultRelayFeeCalculator {
        override public init() {
            super.init()
        }

        override func calculateMinTopUpAmount(_ context: RelayContext, expectedFee: FeeAmount, payingTokenMint: PublicKey?) -> FeeAmount {
            var neededAmount = expectedFee

            // expected fees (+ fee relay signer)
            let expectedTransactionFee = expectedFee.transaction + context.lamportsPerSignature

            // is transaction free
            if context.usageStatus.isFreeTransactionFeeAvailable(transactionFee: expectedTransactionFee)
            {
                neededAmount.transaction = 0
            } else {
                neededAmount.transaction = expectedTransactionFee
            }

            neededAmount.transaction = expectedTransactionFee

            // transaction is totally free
            if neededAmount.total == 0 {
                return neededAmount
            }

            // TODO: Dublicated code!
            let neededAmountWithoutCheckingRelayAccount = neededAmount
            let minimumRelayAccountBalance = context.minimumRelayAccountBalance

            // check if relay account current balance can cover part of needed amount
            if var relayAccountBalance = context.relayAccountStatus.balance {
                if relayAccountBalance < minimumRelayAccountBalance {
                    neededAmount.transaction += minimumRelayAccountBalance - relayAccountBalance
                } else {
                    relayAccountBalance -= minimumRelayAccountBalance

                    // if relayAccountBalance has enough balance to cover transaction fee
                    if relayAccountBalance >= neededAmount.transaction {
                        relayAccountBalance -= neededAmount.transaction
                        neededAmount.transaction = 0

                        // if relayAccountBalance has enough balance to cover accountBalances fee too
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
            } else {
                neededAmount.transaction += minimumRelayAccountBalance
            }

            // if relay account could not cover all fees and paying token is WSOL, the compensation will be done without the existense of relay account
            if neededAmount.total > 0, payingTokenMint == PublicKey.wrappedSOLMint {
                return neededAmountWithoutCheckingRelayAccount
            }

            return neededAmount
        }

        override public func calculateExpectedFeeForTopUp(_ context: RelayContext) throws -> UInt64 {
            // TODO: Throw error
            0
        }
    }
}
