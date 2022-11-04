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

private let btcMint: PublicKey = "9n4nbM75f5Ui33ZbPYXn59EwSgE8CGsHtAeTH5YFeJ9E"
private let btcAssociatedAddress: PublicKey = "4Vfs3NZ1Bo8agrfBJhMFdesso8tBWyUZAPBGMoWHuNRU"

private let ethMint: PublicKey = "2FPyTwcZLUg1MDrwsyoP4D6s1tM7hAkHYRjkNb5w6Pxk"
private let ethAssociatedAddress: PublicKey = "4Tz8MH5APRfA4rjUNxhRruqGGMNvrgji3KhWYKf54dc7"

private let btcTransitTokenAccountAddress: PublicKey = "8eYZfAwWoEfsNMmXhCPUAiTpG8EzMgzW8nzr7km3sL2s"

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
        XCTAssertEqual(env.transitTokenMintPubkey, btcMint)
        XCTAssertEqual(env.transitTokenAccountAddress, btcTransitTokenAccountAddress)
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
        XCTAssertEqual(env.transitTokenMintPubkey, btcMint)
        XCTAssertEqual(env.transitTokenAccountAddress, btcTransitTokenAccountAddress)
    }

    // MARK: - Helpers
    private func solBTCPool() -> Pool {
        .init(
            account: "7N2AEJ98qBs4PwEwZ6k5pj8uZBKMkZrKZeiC7A64B47u",
            authority: "GqnLhu3bPQ46nTZYNFDnzhwm31iFoqhi3ntXMtc5DPiT",
            nonce: 255,
            poolTokenMint: "Acxs19v6eUMTEfdvkvWkRB4bwFCHm3XV9jABCy7c1mXe",
            tokenAccountA: "5eqcnUasgU2NRrEAeWxvFVRTTYWJWfAJhsdffvc6nJc2",
            tokenAccountB: "9G5TBPbEUg2iaFxJ29uVAT8ZzxY77esRshyHiLYZKRh8",
            feeAccount: "4yPG4A9jB3ibDMVXEN2aZW4oA1e1xzzA3z5VWjkZd18B",
            hostFeeAccount: nil,
            feeNumerator: 25,
            feeDenominator: 10000,
            ownerTradeFeeNumerator: 5,
            ownerTradeFeeDenominator: 10000,
            ownerWithdrawFeeNumerator: 0,
            ownerWithdrawFeeDenominator: 0,
            hostFeeNumerator: 0,
            hostFeeDenominator: 0,
            tokenAName: "SOL",
            tokenBName: "BTC",
            curveType: "ConstantProduct",
            amp: nil,
            programVersion: 2,
            deprecated: nil,
            tokenABalance: .init(amount: "715874535300", decimals: 9),
            tokenBBalance: .init(amount: "1113617", decimals: 6),
            isStable: nil
        )
    }
    
    private func btcETHPool() -> Pool {
        .init(
            account: "Fz6yRGsNiXK7hVu4D2zvbwNXW8FQvyJ5edacs3piR1P7",
            authority: "FjRVqnmAJgzjSy2J7MtuQbbWZL3xhZUMqmS2exuy4dXF",
            nonce: 255,
            poolTokenMint: "8pFwdcuXM7pvHdEGHLZbUR8nNsjj133iUXWG6CgdRHk2",
            tokenAccountA: "81w3VGbnszMKpUwh9EzAF9LpRzkKxc5XYCW64fuYk1jH",
            tokenAccountB: "6r14WvGMaR1xGMnaU8JKeuDK38RvUNxJfoXtycUKtC7Z",
            feeAccount: "56FGbSsbZiP2teQhTxRQGwwVSorB2LhEGdLrtUQPfFpb",
            hostFeeAccount: nil,
            feeNumerator: 30,
            feeDenominator: 10000,
            ownerTradeFeeNumerator: 0,
            ownerTradeFeeDenominator: 0,
            ownerWithdrawFeeNumerator: 0,
            ownerWithdrawFeeDenominator: 0,
            hostFeeNumerator: 0,
            hostFeeDenominator: 0,
            tokenAName: "BTC",
            tokenBName: "ETH",
            curveType: "ConstantProduct",
            amp: nil,
            programVersion: nil,
            deprecated: true,
            tokenABalance: .init(amount: "786", decimals: 6),
            tokenBBalance: .init(amount: "9895", decimals: 6),
            isStable: nil
        )
    }

}

private class MockOrcaSwap: MockOrcaSwapBase {
    override func getMint(tokenName: String) -> String? {
        switch tokenName {
        case "BTC":
            return btcMint.base58EncodedString
        case "ETH":
            return ethMint.base58EncodedString
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
        case btcTransitTokenAccountAddress.base58EncodedString where testCase == 1:
            return nil
        case btcTransitTokenAccountAddress.base58EncodedString where testCase == 2:
            let info = BufferInfo<AccountInfo>(
                lamports: 0,
                owner: TokenProgram.id.base58EncodedString,
                data: .init(mint: btcMint, owner: SystemProgram.id, lamports: 0, delegateOption: 0, isInitialized: true, isFrozen: true, state: 0, isNativeOption: 0, rentExemptReserve: nil, isNativeRaw: 0, isNative: true, delegatedAmount: 0, closeAuthorityOption: 0),
                executable: false,
                rentEpoch: 0
            )
            return info as? BufferInfo<T>
        default:
            return try await super.getAccountInfo(account: account)
        }
    }
}
