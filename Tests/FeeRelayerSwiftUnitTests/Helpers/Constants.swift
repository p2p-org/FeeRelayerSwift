import SolanaSwift
@testable import OrcaSwapSwift

let minimumTokenAccountBalance: UInt64 = 2039280
let minimumRelayAccountBalance: UInt64 = 890880
let lamportsPerSignature: UInt64 = 5000
let blockhash: String = "CSymwgTNX1j3E4qhKfJAUE41nBWEwXufoYryPbkde5RR"

func solBTCPool() -> Pool {
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

func btcETHPool() -> Pool {
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


extension PublicKey {
    static var owner: PublicKey {
        "3h1zGmCwsRJnVk5BuRNMLsPaQu1y2aqXqXDWYCgrp5UG"
    }
    
    static var feePayerAddress: PublicKey {
        "FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT"
    }
    
    static var usdtMint: PublicKey {
        "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
    }
    
    static var btcMint: PublicKey {
        "9n4nbM75f5Ui33ZbPYXn59EwSgE8CGsHtAeTH5YFeJ9E"
    }
    
    static var btcAssociatedAddress: PublicKey {
        "4Vfs3NZ1Bo8agrfBJhMFdesso8tBWyUZAPBGMoWHuNRU"
        
    }

    static var ethMint: PublicKey {
        "2FPyTwcZLUg1MDrwsyoP4D6s1tM7hAkHYRjkNb5w6Pxk"
    }
    static var ethAssociatedAddress: PublicKey {
        "4Tz8MH5APRfA4rjUNxhRruqGGMNvrgji3KhWYKf54dc7"
    }

    static var btcTransitTokenAccountAddress: PublicKey {
        "8eYZfAwWoEfsNMmXhCPUAiTpG8EzMgzW8nzr7km3sL2s"
    }
}
