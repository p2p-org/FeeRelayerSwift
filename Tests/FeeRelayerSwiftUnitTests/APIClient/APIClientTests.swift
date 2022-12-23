import XCTest
@testable import FeeRelayerSwift
import SolanaSwift

class APIClientTests: XCTestCase {
    var feeRelayerAPIClient: FeeRelayerAPIClient!

    override func setUp() async throws {
        feeRelayerAPIClient = APIClient(
            httpClient: FeeRelayerHTTPClient(networkManager: MockNetworkManager()),
            baseUrlString: "",
            version: 1
        )
    }
    
    override func tearDown() async throws {
        feeRelayerAPIClient = nil
    }

    func testGetFeeRelayerPubkey() async throws {
        let result = try await feeRelayerAPIClient.getFeePayerPubkey()
        XCTAssertEqual(result, "HkLNnxTFst1oLrKAJc3w6Pq8uypRnqLMrC68iBP6qUPu")
    }

    func testGetFreeTransactionFeeLimit() async throws {
        let result = try await feeRelayerAPIClient.getFreeFeeLimits(for: "GZpacnxxvtFDMg16KWSH8q2g8tM7fwJvNMkb2Df34h9N")
        XCTAssertEqual(result.authority.count, 32)
    }

    func testSendTransaction() async throws {
        let mockedTransaction = PreparedTransaction(
            transaction: .init(
                instructions: [
                    try AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
                        mint: .renBTCMint,
                        owner: "6QuXb6mB6WmRASP2y8AavXh6aabBXEH5ZzrSH5xRrgSm",
                        payer: "HkLNnxTFst1oLrKAJc3w6Pq8uypRnqLMrC68iBP6qUPu"
                    )
                ],
                recentBlockhash: "CSymwgTNX1j3E4qhKfJAUE41nBWEwXufoYryPbkde5RR",
                feePayer: "HkLNnxTFst1oLrKAJc3w6Pq8uypRnqLMrC68iBP6qUPu"),
            signers: [],
            expectedFee: .zero
        )
        
        let txs = try await feeRelayerAPIClient.sendTransaction(
            .relayTransaction(
                .init(
                    preparedTransaction: mockedTransaction,
                    statsInfo: .init(
                        operationType: .transfer,
                        deviceType: .iOS,
                        currency: "SOL",
                        build: "2.0.0",
                        environment: .dev
                    )
                )
            )
        )
        XCTAssertEqual(txs, "39ihraT1nDRgJbg8owTukvoqJ2cqb84qXGdkjtLbpGuGrgyCpr4F2v57XpvNaJxysEpGWatMFG6zQi6rc91689P2")
    }

}

// MARK: - Mocks

private class MockNetworkManager: FeeRelayerSwift.NetworkManager {
    func requestData(request: URLRequest) async throws -> (Data, URLResponse) {
        let mockResponse = [
            "fee_payer/pubkey":
                "HkLNnxTFst1oLrKAJc3w6Pq8uypRnqLMrC68iBP6qUPu",
            "relay_transaction": #"["39ihraT1nDRgJbg8owTukvoqJ2cqb84qXGdkjtLbpGuGrgyCpr4F2v57XpvNaJxysEpGWatMFG6zQi6rc91689P2"]"#,
            "free_fee_limits": #"{"authority":[248,212,223,178,166,140,226,200,49,138,199,37,185,198,86,76,169,111,67,246,105,211,42,108,78,241,50,193,161,53,54,140],"limits":{"use_free_fee":true,"max_amount":10000000,"max_count":100,"period":{"secs":86400,"nanos":0}},"processed_fee":{"total_amount":20000,"count":2}}"#
        ]
        
        
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        guard let result = mockResponse.first(where: {request.url!.absoluteString.contains($0.key)})
        else {
            fatalError()
        }
        
        return (result.value.data(using: .utf8)!, response)
    }
}
