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
    func getTokenAccountBalance(pubkey: String, commitment: SolanaSDK.Commitment?) -> Single<SolanaSDK.TokenAccountBalance>
    func checkAccountValidation(account: String) -> Single<Bool>
    func getMinimumBalanceForRentExemption(span: UInt64) -> Single<UInt64>
    func getRecentBlockhash(commitment: SolanaSDK.Commitment?) -> Single<String>
    func getLamportsPerSignature() -> Single<UInt64>
    var endpoint: SolanaSDK.APIEndPoint {get}
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
                if let error = error as? SolanaSDK.Error {
                    switch error {
                    case .invalidResponse(let response):
                        if response.message == "Invalid param: could not find account" {
                            return .just(.notYetCreated)
                        }
                    default:
                        break
                    }
                }
                throw error
            }
    }
}
