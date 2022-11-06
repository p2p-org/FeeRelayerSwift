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

final class CheckTransitTokenAccountTests: XCTestCase {

    func testDirectSwapWithNoTransitTokenAccount() async throws {
        var env = SwapTransactionBuilder.BuildContext.Environment()
        
        try await SwapTransactionBuilder.checkTransitTokenAccount(
            solanaAPIClient: MockSolanaAPIClient(testCase: 0),
            orcaSwap: MockOrcaSwap(),
            owner: .owner,
            poolsPair: [solBTCPool()],
            env: &env
        )
        
        XCTAssertNil(env.needsCreateTransitTokenAccount)
        XCTAssertNil(env.transitTokenMintPubkey)
        XCTAssertNil(env.transitTokenAccountAddress)
    }
    
    func testTransitiveSwapWithNonCreatedTransitTokenAccount() async throws {
        var env = SwapTransactionBuilder.BuildContext.Environment()
        
        try await SwapTransactionBuilder.checkTransitTokenAccount(
            solanaAPIClient: MockSolanaAPIClient(testCase: 1),
            orcaSwap: MockOrcaSwap(),
            owner: .owner,
            poolsPair: [solBTCPool(), btcETHPool()], // SOL -> BTC -> ETH
            env: &env
        )
        
        XCTAssertEqual(env.needsCreateTransitTokenAccount, true)
        XCTAssertEqual(env.transitTokenMintPubkey, .btcMint)
        XCTAssertEqual(env.transitTokenAccountAddress, .btcTransitTokenAccountAddress)
    }
    
    func testTransitiveSwapWithCreatedTransitTokenAccount() async throws {
        var env = SwapTransactionBuilder.BuildContext.Environment()
        
        try await SwapTransactionBuilder.checkTransitTokenAccount(
            solanaAPIClient: MockSolanaAPIClient(testCase: 2),
            orcaSwap: MockOrcaSwap(),
            owner: .owner,
            poolsPair: [solBTCPool(), btcETHPool()], // SOL -> BTC -> ETH
            env: &env
        )
        
        XCTAssertEqual(env.needsCreateTransitTokenAccount, false)
        XCTAssertEqual(env.transitTokenMintPubkey, .btcMint)
        XCTAssertEqual(env.transitTokenAccountAddress, .btcTransitTokenAccountAddress)
    }
}

private class MockOrcaSwap: MockOrcaSwapBase {
    override func getMint(tokenName: String) -> String? {
        switch tokenName {
        case "BTC":
            return PublicKey.btcMint.base58EncodedString
        case "ETH":
            return PublicKey.ethMint.base58EncodedString
        case "SOL":
            return PublicKey.wrappedSOLMint.base58EncodedString
        default:
            fatalError()
        }
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
