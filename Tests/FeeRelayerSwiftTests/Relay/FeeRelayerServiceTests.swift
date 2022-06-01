import XCTest
@testable import FeeRelayerSwift
import SolanaSwift
import OrcaSwapSwift
import Cuckoo

class FeeRelayerServiceTests: XCTestCase {
    
    var account: Account!
    let endpoint = APIEndPoint(
        address: "https://api.mainnet-beta.solana.com",
        network: .mainnetBeta
    )

    override func setUp() async throws {
        account = try await Account(
            phrase: "miracle pizza supply useful steak border same again youth silver access hundred"
                .components(separatedBy: " "),
            network: .mainnetBeta
        )
    }
    
    let feeRelayerAPIClient = MockFakeFeeRelayerAPIClient()
    lazy var solanaAPIClient = MockFakeJSONRPCAPIClient(endpoint: self.endpoint)
    let orcaSwapAPIClient = MockFakeOrcaSwapAPIClient(configsProvider: MockConfigsProvider())
    
    func testGetFeePayer() async throws {
        let expectedPubKey = "FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT"
        
        let orcaSwap = MockFakeOrcaSwap(
            apiClient: orcaSwapAPIClient,
            solanaClient: solanaAPIClient,
            blockchainClient: MockFakeSolanaBlockchainClient(apiClient: solanaAPIClient),
            accountStorage: FakeAccountStorage(seedPhrase: "", network: .mainnetBeta)
        )
        
        stub(feeRelayerAPIClient) { stub in
            when(stub.getFeePayerPubkey()).thenReturn(expectedPubKey)
        }
        let relayService = FeeRelayerService(
            account: account,
            orcaSwap: orcaSwap,
            solanaApiClient: solanaAPIClient,
            feeCalculator: DefaultFreeRelayerCalculator(),
            feeRelayerAPIClient: APIClient(version: 1),
            deviceType: .iOS,
            buildNumber: "1"
        )
        
        let res = try await relayService.getFeePayer().base58EncodedString
        XCTAssertEqual(res, expectedPubKey)
    }
    
    func testPrepareForTopup() async throws {
        let expectedPubKey = "FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT"
        
        let orcaSwap = MockFakeOrcaSwap(
            apiClient: orcaSwapAPIClient,
            solanaClient: solanaAPIClient,
            blockchainClient: MockFakeSolanaBlockchainClient(apiClient: solanaAPIClient),
            accountStorage: FakeAccountStorage(seedPhrase: "", network: .mainnetBeta)
        )
    
        let relayService = FeeRelayerService(
            account: account,
            orcaSwap: orcaSwap,
            solanaApiClient: solanaAPIClient,
            feeCalculator: DefaultFreeRelayerCalculator(),
            feeRelayerAPIClient: APIClient(version: 1),
            deviceType: .iOS,
            buildNumber: "1"
        )
        
        stub(solanaAPIClient) { stub in
            when(stub.getMinimumBalanceForRentExemption(dataLength: UInt64(165), commitment: any()))
                .thenReturn(890_880)
            when(stub.getMinimumBalanceForRentExemption(dataLength: UInt64(0), commitment: any()))
                .thenReturn(890_880)
            when(stub.getFees(commitment: any())).thenReturn(fakeFee)
            when(stub.getAccountInfo(account: any())).thenReturn(fakeAccountInfo)
            when(stub.getTokenAccountBalance(pubkey: any(), commitment: any()))
                .thenReturn(fakeTokenAccountBalance)
        }
                 
        stub(feeRelayerAPIClient) { stub in
            when(stub.getFeePayerPubkey()).thenReturn(expectedPubKey)
            when(stub.requestFreeFeeLimits(for: any())).thenReturn(.init(authority: [], limits: .init(useFreeFee: false, maxAmount: 1, maxCount: 1, period: .init(secs: 1, nanos: 1)), processedFee: .init(totalAmount: 1, count: 1)))
        }
        
        let ctx = try await FeeRelayerContext.create(
            userAccount: account,
            solanaAPIClient: solanaAPIClient,
            feeRelayerAPIClient: feeRelayerAPIClient
        )
        
        let payingToken = TokenAccount(
            address: try! PublicKey(string: "mCZrAFuPfBDPUW45n5BSkasRLpPZpmqpY7vs3XSYE7x"),
            mint: try! PublicKey(string: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        )
        
        let res = try await relayService.prepareForTopUp(
            ctx,
            topUpAmount: 10_000,
            payingFeeToken: payingToken
        )
        
        XCTAssertEqual(res?.amount, 10_000)
        XCTAssertEqual(res?.expectedFee, 900_880)
    }
    
    var fakeFee: Fee = {
        let fee = "{\"context\":{\"slot\":131770081},\"value\":{\"blockhash\":\"7jvToPQ4ASj3xohjM117tMqmtppQDaWVADZyaLFnytFr\",\"feeCalculator\":{\"lamportsPerSignature\":5000},\"lastValidBlockHeight\":119512694,\"lastValidSlot\":131770381}}".data(using: .utf8)!
        return try! JSONDecoder().decode(Rpc<Fee>.self, from: fee).value
    }()
    
    var fakeAccountInfo: BufferInfo<EmptyInfo>? = {
        let fee = "{\"context\":{\"slot\":131421172},\"value\":{\"data\":[\"xvp6877brTo9ZfNqq8l0MbG75MLS9uDkfKYCA0UvXWF9P8kKbTPTsQZqMMzOan8jwyOl0jQaxrCPh8bU1ysTa96DDAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"base64\"],\"executable\":false,\"lamports\":2039280,\"owner\":\"TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA\",\"rentEpoch\":304}}".data(using: .utf8)!
        return try! JSONDecoder().decode(Rpc<BufferInfo<EmptyInfo>?>.self, from: fee).value
    }()
                 
    var fakeTokenAccountBalance: TokenAccountBalance = {
        let token = #"{"amount":"491717631607","decimals":9,"uiAmount":491.717631607,"uiAmountString":"491.717631607"}"#.data(using: .utf8)!
        return try! JSONDecoder().decode(TokenAccountBalance.self, from: token)
    }()

    
}
