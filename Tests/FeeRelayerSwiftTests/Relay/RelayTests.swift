import XCTest
import RxBlocking
import SolanaSwift
@testable import FeeRelayerSwift
import RxSwift
import OrcaSwapSwift

class RelayTests: XCTestCase {
    private let testsInfo = try! getDataFromJSONTestResourceFile(fileName: "relay-tests", decodedTo: RelayTestsInfo.self)
    
    private var solanaClient: SolanaSDK!
    private var orcaSwap: OrcaSwapType!
    private var relayService: FeeRelayer.Relay!
    
    override func tearDownWithError() throws {
        solanaClient = nil
        orcaSwap = nil
        relayService = nil
    }
    
    // MARK: - TopUp
    func testTopUp() throws {
        try topUp(testInfo: testsInfo.topUp!)
    }
    
    // MARK: - Swap
    /// Swap from SOL to SPL
    func testTopUpAndSwapFromSOL() throws {
        try swap(testInfo: testsInfo.solToSPL!)
    }
    
    /// Swap from SPL to SOL
    func testTopUpAndSwapToSOL() throws {
        try swap(testInfo: testsInfo.splToSOL!)
    }
    
    /// Swap from SPL to SPL
    func testTopUpAndSwapToCreatedToken() throws {
        try swap(testInfo: testsInfo.splToCreatedSpl!)
    }
    
    func testTopUpAndSwapToNonCreatedToken() throws {
        try swap(testInfo: testsInfo.splToNonCreatedSpl!)
    }
    
    // MARK: - Transfer spl tokens
    func testRelaySendNativeSOL() throws {
        try runRelaySendNativeSOL(testsInfo.relaySendNativeSOL!)
    }
    
    func testUSDTTransfer() throws {
        try runRelaySendSPLToken(testsInfo.usdtTransfer!)
    }
    
    func testUSDTBackTransfer() throws {
        try runRelaySendSPLToken(testsInfo.usdtBackTransfer!)
    }
    
    func testUSDTTransferToNonCreatedToken() throws {
        try runRelaySendSPLToken(testsInfo.usdtTransferToNonCreatedToken!)
    }
    
    // MARK: - Helpers
    private func topUp(testInfo: RelayTopUpTest) throws {
        try loadTest(testInfo)
        
        // paying token
        let payingToken = FeeRelayer.Relay.TokenInfo(
            address: testInfo.payingTokenAddress,
            mint: testInfo.payingTokenMint
        )
        
        // prepare params
        let relayAccountStatus = try relayService.getRelayAccountStatus(reuseCache: false).toBlocking().first()!
        
        let params = try relayService.prepareForTopUp(
            amount: .init(transaction: testInfo.amount, accountBalances: 0),
            payingFeeToken: payingToken,
            relayAccountStatus: relayAccountStatus
        ).toBlocking().first()!
        
        let signatures = try relayService.topUp(
            needsCreateUserRelayAddress: false,
            sourceToken: payingToken,
            amount: testInfo.amount,
            topUpPools: params.topUpFeesAndPools!.poolsPair,
            topUpFee: params.topUpFeesAndPools!.fee
        ).toBlocking().first()!
        
        XCTAssertTrue(signatures.count > 0)
    }
    
    private func swap(testInfo: RelaySwapTestInfo) throws {
        try loadTest(testInfo)
        
        // get pools pair
        let poolPairs = try orcaSwap.getTradablePoolsPairs(fromMint: testInfo.fromMint, toMint: testInfo.toMint).toBlocking().first()!
        
        // get best pool pair
        let pools = try orcaSwap.findBestPoolsPairForInputAmount(testInfo.inputAmount, from: poolPairs)!
        
        // request
        let sourceToken = FeeRelayer.Relay.TokenInfo(
            address: testInfo.sourceAddress,
            mint: testInfo.fromMint
        )
        
        let payingToken = FeeRelayer.Relay.TokenInfo(
            address: testInfo.payingTokenAddress,
            mint: testInfo.payingTokenMint
        )
        
        // calculate fee and needed topup amount
        let feeAndTopUpAmount = try relayService.calculateFeeAndNeededTopUpAmountForSwapping(
            sourceToken: sourceToken,
            destinationTokenMint: testInfo.toMint,
            destinationAddress: testInfo.destinationAddress,
            payingFeeToken: payingToken,
            swapPools: pools
        ).toBlocking().first()!
        let fee = feeAndTopUpAmount.feeInSOL?.total ?? 0
        let topUpAmount = feeAndTopUpAmount.topUpAmountInSOL ?? 0
        
        // get relay account balance
        let relayAccountBalance = try relayService.getRelayAccountStatus(reuseCache: false).toBlocking().first()?.balance ?? 0
        
        if fee > relayAccountBalance {
            XCTAssertEqual(topUpAmount, fee - relayAccountBalance)
        } else {
            XCTAssertEqual(topUpAmount, 0)
        }
        
        // prepare transaction
        let preparedTransaction = try relayService.prepareSwapTransaction(
            sourceToken: sourceToken,
            destinationTokenMint: testInfo.toMint,
            destinationAddress: testInfo.destinationAddress,
            payingFeeToken: payingToken,
            swapPools: pools,
            inputAmount: testInfo.inputAmount,
            slippage: 0.05
        ).toBlocking().first()!
        
        // send to relay service
        let signatures = try relayService.topUpAndRelayTransaction(
            preparedTransaction: preparedTransaction,
            payingFeeToken: payingToken
        ).toBlocking().first()!
        
        print(signatures)
        XCTAssertTrue(signatures.count > 0)
    }
    
    func runRelaySendNativeSOL(_ test: RelayTransferNativeSOLTestInfo) throws {
        let feeRelayerAPIClient = try loadTest(test)
        
        let payingToken = FeeRelayer.Relay.TokenInfo(
            address: test.payingTokenAddress,
            mint: test.payingTokenMint
        )
        
        let feePayer = try feeRelayerAPIClient.getFeePayerPubkey().toBlocking().first()!
        
        let preparedTransaction = try solanaClient.prepareSendingNativeSOL(
            to: test.destination,
            amount: test.inputAmount,
            feePayer: try SolanaSDK.PublicKey(string: feePayer)
        ).toBlocking().first()!
        
        XCTAssertEqual(preparedTransaction.expectedFee.total, test.expectedFee)
        
        let signature = try relayService.topUpAndRelayTransaction(
            preparedTransaction: preparedTransaction,
            payingFeeToken: payingToken
        ).toBlocking().first()
        print(signature ?? "Nothing")
    }
    
    func runRelaySendSPLToken(_ test: RelayTransferTestInfo) throws {
        let feeRelayerAPIClient = try loadTest(test)
        
        let payingToken = FeeRelayer.Relay.TokenInfo(
            address: test.payingTokenAddress,
            mint: test.payingTokenMint
        )
        
        let feePayer = try feeRelayerAPIClient.getFeePayerPubkey().toBlocking().first()!
        
        let preparedTransaction = try solanaClient.prepareSendingSPLTokens(
            mintAddress: test.mint,
            decimals: 6,
            from: test.sourceTokenAddress,
            to: test.destinationAddress,
            amount: 100,
            feePayer: try SolanaSDK.PublicKey(string: feePayer),
            transferChecked: true
        ).toBlocking().first()!.preparedTransaction
        
        XCTAssertEqual(preparedTransaction.expectedFee.total, test.expectedFee)
        
        let signature = try relayService.topUpAndRelayTransaction(
            preparedTransaction: preparedTransaction,
            payingFeeToken: payingToken
        ).toBlocking().first()
        print(signature ?? "Nothing")
    }
    
    @discardableResult
    private func loadTest(_ relayTest: RelayTestType) throws -> FeeRelayerAPIClientType {
        let network = SolanaSDK.Network.mainnetBeta
        let accountStorage = FakeAccountStorage(seedPhrase: relayTest.seedPhrase, network: network)
        let endpoint = SolanaSDK.APIEndPoint(address: relayTest.endpoint, network: network, additionalQuery: relayTest.endpointAdditionalQuery)
        solanaClient = SolanaSDK(endpoint: endpoint, accountStorage: accountStorage)
        orcaSwap = OrcaSwap(
            apiClient: OrcaSwap.APIClient(network: network.cluster),
            solanaClient: solanaClient,
            accountProvider: accountStorage,
            notificationHandler: FakeNotificationHandler()
        )
        
        let apiClient = FeeRelayer.APIClient(version: 1)
        relayService = try FeeRelayer.Relay(
            apiClient: apiClient,
            solanaClient: solanaClient,
            accountStorage: accountStorage,
            orcaSwapClient: orcaSwap
        )
        
        _ = try orcaSwap.load().toBlocking().first()
        _ = try relayService.load().toBlocking().first()
        
        return apiClient
    }
}
