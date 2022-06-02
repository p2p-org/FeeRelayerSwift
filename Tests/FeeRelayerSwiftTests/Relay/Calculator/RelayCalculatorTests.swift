import XCTest
@testable import FeeRelayerSwift
import SolanaSwift
import Cuckoo

class RelayCalculatorTests: XCTestCase {
    var account: Account!
    let endpoint = APIEndPoint(
        address: "https://api.mainnet-beta.solana.com",
        network: .mainnetBeta
    )
    let accountStorage = FakeAccountStorage(
        seedPhrase: "miracle pizza supply useful steak border same again youth silver access hundred",
        network: .mainnetBeta
    )
    
    var calculator = DefaultFreeRelayerCalculator()

    override func setUp() async throws {
        account = try await Account(
            phrase: "miracle pizza supply useful steak border same again youth silver access hundred"
                .components(separatedBy: " "),
            network: .mainnetBeta
        )
    }

    func testCalculateExpectedFeeForTopUp() async throws {
        let solanaApiClient = MockFakeJSONRPCAPIClient(endpoint: endpoint)
        let feeRelayerAPIClient = MockFakeFeeRelayerAPIClient()
        
        stub(solanaApiClient) { stub in
            when(stub.getMinimumBalanceForRentExemption(dataLength: UInt64(165), commitment: any()))
                .thenReturn(890_880)
            when(stub.getMinimumBalanceForRentExemption(dataLength: UInt64(0), commitment: any()))
                .thenReturn(890_880)
            when(stub.getFees(commitment: any())).thenReturn(fakeFee)
            when(stub.getAccountInfo(account: any())).thenReturn(fakeAccountInfo)
        }
        stub(feeRelayerAPIClient) { stub in
            when(stub.getFeePayerPubkey()).thenReturn("FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT")
            when(stub.requestFreeFeeLimits(for: any())).thenReturn(.init(authority: [], limits: .init(useFreeFee: false, maxAmount: 1, maxCount: 1, period: .init(secs: 1, nanos: 1)), processedFee: .init(totalAmount: 1, count: 1)))
        }
        
        
        let contextManager = FeeRelayerContextManagerImpl(
            accountStorage: accountStorage,
            solanaAPIClient: solanaApiClient,
            feeRelayerAPIClient: feeRelayerAPIClient
        )
        try await contextManager.update()
        let ctx = try await contextManager.getCurrentContext()
        
        let result = try calculator.calculateExpectedFeeForTopUp(ctx)
        XCTAssertEqual(900_880, result)
    }
    
    func testCalculateNeededTopUpAmount() async throws {
        
        let solanaApiClient = MockFakeJSONRPCAPIClient(endpoint: endpoint)
        let feeRelayerAPIClient = MockFakeFeeRelayerAPIClient()
        
        stub(solanaApiClient) { stub in
            when(stub.getMinimumBalanceForRentExemption(dataLength: UInt64(165), commitment: any()))
                .thenReturn(0)
            when(stub.getMinimumBalanceForRentExemption(dataLength: UInt64(0), commitment: any()))
                .thenReturn(0)
            when(stub.getFees(commitment: any())).thenReturn(fakeFee)
            when(stub.getAccountInfo(account: any())).thenReturn(fakeAccountInfo)
        }
        stub(feeRelayerAPIClient) { stub in
            when(stub.getFeePayerPubkey()).thenReturn("FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT")
            when(stub.requestFreeFeeLimits(for: any())).thenReturn(.init(authority: [231], limits: .init(useFreeFee: true, maxAmount: 10000000, maxCount: 100, period: .init(secs: 86400, nanos: 0)), processedFee: .init(totalAmount: 0, count: 0)))
        }
        
        let contextManager = FeeRelayerContextManagerImpl(
            accountStorage: accountStorage,
            solanaAPIClient: solanaApiClient,
            feeRelayerAPIClient: feeRelayerAPIClient
        )
        try await contextManager.update()
        let ctx = try await contextManager.getCurrentContext()
        
        let result = try await calculator.calculateNeededTopUpAmount(
            ctx,
            expectedFee: FeeAmount(transaction: 2000, accountBalances: 10000000),
            payingTokenMint: try! PublicKey(string: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        )
        XCTAssertEqual(7960720, result.accountBalances)
    }
    
    var fakeFee: Fee = {
        let fee = "{\"context\":{\"slot\":131770081},\"value\":{\"blockhash\":\"7jvToPQ4ASj3xohjM117tMqmtppQDaWVADZyaLFnytFr\",\"feeCalculator\":{\"lamportsPerSignature\":5000},\"lastValidBlockHeight\":119512694,\"lastValidSlot\":131770381}}".data(using: .utf8)!
        return try! JSONDecoder().decode(Rpc<Fee>.self, from: fee).value
    }()
    
    var fakeAccountInfo: BufferInfo<EmptyInfo>? = {
        let fee = "{\"context\":{\"slot\":131421172},\"value\":{\"data\":[\"xvp6877brTo9ZfNqq8l0MbG75MLS9uDkfKYCA0UvXWF9P8kKbTPTsQZqMMzOan8jwyOl0jQaxrCPh8bU1ysTa96DDAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"base64\"],\"executable\":false,\"lamports\":2039280,\"owner\":\"TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA\",\"rentEpoch\":304}}".data(using: .utf8)!
        return try! JSONDecoder().decode(Rpc<BufferInfo<EmptyInfo>?>.self, from: fee).value
    }()
}
