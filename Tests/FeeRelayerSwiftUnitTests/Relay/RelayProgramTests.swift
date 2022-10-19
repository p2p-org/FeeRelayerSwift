import XCTest
@testable import FeeRelayerSwift
import SolanaSwift

final class RelayProgramTests: XCTestCase {
    let userAuthorityAddress: PublicKey = "6QuXb6mB6WmRASP2y8AavXh6aabBXEH5ZzrSH5xRrgSm"
    let feePayerAddress: PublicKey = "HkLNnxTFst1oLrKAJc3w6Pq8uypRnqLMrC68iBP6qUPu"
    let relayAccountAddress: PublicKey = "13DeafU3s4PoEUoDgyeNYZMqZWmgyN8fn3U5HrYxxXwQ"

    func testConstants() throws {
        // id
        XCTAssertEqual(Program.id(network: .mainnetBeta), "12YKFL4mnZz6CBEGePrf293mEzueQM3h8VLPUJsKpGs9")
        XCTAssertEqual(Program.id(network: .devnet), "6xKJFyuM6UHCT8F5SBxnjGt6ZrZYjsVfnAnAeHPU775k")
        XCTAssertEqual(Program.id(network: .testnet), "6xKJFyuM6UHCT8F5SBxnjGt6ZrZYjsVfnAnAeHPU775k")
    }
    
    func testGetUserRelayAddress() throws {
        let relayAddress = try Program.getUserRelayAddress(
            user: userAuthorityAddress,
            network: .mainnetBeta
        )
        XCTAssertEqual(relayAddress, relayAccountAddress)
    }
    
    func testGetUserTemporaryWSOLAddress() throws {
        let tempWSOLAddress = try Program.getUserTemporaryWSOLAddress(
            user: userAuthorityAddress,
            network: .mainnetBeta
        )
        XCTAssertEqual(tempWSOLAddress.base58EncodedString, "FMRxGTeTANuERNfCW4zLBgTDDH4aMkHhPfzYGXVf27Rj")
    }
    
    func testGetTransitTokenAccountAddress() throws {
        let transitTokenAccountAddress = try Program.getTransitTokenAccountAddress(
            user: userAuthorityAddress,
            transitTokenMint: .usdcMint,
            network: .mainnetBeta
        )
        XCTAssertEqual(transitTokenAccountAddress.base58EncodedString, "JhhACrqV4LhpZY7ogW9Gy2MRLVanXXFxyiW548dsjBp")
    }
    
    func testTopUpDirectSwapInstruction() throws {
        let instruction = try Program.topUpSwapInstruction(
            network: .mainnetBeta,
            topUpSwap: createRelayDirectSwapParams(index: 0),
            userAuthorityAddress: "6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D",
            userSourceTokenAccountAddress: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3",
            feePayerAddress: feePayerAddress
        )
        
        XCTAssertEqual(instruction.programId, Program.id(network: .mainnetBeta))
        XCTAssertEqual(instruction.data.toHexString(), "0020a107000000000020a1070000000000")
        XCTAssertEqual(instruction.keys, [
            .init(publicKey: "So11111111111111111111111111111111111111112", isSigner: false, isWritable: false),
            .init(publicKey: feePayerAddress, isSigner: true, isWritable: true),
            .init(publicKey: "6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D", isSigner: true, isWritable: false),
            .init(publicKey: "DBbMbfcZWcgiT7oftRPaNoW5noruSmVoLYCXqkcBVvtB", isSigner: false, isWritable: true),
            .init(publicKey: TokenProgram.id, isSigner: false, isWritable: false),
            .init(publicKey: "6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D", isSigner: false, isWritable: false),
            .init(publicKey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3", isSigner: false, isWritable: false),
            .init(publicKey: "6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D", isSigner: false, isWritable: false),
            .init(publicKey: "6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D", isSigner: true, isWritable: false),
            .init(publicKey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3", isSigner: false, isWritable: true),
            .init(publicKey: "HgqwRMnK59Satquv6Rv5J9K3kScMyaMeGPoSX2kksmL", isSigner: false, isWritable: true),
            .init(publicKey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3", isSigner: false, isWritable: true),
            .init(publicKey: "CRh1jz9Ahs4ZLdTDtsQqtTh8UWFDFre6NtvFTWXQspeX", isSigner: false, isWritable: true),
            .init(publicKey: "3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC", isSigner: false, isWritable: true),
            .init(publicKey: "EDuiPgd4PuCXe9h2YieMbH7uUMeB4pgeWnP5hfcPvxu3", isSigner: false, isWritable: true),
            .init(publicKey: .sysvarRent, isSigner: false, isWritable: false),
            .init(publicKey: SystemProgram.id, isSigner: false, isWritable: false)
        ])
    }
    
    func testTopUpTransitiveSwapInstruction() throws {
        let instruction = try Program.topUpSwapInstruction(
            network: .mainnetBeta,
            topUpSwap: TransitiveSwapData(
                from: createRelayDirectSwapParams(index: 0),
                to: createRelayDirectSwapParams(index: 1),
                transitTokenMintPubkey: "3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC",
                needsCreateTransitTokenAccount: false
            ),
            userAuthorityAddress: userAuthorityAddress,
            userSourceTokenAccountAddress: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3",
            feePayerAddress: feePayerAddress
        )
        
        XCTAssertEqual(instruction.programId, Program.id(network: .mainnetBeta))
        XCTAssertEqual(instruction.data.toHexString(), "0120a107000000000020a107000000000020a1070000000000")
        XCTAssertEqual(instruction.keys, [
            .init(publicKey: "So11111111111111111111111111111111111111112", isSigner: false, isWritable: false),
            .init(publicKey: feePayerAddress, isSigner: true, isWritable: true),
            .init(publicKey: userAuthorityAddress, isSigner: true, isWritable: false),
            .init(publicKey: "13DeafU3s4PoEUoDgyeNYZMqZWmgyN8fn3U5HrYxxXwQ", isSigner: false, isWritable: true),
            .init(publicKey: TokenProgram.id, isSigner: false, isWritable: false),
            .init(publicKey: "6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D", isSigner: true, isWritable: false),
            .init(publicKey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3", isSigner: false, isWritable: true),
            .init(publicKey: "DQmptpwQifMc2a6KQLUtrKmNa26KgxTa1954rmS9zDWD", isSigner: false, isWritable: true),
            .init(publicKey: "FMRxGTeTANuERNfCW4zLBgTDDH4aMkHhPfzYGXVf27Rj", isSigner: false, isWritable: true),
            .init(publicKey: "6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D", isSigner: false, isWritable: false),
            .init(publicKey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3", isSigner: false, isWritable: false),
            .init(publicKey: "6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D", isSigner: false, isWritable: false),
            .init(publicKey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3", isSigner: false, isWritable: true),
            .init(publicKey: "CRh1jz9Ahs4ZLdTDtsQqtTh8UWFDFre6NtvFTWXQspeX", isSigner: false, isWritable: true),
            .init(publicKey: "3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC", isSigner: false, isWritable: true),
            .init(publicKey: "EDuiPgd4PuCXe9h2YieMbH7uUMeB4pgeWnP5hfcPvxu3", isSigner: false, isWritable: true),
            .init(publicKey: "6Aj2GVxoCiEhhYTk9rNySg2QTgvtqSzR229KynihWH3D", isSigner: false, isWritable: false),
            .init(publicKey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3", isSigner: false, isWritable: false),
            .init(publicKey: "6Aj2GVxoCiEhhYTk9rNySg2QTgvtqSzR229KynihWH3D", isSigner: false, isWritable: false),
            .init(publicKey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3", isSigner: false, isWritable: true),
            .init(publicKey: "CRh2jz9Ahs4ZLdTDtsQqtTh8UWFDFre6NtvFTWXQspeX", isSigner: false, isWritable: true),
            .init(publicKey: "3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC", isSigner: false, isWritable: true),
            .init(publicKey: "EDuiPgd4PuCXe9h2YieMbH7uUMeB4pgeWnP5hfcPvxu3", isSigner: false, isWritable: true),
            .init(publicKey: .sysvarRent, isSigner: false, isWritable: false),
            .init(publicKey: SystemProgram.id, isSigner: false, isWritable: false)
        ])
    }
    
    func testTransferSOLInstruction() throws {
        let instruction = try Program.transferSolInstruction(
            userAuthorityAddress: userAuthorityAddress,
            recipient: feePayerAddress,
            lamports: 2039280, // expected fee
            network: .mainnetBeta
        )
        
        XCTAssertEqual(instruction.programId, Program.id(network: .mainnetBeta))
        XCTAssertEqual(instruction.data.toHexString(), "02f01d1f0000000000")
        XCTAssertEqual(instruction.keys, [
            .init(publicKey: userAuthorityAddress, isSigner: true, isWritable: false),
            .init(publicKey: try Program.getUserRelayAddress(user: userAuthorityAddress, network: .mainnetBeta), isSigner: false, isWritable: true),
            .init(publicKey: feePayerAddress, isSigner: false, isWritable: true),
            .init(publicKey: SystemProgram.id, isSigner: false, isWritable: false)
        ])
    }
    
    func testCreateTransitAccountInstruction() throws {
        let transitTokenAccount: PublicKey = "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3"
        let transitTokenMint: PublicKey = .usdcMint
        let instruction = try Program.createTransitTokenAccountInstruction(
            feePayer: feePayerAddress,
            userAuthority: userAuthorityAddress,
            transitTokenAccount: transitTokenAccount,
            transitTokenMint: transitTokenMint,
            network: .mainnetBeta
        )
        
        XCTAssertEqual(instruction.programId, Program.id(network: .mainnetBeta))
        XCTAssertEqual(instruction.data.toHexString(), "03")
        XCTAssertEqual(instruction.keys, [
            .init(publicKey: transitTokenAccount, isSigner: false, isWritable: true),
            .init(publicKey: .usdcMint, isSigner: false, isWritable: false),
            .init(publicKey: userAuthorityAddress, isSigner: true, isWritable: true),
            .init(publicKey: feePayerAddress, isSigner: true, isWritable: false),
            .init(publicKey: TokenProgram.id, isSigner: false, isWritable: false),
            .init(publicKey: .sysvarRent, isSigner: false, isWritable: false),
            .init(publicKey: SystemProgram.id, isSigner: false, isWritable: false)
        ])
    }
}

private func createRelayDirectSwapParams(index: Int) -> DirectSwapData {
    .init(
        programId: "6Aj\(index+1)GVxoCiEhhYTk9rNySg2QTgvtqSzR\(index+1)\(index+1)9KynihWH3D",
        accountPubkey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3",
        authorityPubkey: "6Aj\(index+1)GVxoCiEhhYTk9rNySg2QTgvtqSzR\(index+1)\(index+1)9KynihWH3D",
        transferAuthorityPubkey: "6Aj\(index+1)GVxoCiEhhYTk9rNySg2QTgvtqSzR\(index+1)\(index+1)9KynihWH3D",
        sourcePubkey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3",
        destinationPubkey: "CRh\(index+1)jz9Ahs4ZLdTDtsQqtTh8UWFDFre6NtvFTWXQspeX",
        poolTokenMintPubkey: "3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC",
        poolFeeAccountPubkey: "EDuiPgd4PuCXe9h2YieMbH7uUMeB4pgeWnP5hfcPvxu3",
        amountIn: 500000,
        minimumAmountOut: 500000
    )
}
