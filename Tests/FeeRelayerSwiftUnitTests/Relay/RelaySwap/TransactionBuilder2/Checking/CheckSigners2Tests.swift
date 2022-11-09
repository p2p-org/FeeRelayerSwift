//
//  CheckSignersTests.swift
//  
//
//  Created by Chung Tran on 06/11/2022.
//

import XCTest
import SolanaSwift
@testable import FeeRelayerSwift

final class CheckSigners2Tests: XCTestCase {
    func testSignersWithSourceWSOL() async throws {
        let owner = try await Account(network: .mainnetBeta)
        let newWSOL = try await Account(network: .mainnetBeta)
        var env = SwapTransactionBuilder.BuildContext.Environment(
            sourceWSOLNewAccount: newWSOL
        )
        
        SwapTransactionBuilder.checkSigners(
            ownerAccount: owner,
            env: &env
        )
        
        XCTAssertEqual(env.signers.first, owner)
        XCTAssertEqual(env.signers.last, newWSOL)
    }
    
    func testSignersWithDestinationWSOL() async throws {
        let owner = try await Account(network: .mainnetBeta)
        let newWSOL = try await Account(network: .mainnetBeta)
        var env = SwapTransactionBuilder.BuildContext.Environment(
            destinationNewAccount: newWSOL
        )
        
        SwapTransactionBuilder.checkSigners(
            ownerAccount: owner,
            env: &env
        )
        
        XCTAssertEqual(env.signers.first, owner)
        XCTAssertEqual(env.signers.last, newWSOL)
    }
}
