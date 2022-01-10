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
}

extension SolanaSDK: FeeRelayerRelaySolanaClient {}
