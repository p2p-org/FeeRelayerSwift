import Foundation
import XCTest
@testable import FeeRelayerSwift

class RelayEncodingTests: XCTestCase {
    func testEncodingTopUpWithDirectSwapParams() throws {
        let params = FeeRelayer.Relay.TopUpWithSwapParams(
            userSourceTokenAccountPubkey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3",
            sourceTokenMintPubkey: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            userAuthorityPubkey: "6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D",
            topUpSwap: .init(createRelayDirectSwapParams(index: 0)),
            feeAmount: 500000,
            signatures: fakeSignature,
            blockhash: "FyGp8WQvMAMiXs1E3YHRPhQ9KeNquTGu9NdnnKudrF7S"
        )
        
        let data = try JSONEncoder().encode(params)
        let string = String(data: data, encoding: .utf8)
        
        XCTAssertEqual(string, #"{"user_authority_pubkey":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","top_up_swap":{"pool_fee_account_pubkey":"EDuiPgd4PuCXe9h2YieMbH7uUMeB4pgeWnP5hfcPvxu3","account_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","destination_pubkey":"CRh1jz9Ahs4ZLdTDtsQqtTh8UWFDFre6NtvFTWXQspeX","amount_in":500000,"source_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","transfer_authority_pubkey":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","minimum_amount_out":500000,"authority_pubkey":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","program_id":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","pool_token_mint_pubkey":"3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC"},"user_source_token_account_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","signatures":{"user_authority_signature":"3rR2np1ZtgNa9QCnhGCybFXEiHKref7CAvpMA4DEh8yJ8gCF5oXKGzJZ8TEWTzUTQGZNm83CQyjyiSo2VHcQWXJd","transfer_authority_signature":"3rR2np1ZtgNa9QCnhGCybFXEiHKref7CAvpMA4DEh8yJ8gCF5oXKGzJZ8TEWTzUTQGZNm83CQyjyiSo2VHcQWXJd"},"blockhash":"FyGp8WQvMAMiXs1E3YHRPhQ9KeNquTGu9NdnnKudrF7S","fee_amount":500000,"source_token_mint_pubkey":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"}"#)
    }
    
    func testEncodingTopUpWithTransitiveSwapParams() throws {
        let params = FeeRelayer.Relay.TopUpWithSwapParams(
            userSourceTokenAccountPubkey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3",
            sourceTokenMintPubkey: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            userAuthorityPubkey: "6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D",
            topUpSwap: .init(FeeRelayer.Relay.TransitiveSwapData(
                from: createRelayDirectSwapParams(index: 0),
                to: createRelayDirectSwapParams(index: 1),
                transitTokenMintPubkey: "3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC"
            )),
            feeAmount: 500000,
            signatures: fakeSignature,
            blockhash: "FyGp8WQvMAMiXs1E3YHRPhQ9KeNquTGu9NdnnKudrF7S"
        )
        
        let data = try JSONEncoder().encode(params)
        let string = String(data: data, encoding: .utf8)
        
        XCTAssertEqual(string, #"{"user_authority_pubkey":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","top_up_swap":{"to":{"pool_fee_account_pubkey":"EDuiPgd4PuCXe9h2YieMbH7uUMeB4pgeWnP5hfcPvxu3","account_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","destination_pubkey":"CRh2jz9Ahs4ZLdTDtsQqtTh8UWFDFre6NtvFTWXQspeX","amount_in":500000,"source_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","transfer_authority_pubkey":"6Aj2GVxoCiEhhYTk9rNySg2QTgvtqSzR229KynihWH3D","minimum_amount_out":500000,"authority_pubkey":"6Aj2GVxoCiEhhYTk9rNySg2QTgvtqSzR229KynihWH3D","program_id":"6Aj2GVxoCiEhhYTk9rNySg2QTgvtqSzR229KynihWH3D","pool_token_mint_pubkey":"3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC"},"transit_token_mint_pubkey":"3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC","from":{"pool_fee_account_pubkey":"EDuiPgd4PuCXe9h2YieMbH7uUMeB4pgeWnP5hfcPvxu3","account_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","destination_pubkey":"CRh1jz9Ahs4ZLdTDtsQqtTh8UWFDFre6NtvFTWXQspeX","amount_in":500000,"source_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","transfer_authority_pubkey":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","minimum_amount_out":500000,"authority_pubkey":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","program_id":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","pool_token_mint_pubkey":"3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC"}},"user_source_token_account_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","signatures":{"user_authority_signature":"3rR2np1ZtgNa9QCnhGCybFXEiHKref7CAvpMA4DEh8yJ8gCF5oXKGzJZ8TEWTzUTQGZNm83CQyjyiSo2VHcQWXJd","transfer_authority_signature":"3rR2np1ZtgNa9QCnhGCybFXEiHKref7CAvpMA4DEh8yJ8gCF5oXKGzJZ8TEWTzUTQGZNm83CQyjyiSo2VHcQWXJd"},"blockhash":"FyGp8WQvMAMiXs1E3YHRPhQ9KeNquTGu9NdnnKudrF7S","fee_amount":500000,"source_token_mint_pubkey":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"}"#)
    }
    
    func testEncodingSwapWithDirectSwapParams() throws {
        let params = FeeRelayer.Relay.SwapParams(
            userSourceTokenAccountPubkey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3",
            userDestinationPubkey: "6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D",
            userDestinationAccountOwner: nil,
            sourceTokenMintPubkey: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            destinationTokenMintPubkey: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            userAuthorityPubkey: "6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D",
            userSwap: .init(createRelayDirectSwapParams(index: 0)),
            feeAmount: 500000,
            signatures: fakeSignature,
            blockhash: "FyGp8WQvMAMiXs1E3YHRPhQ9KeNquTGu9NdnnKudrF7S"
        )
        
        let data = try JSONEncoder().encode(params)
        let string = String(data: data, encoding: .utf8)
        
        XCTAssertEqual(string, #"{"destination_token_mint_pubkey":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","user_authority_pubkey":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","user_source_token_account_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","user_swap":{"pool_fee_account_pubkey":"EDuiPgd4PuCXe9h2YieMbH7uUMeB4pgeWnP5hfcPvxu3","account_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","destination_pubkey":"CRh1jz9Ahs4ZLdTDtsQqtTh8UWFDFre6NtvFTWXQspeX","amount_in":500000,"source_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","transfer_authority_pubkey":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","minimum_amount_out":500000,"authority_pubkey":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","program_id":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","pool_token_mint_pubkey":"3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC"},"signatures":{"user_authority_signature":"3rR2np1ZtgNa9QCnhGCybFXEiHKref7CAvpMA4DEh8yJ8gCF5oXKGzJZ8TEWTzUTQGZNm83CQyjyiSo2VHcQWXJd","transfer_authority_signature":"3rR2np1ZtgNa9QCnhGCybFXEiHKref7CAvpMA4DEh8yJ8gCF5oXKGzJZ8TEWTzUTQGZNm83CQyjyiSo2VHcQWXJd"},"blockhash":"FyGp8WQvMAMiXs1E3YHRPhQ9KeNquTGu9NdnnKudrF7S","user_destination_pubkey":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","source_token_mint_pubkey":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","fee_amount":500000}"#)
    }
    
    func testEncodingSwapWithTransitiveSwapParams() throws {
        let params = FeeRelayer.Relay.SwapParams(
            userSourceTokenAccountPubkey: "3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3",
            userDestinationPubkey: "CRh1jz9Ahs4ZLdTDtsQqtTh8UWFDFre6NtvFTWXQspeX",
            userDestinationAccountOwner: "CRh1jz9Ahs4ZLdTDtsQqtTh8UWFDFre6NtvFTWXQspeX",
            sourceTokenMintPubkey: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            destinationTokenMintPubkey: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            userAuthorityPubkey: "6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D",
            userSwap: .init(FeeRelayer.Relay.TransitiveSwapData(
                from: createRelayDirectSwapParams(index: 0),
                to: createRelayDirectSwapParams(index: 1),
                transitTokenMintPubkey: "3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC"
            )),
            feeAmount: 50000,
            signatures: fakeSignature,
            blockhash: "FyGp8WQvMAMiXs1E3YHRPhQ9KeNquTGu9NdnnKudrF7S"
        )
        
        let data = try JSONEncoder().encode(params)
        let string = String(data: data, encoding: .utf8)
        
        XCTAssertEqual(string, #"{"destination_token_mint_pubkey":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","user_authority_pubkey":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","user_source_token_account_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","user_swap":{"to":{"pool_fee_account_pubkey":"EDuiPgd4PuCXe9h2YieMbH7uUMeB4pgeWnP5hfcPvxu3","account_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","destination_pubkey":"CRh2jz9Ahs4ZLdTDtsQqtTh8UWFDFre6NtvFTWXQspeX","amount_in":500000,"source_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","transfer_authority_pubkey":"6Aj2GVxoCiEhhYTk9rNySg2QTgvtqSzR229KynihWH3D","minimum_amount_out":500000,"authority_pubkey":"6Aj2GVxoCiEhhYTk9rNySg2QTgvtqSzR229KynihWH3D","program_id":"6Aj2GVxoCiEhhYTk9rNySg2QTgvtqSzR229KynihWH3D","pool_token_mint_pubkey":"3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC"},"transit_token_mint_pubkey":"3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC","from":{"pool_fee_account_pubkey":"EDuiPgd4PuCXe9h2YieMbH7uUMeB4pgeWnP5hfcPvxu3","account_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","destination_pubkey":"CRh1jz9Ahs4ZLdTDtsQqtTh8UWFDFre6NtvFTWXQspeX","amount_in":500000,"source_pubkey":"3uetDDizgTtadDHZzyy9BqxrjQcozMEkxzbKhfZF4tG3","transfer_authority_pubkey":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","minimum_amount_out":500000,"authority_pubkey":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","program_id":"6Aj1GVxoCiEhhYTk9rNySg2QTgvtqSzR119KynihWH3D","pool_token_mint_pubkey":"3H5XKkE9uVvxsdrFeN4BLLGCmohiQN6aZJVVcJiXQ4WC"}},"signatures":{"user_authority_signature":"3rR2np1ZtgNa9QCnhGCybFXEiHKref7CAvpMA4DEh8yJ8gCF5oXKGzJZ8TEWTzUTQGZNm83CQyjyiSo2VHcQWXJd","transfer_authority_signature":"3rR2np1ZtgNa9QCnhGCybFXEiHKref7CAvpMA4DEh8yJ8gCF5oXKGzJZ8TEWTzUTQGZNm83CQyjyiSo2VHcQWXJd"},"blockhash":"FyGp8WQvMAMiXs1E3YHRPhQ9KeNquTGu9NdnnKudrF7S","user_destination_pubkey":"CRh1jz9Ahs4ZLdTDtsQqtTh8UWFDFre6NtvFTWXQspeX","source_token_mint_pubkey":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","fee_amount":50000}"#)
    }
}

// MARK: - Helpers
private func createRelayDirectSwapParams(index: Int) -> FeeRelayer.Relay.DirectSwapData {
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

private var fakeSignature: FeeRelayer.Relay.SwapTransactionSignatures {
    .init(
        userAuthoritySignature: "3rR2np1ZtgNa9QCnhGCybFXEiHKref7CAvpMA4DEh8yJ8gCF5oXKGzJZ8TEWTzUTQGZNm83CQyjyiSo2VHcQWXJd",
        transferAuthoritySignature: "3rR2np1ZtgNa9QCnhGCybFXEiHKref7CAvpMA4DEh8yJ8gCF5oXKGzJZ8TEWTzUTQGZNm83CQyjyiSo2VHcQWXJd"
    )
}
