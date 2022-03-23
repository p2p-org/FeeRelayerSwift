//
//  File.swift
//  
//
//  Created by Chung Tran on 10/01/2022.
//

import Foundation
import RxSwift
import SolanaSwift
import OrcaSwapSwift

extension FeeRelayer.Relay {
    func getRelayAccountCreationCost() -> UInt64 {
        cache.lamportsPerSignature ?? 0 // TODO: Check again
    }
    
    // MARK: - Top up
    /// Prepare swap data from swap pools
    func prepareSwapData(
        network: SolanaSDK.Network,
        pools: OrcaSwap.PoolsPair,
        inputAmount: UInt64?,
        minAmountOut: UInt64?,
        slippage: Double,
        transitTokenMintPubkey: SolanaSDK.PublicKey? = nil,
        newTransferAuthority: Bool = false,
        needsCreateTransitTokenAccount: Bool
    ) throws -> (swapData: FeeRelayerRelaySwapType, transferAuthorityAccount: SolanaSDK.Account?) {
        // preconditions
        guard pools.count > 0 && pools.count <= 2 else { throw FeeRelayer.Error.swapPoolsNotFound }
        guard !(inputAmount == nil && minAmountOut == nil) else { throw FeeRelayer.Error.invalidAmount }
        
        // create transferAuthority
        let transferAuthority = try SolanaSDK.Account(network: network)
        
        // form topUp params
        if pools.count == 1 {
            let pool = pools[0]
            
            guard let amountIn = try inputAmount ?? pool.getInputAmount(minimumReceiveAmount: minAmountOut!, slippage: slippage),
                  let minAmountOut = try minAmountOut ?? pool.getMinimumAmountOut(inputAmount: inputAmount!, slippage: slippage)
            else { throw FeeRelayer.Error.invalidAmount }
            
            let directSwapData = pool.getSwapData(
                transferAuthorityPubkey: newTransferAuthority ? transferAuthority.publicKey: owner.publicKey,
                amountIn: amountIn,
                minAmountOut: minAmountOut
            )
            return (swapData: directSwapData, transferAuthorityAccount: newTransferAuthority ? transferAuthority: nil)
        } else {
            let firstPool = pools[0]
            let secondPool = pools[1]
            
            guard let transitTokenMintPubkey = transitTokenMintPubkey else {
                throw FeeRelayer.Error.transitTokenMintNotFound
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
                throw FeeRelayer.Error.invalidAmount
            }
            
            let transitiveSwapData = TransitiveSwapData(
                from: firstPool.getSwapData(
                    transferAuthorityPubkey: newTransferAuthority ? transferAuthority.publicKey: owner.publicKey,
                    amountIn: firstPoolAmountIn,
                    minAmountOut: secondPoolAmountIn
                ),
                to: secondPool.getSwapData(
                    transferAuthorityPubkey: newTransferAuthority ? transferAuthority.publicKey: owner.publicKey,
                    amountIn: secondPoolAmountIn,
                    minAmountOut: secondPoolAmountOut
                ),
                transitTokenMintPubkey: transitTokenMintPubkey.base58EncodedString,
                needsCreateTransitTokenAccount: needsCreateTransitTokenAccount
            )
            return (swapData: transitiveSwapData, transferAuthorityAccount: newTransferAuthority ? transferAuthority: nil)
        }
    }
    
    func getTransitTokenMintPubkey(pools: OrcaSwap.PoolsPair) throws -> SolanaSDK.PublicKey? {
        var transitTokenMintPubkey: SolanaSDK.PublicKey?
        if pools.count == 2 {
            let interTokenName = pools[0].tokenBName
            transitTokenMintPubkey = try SolanaSDK.PublicKey(string: orcaSwapClient.getMint(tokenName: interTokenName))
        }
        return transitTokenMintPubkey
    }
    
    func getTransitToken(
        pools: OrcaSwap.PoolsPair
    ) throws -> TokenInfo? {
        let transitTokenMintPubkey = try getTransitTokenMintPubkey(pools: pools)
        
        var transitTokenAccountAddress: SolanaSDK.PublicKey?
        if let transitTokenMintPubkey = transitTokenMintPubkey {
            transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
                user: owner.publicKey,
                transitTokenMint: transitTokenMintPubkey,
                network: solanaClient.endpoint.network
            )
        }
    
        if let transitTokenMintPubkey = transitTokenMintPubkey,
           let transitTokenAccountAddress = transitTokenAccountAddress
        {
            return .init(address: transitTokenAccountAddress.base58EncodedString, mint: transitTokenMintPubkey.base58EncodedString)
        }
        return nil
    }
    
    func checkIfNeedsCreateTransitTokenAccount(
        transitToken: TokenInfo?
    ) -> Single<Bool?> {
        guard let transitToken = transitToken else {
            return .just(nil)
        }

        return solanaClient.getAccountInfo(
            account: transitToken.address,
            decodedTo: SolanaSDK.AccountInfo.self
        )
            .map {info -> Bool in
                // detect if destination address is already a SPLToken address
                if info.data.mint.base58EncodedString == transitToken.mint {
                    return false
                }
                return true
            }
            .catchAndReturn(true)
    }
    
    /// Update free transaction fee limit
    func updateFreeTransactionFeeLimit() -> Completable {
        apiClient.requestFreeFeeLimits(for: owner.publicKey.base58EncodedString)
            .do(onSuccess: { [weak self] info in
                let info = FreeTransactionFeeLimit(
                    maxUsage: info.limits.maxCount,
                    currentUsage: info.processedFee.count,
                    maxAmount: info.limits.maxAmount,
                    amountUsed: info.processedFee.totalAmount
                )
                self?.locker.lock()
                self?.cache.freeTransactionFeeLimit = info
                self?.locker.unlock()
            })
            .asCompletable()
    }
    
    func updateRelayAccountStatus() -> Completable {
        solanaClient.getRelayAccountStatus(userRelayAddress.base58EncodedString)
            .do(onSuccess: { [weak self] info in
                self?.locker.lock()
                self?.cache.relayAccountStatus = info
                self?.locker.unlock()
            })
            .asCompletable()
    }
    
    func markTransactionAsCompleted(freeFeeAmountUsed: UInt64) {
        locker.lock()
        cache.freeTransactionFeeLimit?.currentUsage += 1
        cache.freeTransactionFeeLimit?.amountUsed = freeFeeAmountUsed
        locker.unlock()
    }
}

extension Single where Element == [String] {
    func retryWhenNeeded() -> Single<Element> {
        retry(.delayed(maxCount: 3, time: 3.0), shouldRetry: {error in
            if let error = error as? FeeRelayer.Error,
               let clientError = error.clientError
            {
                if clientError.type == .maximumNumberOfInstructionsAllowedExceeded {
                    return true
                }
                
                if clientError.type == .connectionClosedBeforeMessageCompleted {
                    return true
                }
            }
            
            return false
        })
    }
}

private extension OrcaSwap.Pool {
    func getSwapData(
        transferAuthorityPubkey: SolanaSDK.PublicKey,
        amountIn: UInt64,
        minAmountOut: UInt64
    ) -> FeeRelayer.Relay.DirectSwapData {
        .init(
            programId: swapProgramId.base58EncodedString,
            accountPubkey: account,
            authorityPubkey: authority,
            transferAuthorityPubkey: transferAuthorityPubkey.base58EncodedString,
            sourcePubkey: tokenAccountA,
            destinationPubkey: tokenAccountB,
            poolTokenMintPubkey: poolTokenMint,
            poolFeeAccountPubkey: feeAccount,
            amountIn: amountIn,
            minimumAmountOut: minAmountOut
        )
    }
}

extension Encodable {
    var jsonString: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
