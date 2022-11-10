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
    var swapTransactionBuilder: SwapTransactionBuilderImpl!
    
    override func tearDown() async throws {
        swapTransactionBuilder = nil
    }
    
    func testSignersWithSourceWSOL() async throws {
        swapTransactionBuilder = .init(
            solanaAPIClient: MockSolanaAPIClientBase(),
            orcaSwap: MockOrcaSwapBase(),
            feePayerAddress: .feePayerAddress,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            lamportsPerSignature: lamportsPerSignature
        )
        
        let owner = try await Account(network: .mainnetBeta)
        let newWSOL = try await Account(network: .mainnetBeta)
        var env = SwapTransactionBuilderOutput(
            sourceWSOLNewAccount: newWSOL
        )
        
        swapTransactionBuilder.checkSigners(
            ownerAccount: owner,
            env: &env
        )
        
        XCTAssertEqual(env.signers.first, owner)
        XCTAssertEqual(env.signers.last, newWSOL)
    }
    
    func testSignersWithDestinationWSOL() async throws {
        swapTransactionBuilder = .init(
            solanaAPIClient: MockSolanaAPIClientBase(),
            orcaSwap: MockOrcaSwapBase(),
            feePayerAddress: .feePayerAddress,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            lamportsPerSignature: lamportsPerSignature
        )
        
        let owner = try await Account(network: .mainnetBeta)
        let newWSOL = try await Account(network: .mainnetBeta)
        var env = SwapTransactionBuilderOutput(
            destinationNewAccount: newWSOL
        )
        
        swapTransactionBuilder.checkSigners(
            ownerAccount: owner,
            env: &env
        )
        
        XCTAssertEqual(env.signers.first, owner)
        XCTAssertEqual(env.signers.last, newWSOL)
    }
}
