//
//  FeeRelayer.Relay+TopUp.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 07/02/2022.
//

import Foundation
import RxSwift
import SolanaSwift
import OrcaSwapSwift

extension FeeRelayer.Relay {
    /// Submits a signed top up swap transaction to the backend for processing
    func topUp(
        needsCreateUserRelayAddress: Bool,
        sourceToken: TokenInfo,
        amount: UInt64,
        topUpPools: OrcaSwap.PoolsPair,
        topUpFee: SolanaSDK.FeeAmount
    ) -> Single<[String]> {
        guard let owner = accountStorage.account else {return .error(FeeRelayer.Error.unauthorized)}
        
        // get recent blockhash
        return solanaClient.getRecentBlockhash(commitment: nil)
            .observe(on: ConcurrentDispatchQueueScheduler(qos: .default))
            .flatMap { [weak self] recentBlockhash in
                guard let self = self else {throw FeeRelayer.Error.unknown}
                guard let info = self.info else { throw FeeRelayer.Error.relayInfoMissing }
                
                var amount = amount
                if needsCreateUserRelayAddress {
                    amount += self.getRelayAccountCreationCost()
                }
                
                // STEP 3: prepare for topUp
                let topUpTransaction = try self.prepareForTopUp(
                    network: self.solanaClient.endpoint.network,
                    sourceToken: sourceToken,
                    userAuthorityAddress: owner.publicKey,
                    userRelayAddress: self.userRelayAddress,
                    topUpPools: topUpPools,
                    amount: amount,
                    feeAmount: topUpFee,
                    blockhash: recentBlockhash,
                    minimumRelayAccountBalance: info.minimumRelayAccountBalance,
                    minimumTokenAccountBalance: info.minimumTokenAccountBalance,
                    needsCreateUserRelayAccount: needsCreateUserRelayAddress,
                    feePayerAddress: info.feePayerAddress,
                    lamportsPerSignature: info.lamportsPerSignature
                )
                
                // STEP 4: send transaction
                let signatures = try self.getSignatures(
                    transaction: topUpTransaction.transaction,
                    owner: owner,
                    transferAuthorityAccount: topUpTransaction.transferAuthorityAccount
                )
                return self.apiClient.sendTransaction(
                    .relayTopUpWithSwap(
                        .init(
                            userSourceTokenAccountPubkey: sourceToken.address,
                            sourceTokenMintPubkey: sourceToken.mint,
                            userAuthorityPubkey: owner.publicKey.base58EncodedString,
                            topUpSwap: .init(topUpTransaction.swapData),
                            feeAmount: topUpFee.accountBalances,
                            signatures: signatures,
                            blockhash: recentBlockhash
                        )
                    ),
                    decodedTo: [String].self
                )
                    .do(onSuccess: {_ in
                        Logger.log(message: "Top up \(amount) into \(self.userRelayAddress) completed", event: .info)
                    }, onSubscribe: {
                        Logger.log(message: "Top up \(amount) into \(self.userRelayAddress) processing", event: .info)
                    })
            }
            .observe(on: MainScheduler.instance)
    }
    
    // MARK: - Helpers
    func prepareForTopUp(
        amount: SolanaSDK.FeeAmount,
        payingFeeToken: TokenInfo,
        relayAccountStatus: RelayAccountStatus
    ) -> Single<TopUpPreparedParams> {
        // form request
        orcaSwapClient
            .getTradablePoolsPairs(
                fromMint: payingFeeToken.mint,
                toMint: SolanaSDK.PublicKey.wrappedSOLMint.base58EncodedString
            )
            .map { [weak self] tradableTopUpPoolsPair in
                guard let self = self else { throw FeeRelayer.Error.unknown }
                
                
                // TOP UP
                let topUpFeesAndPools: FeesAndPools?
                var topUpAmount: UInt64?
                if let relayAccountBalance = relayAccountStatus.balance,
                   relayAccountBalance >= amount.total {
                    topUpFeesAndPools = nil
                }
                // STEP 2.2: Else
                else {
                    // Get best poolpairs for topping up
                    topUpAmount = amount.total - (relayAccountStatus.balance ?? 0)
                    
                    guard let topUpPools = try self.orcaSwapClient.findBestPoolsPairForEstimatedAmount(topUpAmount!, from: tradableTopUpPoolsPair) else {
                        throw FeeRelayer.Error.swapPoolsNotFound
                    }
                    let topUpFee = try self.calculateTopUpFee(topUpPools: topUpPools, relayAccountStatus: relayAccountStatus)
                    topUpFeesAndPools = .init(fee: topUpFee, poolsPair: topUpPools)
                }
                
                return .init(
                    topUpFeesAndPools: topUpFeesAndPools,
                    topUpAmount: topUpAmount
                )
            }
    }
    
    /// Calculate needed fee for topup transaction by forming fake transaction
    func calculateTopUpFee(topUpPools: OrcaSwap.PoolsPair, relayAccountStatus: RelayAccountStatus) throws -> SolanaSDK.FeeAmount {
        guard let info = info else {throw FeeRelayer.Error.relayInfoMissing}
        let fee = try prepareForTopUp(
            network: solanaClient.endpoint.network,
            sourceToken: .init(
                address: "C5B13tQA4pq1zEVSVkWbWni51xdWB16C2QsC72URq9AJ", // fake
                mint: "2Kc38rfQ49DFaKHQaWbijkE7fcymUMLY5guUiUsDmFfn" // fake
            ),
            userAuthorityAddress: "5bYReP8iw5UuLVS5wmnXfEfrYCKdiQ1FFAZQao8JqY7V", // fake
            userRelayAddress: userRelayAddress,
            topUpPools: topUpPools,
            amount: 10000, // fake
            feeAmount: .zero, // fake
            blockhash: "FR1GgH83nmcEdoNXyztnpUL2G13KkUv6iwJPwVfnqEgW", // fake
            minimumRelayAccountBalance: info.minimumRelayAccountBalance,
            minimumTokenAccountBalance: info.minimumTokenAccountBalance,
            needsCreateUserRelayAccount: relayAccountStatus == .notYetCreated,
            feePayerAddress: "FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT", // fake
            lamportsPerSignature: info.lamportsPerSignature
        ).feeAmount
        return fee
    }
    
    /// Prepare transaction and expected fee for a given relay transaction
    private func prepareForTopUp(
        network: SolanaSDK.Network,
        sourceToken: TokenInfo,
        userAuthorityAddress: SolanaSDK.PublicKey,
        userRelayAddress: SolanaSDK.PublicKey,
        topUpPools: OrcaSwap.PoolsPair,
        amount: UInt64,
        feeAmount: SolanaSDK.FeeAmount,
        blockhash: String,
        minimumRelayAccountBalance: UInt64,
        minimumTokenAccountBalance: UInt64,
        needsCreateUserRelayAccount: Bool,
        feePayerAddress: String,
        lamportsPerSignature: UInt64
    ) throws -> PreparedParams {
        // assertion
        guard let userSourceTokenAccountAddress = try? SolanaSDK.PublicKey(string: sourceToken.address),
              let sourceTokenMintAddress = try? SolanaSDK.PublicKey(string: sourceToken.mint),
              let feePayerAddress = try? SolanaSDK.PublicKey(string: feePayerAddress),
              let associatedTokenAddress = try? SolanaSDK.PublicKey.associatedTokenAddress(walletAddress: feePayerAddress, tokenMintAddress: sourceTokenMintAddress),
              userSourceTokenAccountAddress != associatedTokenAddress
        else { throw FeeRelayer.Error.wrongAddress }
        
        // forming transaction and count fees
        var expectedFee = SolanaSDK.FeeAmount(transaction: 0, accountBalances: 0)
        var instructions = [SolanaSDK.TransactionInstruction]()
        
        // create user relay account
        if needsCreateUserRelayAccount {
            instructions.append(
                SolanaSDK.SystemProgram.transferInstruction(
                    from: feePayerAddress,
                    to: userRelayAddress,
                    lamports: minimumRelayAccountBalance
                )
            )
            expectedFee.accountBalances += minimumRelayAccountBalance
        }
        
        // top up swap
        let transitTokenMintPubkey = try getTransitTokenMintPubkey(pools: topUpPools)
        let swap = try prepareSwapData(network: network, pools: topUpPools, inputAmount: nil, minAmountOut: amount, slippage: 0.01, transitTokenMintPubkey: transitTokenMintPubkey)
        let userTransferAuthority = swap.transferAuthorityAccount?.publicKey
        
        switch swap.swapData {
        case let swap as DirectSwapData:
            expectedFee.accountBalances += minimumTokenAccountBalance
            // approve
            if let userTransferAuthority = userTransferAuthority {
                instructions.append(
                    SolanaSDK.TokenProgram.approveInstruction(
                        tokenProgramId: .tokenProgramId,
                        account: userSourceTokenAccountAddress,
                        delegate: userTransferAuthority,
                        owner: userAuthorityAddress,
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
            
            // transfer
            instructions.append(
                try Program.transferSolInstruction(
                    userAuthorityAddress: userAuthorityAddress,
                    recipient: feePayerAddress,
                    lamports: feeAmount.accountBalances,
                    network: network
                )
            )
        case let swap as TransitiveSwapData:
            // approve
            if let userTransferAuthority = userTransferAuthority {
                instructions.append(
                    SolanaSDK.TokenProgram.approveInstruction(
                        tokenProgramId: .tokenProgramId,
                        account: userSourceTokenAccountAddress,
                        delegate: userTransferAuthority,
                        owner: userAuthorityAddress,
                        amount: swap.from.amountIn
                    )
                )
            }
            
            // create transit token account
            let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
                user: userAuthorityAddress,
                transitTokenMint: try SolanaSDK.PublicKey(string: swap.transitTokenMintPubkey),
                network: network
            )
            instructions.append(
                try Program.createTransitTokenAccountInstruction(
                    feePayer: feePayerAddress,
                    userAuthority: userAuthorityAddress,
                    transitTokenAccount: transitTokenAccountAddress,
                    transitTokenMint: try SolanaSDK.PublicKey(string: swap.transitTokenMintPubkey),
                    network: network
                )
            )
            
            // Destination WSOL account funding
            expectedFee.accountBalances += minimumTokenAccountBalance
            
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
            
            // close transit token account
            instructions.append(
                SolanaSDK.TokenProgram.closeAccountInstruction(
                    account: transitTokenAccountAddress,
                    destination: feePayerAddress,
                    owner: feePayerAddress
                )
            )
            
            // transfer
            instructions.append(
                try Program.transferSolInstruction(
                    userAuthorityAddress: userAuthorityAddress,
                    recipient: feePayerAddress,
                    lamports: feeAmount.accountBalances,
                    network: network
                )
            )
        default:
            fatalError("unsupported swap type")
        }
        
        var transaction = SolanaSDK.Transaction()
        transaction.instructions = instructions
        transaction.feePayer = feePayerAddress
        transaction.recentBlockhash = blockhash
        let transactionFee = try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignature)
        expectedFee.transaction = transactionFee
        
        return .init(
            swapData: swap.swapData,
            transaction: transaction,
            feeAmount: expectedFee,
            transferAuthorityAccount: swap.transferAuthorityAccount
        )
    }
}
