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
}
