//
//  File.swift
//  
//
//  Created by Chung Tran on 10/01/2022.
//

import Foundation
import SolanaSwift
import RxSwift

public protocol FeeRelayerRelaySolanaClient {
    func getRelayAccountStatus(_ relayAccountAddress: String) -> Single<FeeRelayer.Relay.RelayAccountStatus>
    func getMinimumBalanceForRentExemption(span: UInt64) -> Single<UInt64>
    func getRecentBlockhash(commitment: SolanaSDK.Commitment?) -> Single<String>
    func getLamportsPerSignature() -> Single<UInt64>
    var endpoint: SolanaSDK.APIEndPoint {get}
    func prepareTransaction(
        instructions: [SolanaSDK.TransactionInstruction],
        signers: [SolanaSDK.Account],
        feePayer: SolanaSDK.PublicKey,
        accountsCreationFee: SolanaSDK.Lamports,
        recentBlockhash: String?,
        lamportsPerSignature: SolanaSDK.Lamports?
    ) -> Single<SolanaSDK.PreparedTransaction>
    func findSPLTokenDestinationAddress(
        mintAddress: String,
        destinationAddress: String
    ) -> Single<SolanaSDK.SPLTokenDestinationAddress>
    func getAccountInfo<T: DecodableBufferLayout>(account: String, decodedTo: T.Type) -> Single<SolanaSDK.BufferInfo<T>>
}

extension SolanaSDK: FeeRelayerRelaySolanaClient {
    public func getLamportsPerSignature() -> Single<UInt64> {
        getFees(commitment: nil).map {$0.feeCalculator?.lamportsPerSignature ?? 0}
    }
    
    public func getRelayAccountStatus(_ relayAccountAddress: String) -> Single<FeeRelayer.Relay.RelayAccountStatus> {
        getAccountInfo(account: relayAccountAddress, decodedTo: SolanaSDK.EmptyInfo.self)
            .map {.created(balance: $0.lamports)}
            .catch { error in
                if error.isEqualTo(SolanaSDK.Error.couldNotRetrieveAccountInfo) {
                    return .just(.notYetCreated)
                }
                throw error
            }
    }
}
