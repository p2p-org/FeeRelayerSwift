import XCTest
@testable import OrcaSwapSwift
@testable import FeeRelayerSwift
import SolanaSwift

final class BuildSwapDataTests: XCTestCase {
    private var accountStorage: MockAccountStorage!
    var account: SolanaSwift.Account { accountStorage.account! }
    
    override func setUp() async throws {
        accountStorage = try await .init()
    }
    
    override func tearDown() async throws {
        accountStorage = nil
    }

    func testBuildDirectSwapData() async throws {
        // SOL -> BTC
        let swapData = try await SwapTransactionBuilder.buildSwapData(
            userAccount: account,
            network: .mainnetBeta,
            pools: [solBTCPool()],
            inputAmount: 10000,
            minAmountOut: 100,
            slippage: 0.01,
            needsCreateTransitTokenAccount: false
        )
        let encodedSwapData = try JSONEncoder().encode(swapData.swapData as! DirectSwapData)
        let expectedEncodedSwapData = try JSONEncoder().encode(
            DirectSwapData(
                programId: "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP",
                accountPubkey: "7N2AEJ98qBs4PwEwZ6k5pj8uZBKMkZrKZeiC7A64B47u",
                authorityPubkey: "GqnLhu3bPQ46nTZYNFDnzhwm31iFoqhi3ntXMtc5DPiT",
                transferAuthorityPubkey: "3h1zGmCwsRJnVk5BuRNMLsPaQu1y2aqXqXDWYCgrp5UG",
                sourcePubkey: "5eqcnUasgU2NRrEAeWxvFVRTTYWJWfAJhsdffvc6nJc2",
                destinationPubkey: "9G5TBPbEUg2iaFxJ29uVAT8ZzxY77esRshyHiLYZKRh8",
                poolTokenMintPubkey: "Acxs19v6eUMTEfdvkvWkRB4bwFCHm3XV9jABCy7c1mXe",
                poolFeeAccountPubkey: "4yPG4A9jB3ibDMVXEN2aZW4oA1e1xzzA3z5VWjkZd18B",
                amountIn: 10000,
                minimumAmountOut: 100
            )
        )
        XCTAssertEqual(encodedSwapData, expectedEncodedSwapData)
    }
    
    func testBuildTransitiveSwapData() async throws {
        // SOL -> BTC -> ETH
        let needsCreateTransitTokenAccount = Bool.random()
        
        let swapData = try await SwapTransactionBuilder.buildSwapData(
            userAccount: account,
            network: .mainnetBeta,
            pools: [solBTCPool(), btcETHPool()],
            inputAmount: 10000000,
            minAmountOut: nil,
            slippage: 0.01,
            transitTokenMintPubkey: .ethMint,
            needsCreateTransitTokenAccount: needsCreateTransitTokenAccount
        )
        let encodedSwapData = try JSONEncoder().encode(swapData.swapData as! TransitiveSwapData)
        let expectedEncodedSwapData = try JSONEncoder().encode(
            TransitiveSwapData(
                from: .init(
                    programId: "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP",
                    accountPubkey: "7N2AEJ98qBs4PwEwZ6k5pj8uZBKMkZrKZeiC7A64B47u",
                    authorityPubkey: "GqnLhu3bPQ46nTZYNFDnzhwm31iFoqhi3ntXMtc5DPiT",
                    transferAuthorityPubkey: "3h1zGmCwsRJnVk5BuRNMLsPaQu1y2aqXqXDWYCgrp5UG",
                    sourcePubkey: "5eqcnUasgU2NRrEAeWxvFVRTTYWJWfAJhsdffvc6nJc2",
                    destinationPubkey: "9G5TBPbEUg2iaFxJ29uVAT8ZzxY77esRshyHiLYZKRh8",
                    poolTokenMintPubkey: "Acxs19v6eUMTEfdvkvWkRB4bwFCHm3XV9jABCy7c1mXe",
                    poolFeeAccountPubkey: "4yPG4A9jB3ibDMVXEN2aZW4oA1e1xzzA3z5VWjkZd18B",
                    amountIn: 10000000,
                    minimumAmountOut: 14
                ),
                to: .init(
                    programId: "DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1",
                    accountPubkey: "Fz6yRGsNiXK7hVu4D2zvbwNXW8FQvyJ5edacs3piR1P7",
                    authorityPubkey: "FjRVqnmAJgzjSy2J7MtuQbbWZL3xhZUMqmS2exuy4dXF",
                    transferAuthorityPubkey: "3h1zGmCwsRJnVk5BuRNMLsPaQu1y2aqXqXDWYCgrp5UG",
                    sourcePubkey: "81w3VGbnszMKpUwh9EzAF9LpRzkKxc5XYCW64fuYk1jH",
                    destinationPubkey: "6r14WvGMaR1xGMnaU8JKeuDK38RvUNxJfoXtycUKtC7Z",
                    poolTokenMintPubkey: "8pFwdcuXM7pvHdEGHLZbUR8nNsjj133iUXWG6CgdRHk2",
                    poolFeeAccountPubkey: "56FGbSsbZiP2teQhTxRQGwwVSorB2LhEGdLrtUQPfFpb",
                    amountIn: 14,
                    minimumAmountOut: 171
                ),
                transitTokenMintPubkey: "2FPyTwcZLUg1MDrwsyoP4D6s1tM7hAkHYRjkNb5w6Pxk",
                needsCreateTransitTokenAccount: needsCreateTransitTokenAccount
            )
        )
        XCTAssertEqual(encodedSwapData, expectedEncodedSwapData)
    }
}
