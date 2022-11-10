//
//  CheckTransitTokenAccountTests.swift
//  
//
//  Created by Chung Tran on 04/11/2022.
//

import XCTest
@testable import FeeRelayerSwift
@testable import OrcaSwapSwift
@testable import SolanaSwift

final class CheckTransitTokenAccount2Tests: XCTestCase {
    var swapTransactionBuilder: SwapTransactionBuilderImpl!
    
    override func tearDown() async throws {
        swapTransactionBuilder = nil
    }

    func testDirectSwapWithNoTransitTokenAccount() async throws {
        swapTransactionBuilder = .init(
            solanaAPIClient: MockSolanaAPIClient(testCase: 0),
            orcaSwap: MockOrcaSwapBase(),
            relayContextManager: MockRelayContextManagerBase()
        )
        
        var env = SwapTransactionBuilderOutput()
        
        try await swapTransactionBuilder.checkTransitTokenAccount(
            owner: .owner,
            poolsPair: [.solBTC],
            output: &env
        )
        
        XCTAssertNil(env.needsCreateTransitTokenAccount)
        XCTAssertNil(env.transitTokenMintPubkey)
        XCTAssertNil(env.transitTokenAccountAddress)
    }
    
    func testTransitiveSwapWithNonCreatedTransitTokenAccount() async throws {
        swapTransactionBuilder = .init(
            solanaAPIClient: MockSolanaAPIClient(testCase: 1),
            orcaSwap: MockOrcaSwapBase(),
            relayContextManager: MockRelayContextManagerBase()
        )
        
        var env = SwapTransactionBuilderOutput()
        
        try await swapTransactionBuilder.checkTransitTokenAccount(
            owner: .owner,
            poolsPair: [.solBTC, .btcETH], // SOL -> BTC -> ETH
            output: &env
        )
        
        XCTAssertEqual(env.needsCreateTransitTokenAccount, true)
        XCTAssertEqual(env.transitTokenMintPubkey, .btcMint)
        XCTAssertEqual(env.transitTokenAccountAddress, .btcTransitTokenAccountAddress)
    }
    
    func testTransitiveSwapWithCreatedTransitTokenAccount() async throws {
        swapTransactionBuilder = .init(
            solanaAPIClient: MockSolanaAPIClient(testCase: 2),
            orcaSwap: MockOrcaSwapBase(),
            relayContextManager: MockRelayContextManagerBase()
        )
        
        var env = SwapTransactionBuilderOutput()
        
        try await swapTransactionBuilder.checkTransitTokenAccount(
            owner: .owner,
            poolsPair: [.solBTC, .btcETH], // SOL -> BTC -> ETH
            output: &env
        )
        
        XCTAssertEqual(env.needsCreateTransitTokenAccount, false)
        XCTAssertEqual(env.transitTokenMintPubkey, .btcMint)
        XCTAssertEqual(env.transitTokenAccountAddress, .btcTransitTokenAccountAddress)
    }
}

private class MockSolanaAPIClient: MockSolanaAPIClientBase {
    let testCase: Int
    
    init(testCase: Int) {
        self.testCase = testCase
        super.init()
    }
    
    override func getAccountInfo<T>(account: String) async throws -> BufferInfo<T>? where T : BufferLayout {
        switch account {
        case PublicKey.btcTransitTokenAccountAddress.base58EncodedString where testCase == 1:
            return nil
        case PublicKey.btcTransitTokenAccountAddress.base58EncodedString where testCase == 2:
            let info = BufferInfo<AccountInfo>(
                lamports: 0,
                owner: TokenProgram.id.base58EncodedString,
                data: .init(mint: .btcMint, owner: SystemProgram.id, lamports: 0, delegateOption: 0, isInitialized: true, isFrozen: true, state: 0, isNativeOption: 0, rentExemptReserve: nil, isNativeRaw: 0, isNative: true, delegatedAmount: 0, closeAuthorityOption: 0),
                executable: false,
                rentEpoch: 0
            )
            return info as? BufferInfo<T>
        default:
            return try await super.getAccountInfo(account: account)
        }
    }
}
