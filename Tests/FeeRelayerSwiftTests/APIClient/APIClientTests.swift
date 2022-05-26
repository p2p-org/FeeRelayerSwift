import XCTest
@testable import FeeRelayerSwift
import RxBlocking
import SolanaSwift

class APIClientTests: XCTestCase {
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
    
    func testGetFeeRelayerPubkey() async throws {
        let expected = "FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT"
        let feeRelayer = APIClientMock(version: 1)
        let result = try await feeRelayer.getFeePayerPubkey()
        XCTAssertEqual(result.isEmpty, false)
        XCTAssertEqual(result, expected)
    }
    
    func testGetFreeTransactionFeeLimit() async throws {
        let feeRelayer = APIClientMock(version: 1)
        let result = try await feeRelayer.requestFreeFeeLimits(for: "GZpacnxxvtFDMg16KWSH8q2g8tM7fwJvNMkb2Df34h9N")
        XCTAssertNotNil(result)
        XCTAssertEqual(result.authority.first, 231)
    }
    
    func testSendTransaction() async throws {
        let feeRelayer = APIClientMock(version: 1)

        let toPublicKey = "6QuXb6mB6WmRASP2y8AavXh6aabBXEH5ZzrSH5xRrgSm"
        let apiClient = SolanaAPIClientMock(endpoint: endpoint)
        
        let blockchain = BlockchainClient(apiClient: apiClient)

        let tx = try await blockchain.prepareSendingNativeSOL(
            from: account,
            to: toPublicKey,
            amount: 1,
            feePayer: account.publicKey
        )

        let recentBlockhash = try await apiClient.getRecentBlockhash()
        
        var preparedTransaction = tx
        preparedTransaction.transaction.recentBlockhash = recentBlockhash
        preparedTransaction.signers = [account]
        try preparedTransaction.sign()

        let txs = try await feeRelayer.sendTransaction(.relayTransaction(
            .init(preparedTransaction: preparedTransaction)
        ))
        XCTAssertNotNil(txs)
        XCTAssertEqual(txs, "123")
    }
    
}

class APIClientMock: FeeRelayerSwift.APIClient {

    // MARK: - Initializers

    public override init(httpClient: HTTPClient = FeeRelayerHTTPClient(networkManager: MockNetworkManager()), version: Int) {
        super.init(httpClient: httpClient, version: version)
    }
}

// MARK: - Mocks

class MockNetworkManager: FeeRelayerSwift.NetworkManager {
    func requestData(request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        if request.url?.absoluteString.contains("relay_transaction") ?? false {
            return (
                "123".data(using: .utf8)!,
                response
            )
        } else if request.url?.absoluteString.contains("free_fee_limits") ?? false {
            return (
                NetworkManagerMockJSON["fee"]!.data(using: .utf8)!,
                response
            )
        } else {
            return (
                "FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT".data(using: .utf8)!,
                response
            )
        }
        fatalError()
    }
    
    private let NetworkManagerMockJSON = [
        "fee": "{\"authority\":[231],\"limits\":{\"use_free_fee\":true,\"max_amount\":10000000,\"max_count\":100,\"period\":{\"secs\":86400,\"nanos\":0}},\"processed_fee\":{\"total_amount\":0,\"count\":0}}"
    ]
}

class MockHTTPClient: HTTPClient {
    var networkManager: FeeRelayerSwift.NetworkManager = MockNetworkManager()
    func sendRequest<T>(request: URLRequest, decoder: JSONDecoder) async throws -> T where T : Decodable {
        if request.url?.absoluteString.contains("relay_transaction") ?? false {
        let json = "123".data(using: .utf8)!
            return try decoder.decode(T.self, from: json)
        }
        fatalError()
    }
}

class SolanaAPIClientMock: SolanaAPIClient {
    
    init(endpoint: APIEndPoint) {
        self.endpoint = endpoint
    }
    
    private let NetworkManagerMockJSON = [
        "getAccountInfo": "{\"context\":{\"slot\":132713905},\"value\":{\"data\":[\"\",\"base64\"],\"executable\":false,\"lamports\":14092740,\"owner\":\"11111111111111111111111111111111\",\"rentEpoch\":307}}"
        , "getFees": "{\"context\":{\"slot\":131770081},\"value\":{\"blockhash\":\"7jvToPQ4ASj3xohjM117tMqmtppQDaWVADZyaLFnytFr\",\"feeCalculator\":{\"lamportsPerSignature\":5000},\"lastValidBlockHeight\":119512694,\"lastValidSlot\":131770381}}"
        , "sendTransaction": "{\"jsonrpc\":\"2.0\",\"result\":\"123\",\"id\":\"3FF1AACE-812A-4106-8C34-6EF66237673C\"}\n",
    ]
    
    func getAccountInfo<T: BufferLayout>(account: String) async throws -> BufferInfo<T>? {
        let json = NetworkManagerMockJSON["getAccountInfo"]!.data(using: .utf8)!
        let ret = try! JSONDecoder().decode(Rpc<BufferInfo<T>?>.self, from: json)
        return ret.value!
    }
    
    // MARK: -
    
    var endpoint: APIEndPoint
    
    func getBalance(account: String, commitment: Commitment?) async throws -> UInt64 {
        fatalError()
    }
    
    func getBlockCommitment(block: UInt64) async throws -> BlockCommitment {
        fatalError()
    }
    
    func getBlockTime(block: UInt64) async throws -> Date {
        fatalError()
    }
    
    func getClusterNodes() async throws -> [ClusterNodes] {
        fatalError()
    }
    
    func getBlockHeight() async throws -> UInt64 {
        fatalError()
    }
    
    func getConfirmedBlocksWithLimit(startSlot: UInt64, limit: UInt64) async throws -> [UInt64] {
        fatalError()
    }
    
    func getConfirmedBlock(slot: UInt64, encoding: String) async throws -> ConfirmedBlock {
        fatalError()
    }
    
    func getConfirmedSignaturesForAddress(account: String, startSlot: UInt64, endSlot: UInt64) async throws -> [String] {
        fatalError()
    }
    
    func getEpochInfo(commitment: Commitment?) async throws -> EpochInfo {
        fatalError()
    }
    
    func getFees(commitment: Commitment?) async throws -> Fee {
        let json = NetworkManagerMockJSON["getFees"]!.data(using: .utf8)!
        let ret = try! JSONDecoder().decode(Fee.self, from: json)
        return ret
    }
    
    func getSignatureStatuses(signatures: [String], configs: RequestConfiguration?) async throws -> [SignatureStatus?] {
        fatalError()
    }
    
    func getSignatureStatus(signature: String, configs: RequestConfiguration?) async throws -> SignatureStatus {
        fatalError()
    }
    
    func getTokenAccountBalance(pubkey: String, commitment: Commitment?) async throws -> TokenAccountBalance {
        fatalError()
    }
    
    func getTokenAccountsByDelegate(pubkey: String, mint: String?, programId: String?, configs: RequestConfiguration?) async throws -> [SolanaSwift.TokenAccount<AccountInfo>] {
        fatalError()
    }
    
    func getTokenAccountsByOwner(pubkey: String, params: OwnerInfoParams?, configs: RequestConfiguration?) async throws -> [SolanaSwift.TokenAccount<AccountInfo>] {
        fatalError()
    }
    
    func getTokenLargestAccounts(pubkey: String, commitment: Commitment?) async throws -> [TokenAmount] {
        fatalError()
    }
    
    func getTokenSupply(pubkey: String, commitment: Commitment?) async throws -> TokenAmount {
        fatalError()
    }
    
    func getVersion() async throws -> Version {
        fatalError()
    }
    
    func getVoteAccounts(commitment: Commitment?) async throws -> VoteAccounts {
        fatalError()
    }
    
    func minimumLedgerSlot() async throws -> UInt64 {
        fatalError()
    }
    
    func requestAirdrop(account: String, lamports: UInt64, commitment: Commitment?) async throws -> String {
        fatalError()
    }
    
    func sendTransaction(transaction: String, configs: RequestConfiguration) async throws -> TransactionID {
        fatalError()
    }
    
    func simulateTransaction(transaction: String, configs: RequestConfiguration) async throws -> SimulationResult {
        fatalError()
    }
    
    func setLogFilter(filter: String) async throws -> String? {
        fatalError()
    }
    
    func validatorExit() async throws -> Bool {
        fatalError()
    }
    
    func getMultipleAccounts<T>(pubkeys: [String]) async throws -> [BufferInfo<T>] where T : BufferLayout {
        fatalError()
    }
    
    func getSignaturesForAddress(address: String, configs: RequestConfiguration?) async throws -> [SignatureInfo] {
        fatalError()
    }
    
    func getMinimumBalanceForRentExemption(dataLength: UInt64, commitment: Commitment?) async throws -> UInt64 {
        2_039_280
    }
    
    func observeSignatureStatus(signature: String, timeout: Int, delay: Int) -> AsyncStream<TransactionStatus> {
        fatalError()
    }
    
    func getRecentBlockhash(commitment: Commitment?) async throws -> String {
//        switch testCase {
//        case "testPrepareSendingNativeSOL()":
            return "DSfeYUm7WDw1YnKodR361rg8sUzUCGdat9V7fSKPFgzq"
//        case "testPrepareSendingSPLTokens()#1":
//            return "9VG1E6DTdjRRx2JpbXrH9QPTQQ6FRjakvStttnmSV7fR"
//        case "testPrepareSendingSPLTokens()#2":
//            return "3uRa2bbJgTKVEKmZqKRtfWfhZF5YMn4D9xE64NYvTh4v"
//        case "testPrepareSendingSPLTokens()#3":
//            return "4VXrgGDjah4rCo2bvqSWXJTLbaDkmn4NTXknLn9GzacN"
//        case "testPrepareSendingSPLTokens()#4":
//            return "Bc11qGhSE3Vham6cBWEUxhRVVSNtzkyisdGGXwh6hvnT"
//        case "testPrepareSendingSPLTokens()#5":
//            return "7GhCDV2MK7RVhYzD3iNZAVkCd9hYCgyqkgXdFbEFj9PD"
//        default:
//            fatalError()
//        }
    }
}
