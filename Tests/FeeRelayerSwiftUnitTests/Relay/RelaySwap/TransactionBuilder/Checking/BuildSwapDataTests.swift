import XCTest
@testable import OrcaSwapSwift
@testable import FeeRelayerSwift
import SolanaSwift

private let btcMint: PublicKey = "9n4nbM75f5Ui33ZbPYXn59EwSgE8CGsHtAeTH5YFeJ9E"
private let btcAssociatedAddress: PublicKey = "4Vfs3NZ1Bo8agrfBJhMFdesso8tBWyUZAPBGMoWHuNRU"

private let ethMint: PublicKey = "2FPyTwcZLUg1MDrwsyoP4D6s1tM7hAkHYRjkNb5w6Pxk"
private let ethAssociatedAddress: PublicKey = "4Tz8MH5APRfA4rjUNxhRruqGGMNvrgji3KhWYKf54dc7"

private let btcTransitTokenAccountAddress: PublicKey = "8eYZfAwWoEfsNMmXhCPUAiTpG8EzMgzW8nzr7km3sL2s"

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
            transitTokenMintPubkey: ethMint,
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
