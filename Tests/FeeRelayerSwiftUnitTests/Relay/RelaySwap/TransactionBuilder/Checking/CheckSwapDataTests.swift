//
//  CheckSwapDataTests.swift
//  
//
//  Created by Chung Tran on 06/11/2022.
//

import XCTest
@testable import OrcaSwapSwift
@testable import FeeRelayerSwift
import SolanaSwift

final class CheckSwapDataTests: XCTestCase {
    func testCheckDirectSwapData() async throws {
        // BTC -> ETH
        let swapData = DirectSwapData(
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
        )
        
        var env = SwapTransactionBuilder.BuildContext.Environment(
            userSource: .btcAssociatedAddress,
            userDestinationTokenAccountAddress: .ethAssociatedAddress
        )
        
        try SwapTransactionBuilder.checkSwapData(
            network: .mainnetBeta,
            owner: .owner,
            feePayerAddress: .feePayerAddress,
            poolsPair: [btcETHPool()],
            env: &env,
            swapData: .init(swapData: swapData, transferAuthorityAccount: nil)
        )
        
        let swapInstruction = env.instructions[0]
        
        XCTAssertEqual(swapInstruction.keys[0], .readonly(publicKey: "Fz6yRGsNiXK7hVu4D2zvbwNXW8FQvyJ5edacs3piR1P7", isSigner: false))
        XCTAssertEqual(swapInstruction.keys[1], .readonly(publicKey: "FjRVqnmAJgzjSy2J7MtuQbbWZL3xhZUMqmS2exuy4dXF", isSigner: false))
        XCTAssertEqual(swapInstruction.keys[2], .readonly(publicKey: "3h1zGmCwsRJnVk5BuRNMLsPaQu1y2aqXqXDWYCgrp5UG", isSigner: true))
        XCTAssertEqual(swapInstruction.keys[3], .writable(publicKey: "4Vfs3NZ1Bo8agrfBJhMFdesso8tBWyUZAPBGMoWHuNRU", isSigner: false))
        XCTAssertEqual(swapInstruction.keys[4], .writable(publicKey: "81w3VGbnszMKpUwh9EzAF9LpRzkKxc5XYCW64fuYk1jH", isSigner: false))
        XCTAssertEqual(swapInstruction.keys[5], .writable(publicKey: "6r14WvGMaR1xGMnaU8JKeuDK38RvUNxJfoXtycUKtC7Z", isSigner: false))
        XCTAssertEqual(swapInstruction.keys[6], .writable(publicKey: "4Tz8MH5APRfA4rjUNxhRruqGGMNvrgji3KhWYKf54dc7", isSigner: false))
        XCTAssertEqual(swapInstruction.keys[7], .writable(publicKey: "8pFwdcuXM7pvHdEGHLZbUR8nNsjj133iUXWG6CgdRHk2", isSigner: false))
        XCTAssertEqual(swapInstruction.keys[8], .writable(publicKey: "56FGbSsbZiP2teQhTxRQGwwVSorB2LhEGdLrtUQPfFpb", isSigner: false))
        XCTAssertEqual(swapInstruction.keys[9], .readonly(publicKey: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", isSigner: false))
        
        XCTAssertEqual(swapInstruction.programId, "DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1")
        XCTAssertEqual(swapInstruction.data, [UInt8]([1, 14, 0, 0, 0, 0, 0, 0, 0, 171, 0, 0, 0, 0, 0, 0, 0]))
    }
    
    func testCheckTransitiveSwapData() async throws {
        // SOL -> BTC -> ETH
        let needsCreateTransitTokenAccount = Bool.random()
        
        let swapData = TransitiveSwapData(
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
            to: DirectSwapData(
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
            transitTokenMintPubkey: PublicKey.btcMint.base58EncodedString,
            needsCreateTransitTokenAccount: needsCreateTransitTokenAccount
        )
    }
}
