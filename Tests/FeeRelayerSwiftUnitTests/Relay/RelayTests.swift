//
//  File.swift
//  
//
//  Created by Chung Tran on 18/10/2022.
//

import Foundation
import SolanaSwift
//    var service: FeeRelayerService!
//
//    override func setUp() async throws {
//        service = .init(
//            orcaSwap: MockOrcaSwap(),
//            accountStorage: try await MockAccountStorage(),
//            solanaApiClient: MockSolanaAPIClient(),
//            feeRelayerAPIClient: MockFeeRelayerAPIClient(),
//            deviceType: .iOS,
//            buildNumber: "1.0.0"
//        )
//    }
//
//    override func tearDown() async throws {
//        service = nil
//    }

//        let freeTransactionFeeLimit = FeeLimitForAuthorityResponse(
//            authority: [],
//            limits: .init(
//                useFreeFee: true,
//                maxAmount: 10000000,
//                maxCount: 100,
//                period: .init(secs: 86400, nanos: 0)
//            ),
//            processedFee: .init(
//                totalAmount: 20000,
//                count: 2
//            )
//        )

private class MockOrcaSwap: MockOrcaSwapBase {
    
}

private class MockAccountStorage: SolanaAccountStorage {
    let account: SolanaSwift.Account?
    
    init() async throws {
        account = try await Account(
            phrase: "miracle pizza supply useful steak border same again youth silver access hundred".components(separatedBy: " "),
            network: .mainnetBeta
        )
    }
    
    func save(_ account: SolanaSwift.Account) throws {}
}

private class MockSolanaAPIClient: MockSolanaAPIClientBase {
    
}

private class MockFeeRelayerAPIClient: MockFeeRelayerAPIClientBase {
    
}
