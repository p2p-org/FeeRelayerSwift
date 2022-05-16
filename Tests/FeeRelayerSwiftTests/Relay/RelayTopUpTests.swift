import Foundation
import XCTest
import SolanaSwift
import RxSwift
import OrcaSwapSwift
@testable import FeeRelayerSwift

class RelayTopUpTests: RelayTests {
    // MARK: - Amount test
    func testTopUpAmount() throws {
        let relayTest = testsInfo.topUp!
        let network = SolanaSDK.Network.mainnetBeta
        let endpoint = SolanaSDK.APIEndPoint(address: relayTest.endpoint, network: network, additionalQuery: relayTest.endpointAdditionalQuery)
        
        let neededTransactionFee: UInt64 = 10000
        let neededTopUpTransactionFee: UInt64 = 10000
        
        // CASE1: FREE TRANSACTION FEE IS AVAILABLE
        // account balance fee is zero
        XCTAssertEqual(
            try calculateNeededTopUpAmount(
                endpoint: endpoint,
                seedPhrase: relayTest.seedPhrase,
                relayAccountStatus: .notYetCreated,
                isFreeTransactionAvailable: true,
                expectedFee: .init(transaction: neededTransactionFee, accountBalances: 0)
            ).total,
            0
        )
        
        // relay account is not yet created
        XCTAssertEqual(
            try calculateNeededTopUpAmount(
                endpoint: endpoint,
                seedPhrase: relayTest.seedPhrase,
                relayAccountStatus: .notYetCreated,
                isFreeTransactionAvailable: true,
                expectedFee: .init(transaction: neededTransactionFee, accountBalances: relayTest.amount)
            ).total,
            relayTest.amount + 890880
        )
        
        // relay account has already been created with balance < min relay account balance
        XCTAssertEqual(
            try calculateNeededTopUpAmount(
                endpoint: endpoint,
                seedPhrase: relayTest.seedPhrase,
                relayAccountStatus: .created(balance: 889646),
                isFreeTransactionAvailable: true,
                expectedFee: .init(transaction: neededTransactionFee, accountBalances: relayTest.amount)
            ).total,
            relayTest.amount + 1234
        )
        
        // relay account has already been created with balance == min relay account balance
        XCTAssertEqual(
            try calculateNeededTopUpAmount(
                endpoint: endpoint,
                seedPhrase: relayTest.seedPhrase,
                relayAccountStatus: .created(balance: 890880),
                isFreeTransactionAvailable: true,
                expectedFee: .init(transaction: neededTransactionFee, accountBalances: relayTest.amount)
            ).total,
            relayTest.amount
        )
        
        // relay account has already been created with balance > min relay account balance
        XCTAssertEqual(
            try calculateNeededTopUpAmount(
                endpoint: endpoint,
                seedPhrase: relayTest.seedPhrase,
                relayAccountStatus: .created(balance: 890880 + 1234),
                isFreeTransactionAvailable: true,
                expectedFee: .init(transaction: neededTransactionFee, accountBalances: relayTest.amount)
            ).total,
            relayTest.amount - 1234
        )
        
        // CASE2: FREE TRANSACTION FEE IS NOT AVAILABLE
        // account balance fee is zero
        XCTAssertEqual(
            try calculateNeededTopUpAmount(
                endpoint: endpoint,
                seedPhrase: relayTest.seedPhrase,
                relayAccountStatus: .notYetCreated,
                isFreeTransactionAvailable: false,
                expectedFee: .init(transaction: neededTransactionFee, accountBalances: 0)
            ).total,
            890880 + neededTransactionFee + neededTopUpTransactionFee
        )
        
        // relay account is not yet created
        XCTAssertEqual(
            try calculateNeededTopUpAmount(
                endpoint: endpoint,
                seedPhrase: relayTest.seedPhrase,
                relayAccountStatus: .notYetCreated,
                isFreeTransactionAvailable: false,
                expectedFee: .init(transaction: neededTransactionFee, accountBalances: relayTest.amount)
            ).total,
            relayTest.amount + 890880 + neededTransactionFee + neededTopUpTransactionFee
        )
        
        // relay account has already been created with balance < min relay account balance
        XCTAssertEqual(
            try calculateNeededTopUpAmount(
                endpoint: endpoint,
                seedPhrase: relayTest.seedPhrase,
                relayAccountStatus: .created(balance: 890880-1234),
                isFreeTransactionAvailable: false,
                expectedFee: .init(transaction: neededTransactionFee, accountBalances: relayTest.amount)
            ).total,
            relayTest.amount + 1234 + neededTransactionFee + neededTopUpTransactionFee
        )
        
        // relay account has already been created with balance == min relay account balance
        XCTAssertEqual(
            try calculateNeededTopUpAmount(
                endpoint: endpoint,
                seedPhrase: relayTest.seedPhrase,
                relayAccountStatus: .created(balance: 890880),
                isFreeTransactionAvailable: false,
                expectedFee: .init(transaction: neededTransactionFee, accountBalances: relayTest.amount)
            ).total,
            relayTest.amount + neededTransactionFee + neededTopUpTransactionFee
        )
        
        // relay account has already been created with balance > min relay account balance
        XCTAssertEqual(
            try calculateNeededTopUpAmount(
                endpoint: endpoint,
                seedPhrase: relayTest.seedPhrase,
                relayAccountStatus: .created(balance: 890880+1234),
                isFreeTransactionAvailable: false,
                expectedFee: .init(transaction: neededTransactionFee, accountBalances: relayTest.amount)
            ).total,
            relayTest.amount - 1234 + neededTransactionFee + neededTopUpTransactionFee
        )
    }
    
    func testTopUp() throws {
        try topUp(testInfo: testsInfo.topUp!)
    }
    
    // MARK: - Helpers
    private func calculateNeededTopUpAmount(
        endpoint: SolanaSDK.APIEndPoint,
        seedPhrase: String,
        relayAccountStatus: FeeRelayer.Relay.RelayAccountStatus,
        isFreeTransactionAvailable: Bool,
        expectedFee: SolanaSDK.FeeAmount
    ) throws -> SolanaSDK.FeeAmount {
        let solanaClient = FakeSolanaClient(endpoint: endpoint, relayAccountStatus: relayAccountStatus)
        let orcaSwapClient = FakeOrcaSwap()
        let feeRelayerAPIClient = FakeFeeRelayerAPIClient(maxCount: 10, count: isFreeTransactionAvailable ? 0: 10)
        
        let relayService = try FeeRelayer.Relay(
            apiClient: feeRelayerAPIClient,
            solanaClient: solanaClient,
            accountStorage: FakeAccountStorage(seedPhrase: seedPhrase, network: endpoint.network),
            orcaSwapClient: orcaSwapClient
        )
        let _ = try relayService.load().toBlocking().first()
        let neededTopUpAmount = try relayService.calculateNeededTopUpAmount(expectedFee: expectedFee, payingTokenMint: nil).toBlocking().first()!
        return neededTopUpAmount
    }
    
    private func topUp(testInfo: RelayTopUpTest) throws {
        try loadTest(testInfo)

        // paying token
        let payingToken = FeeRelayer.Relay.TokenInfo(
            address: testInfo.payingTokenAddress,
            mint: testInfo.payingTokenMint
        )

        // prepare params
        let relayAccountStatus = try relayService.getRelayAccountStatus().toBlocking().first()!
        let freeTransactionFeeLimit = try relayService.getFreeTransactionFeeLimit().toBlocking().first()!
        
        let topUpAmount = try relayService.calculateNeededTopUpAmount(expectedFee: .init(transaction: 10000, accountBalances: testInfo.amount), payingTokenMint: nil).toBlocking().first()!.total
        
        let params = try relayService.prepareForTopUp(
            topUpAmount: topUpAmount,
            payingFeeToken: payingToken,
            relayAccountStatus: relayAccountStatus,
            freeTransactionFeeLimit: freeTransactionFeeLimit,
            forceUsingTransitiveSwap: true
        ).toBlocking().first()!
        
        let signatures = try relayService.topUp(
            needsCreateUserRelayAddress: relayAccountStatus == .notYetCreated,
            sourceToken: payingToken,
            targetAmount: params!.amount,
            topUpPools: params!.poolsPair,
            expectedFee: params!.expectedFee
        ).toBlocking().first()!

        XCTAssertTrue(signatures.count > 0)
    }
}

private class FakeSolanaClient: FeeRelayerRelaySolanaClient {
    let endpoint: SolanaSDK.APIEndPoint
    private let relayAccountStatus: FeeRelayer.Relay.RelayAccountStatus
    
    init(endpoint: SolanaSDK.APIEndPoint, relayAccountStatus: FeeRelayer.Relay.RelayAccountStatus) {
        self.endpoint = endpoint
        self.relayAccountStatus = relayAccountStatus
    }
    
    func getRelayAccountStatus(_ relayAccountAddress: String) -> Single<FeeRelayer.Relay.RelayAccountStatus> {
        .just(relayAccountStatus)
    }
    
    func getMinimumBalanceForRentExemption(span: UInt64) -> Single<UInt64> {
        if span == 165 {return .just(2039280)}
        if span == 0 {return .just(890880)}
        fatalError()
    }
    
    func getRecentBlockhash(commitment: SolanaSDK.Commitment?) -> Single<String> {
        .just("5RwrqbEus8NFnz8hp4aJg4r1quovPbHJU86ctcupiPfd")
    }
    
    func getLamportsPerSignature() -> Single<UInt64> {
        .just(5000)
    }
    
    func prepareTransaction(instructions: [SolanaSDK.TransactionInstruction], signers: [SolanaSDK.Account], feePayer: SolanaSDK.PublicKey, accountsCreationFee: SolanaSDK.Lamports, recentBlockhash: String?, lamportsPerSignature: SolanaSDK.Lamports?) -> Single<SolanaSDK.PreparedTransaction> {
        fatalError()
    }
    
    func findSPLTokenDestinationAddress(mintAddress: String, destinationAddress: String) -> Single<SolanaSDK.SPLTokenDestinationAddress> {
        fatalError()
    }
    
    func getAccountInfo<T>(account: String, decodedTo: T.Type) -> Single<SolanaSDK.BufferInfo<T>> where T : DecodableBufferLayout {
        fatalError()
    }
}

private class FakeOrcaSwap: OrcaSwapType {
    func load() -> Completable {
        .empty()
    }
    
    func getMint(tokenName: String) -> String? {
        fatalError()
    }
    
    func findPosibleDestinationMints(fromMint: String) throws -> [String] {
        fatalError()
    }
    
    func getTradablePoolsPairs(fromMint: String, toMint: String) -> Single<[OrcaSwap.PoolsPair]> {
        fatalError()
    }
    
    func findBestPoolsPairForInputAmount(_ inputAmount: UInt64, from poolsPairs: [OrcaSwap.PoolsPair]) throws -> OrcaSwap.PoolsPair? {
        fatalError()
    }
    
    func findBestPoolsPairForEstimatedAmount(_ estimatedAmount: UInt64, from poolsPairs: [OrcaSwap.PoolsPair]) throws -> OrcaSwap.PoolsPair? {
        fatalError()
    }
    
    func getLiquidityProviderFee(bestPoolsPair: OrcaSwap.PoolsPair?, inputAmount: Double?, slippage: Double) throws -> [UInt64] {
        fatalError()
    }
    
    func getNetworkFees(myWalletsMints: [String], fromWalletPubkey: String, toWalletPubkey: String?, bestPoolsPair: OrcaSwap.PoolsPair?, inputAmount: Double?, slippage: Double, lamportsPerSignature: UInt64, minRentExempt: UInt64) throws -> Single<SolanaSDK.FeeAmount> {
        fatalError()
    }
    
    func prepareForSwapping(fromWalletPubkey: String, toWalletPubkey: String?, bestPoolsPair: OrcaSwap.PoolsPair, amount: Double, feePayer: OrcaSwap.PublicKey?, slippage: Double) -> Single<([OrcaSwap.PreparedSwapTransaction], String?)> {
        fatalError()
    }
    
    func swap(fromWalletPubkey: String, toWalletPubkey: String?, bestPoolsPair: OrcaSwap.PoolsPair, amount: Double, slippage: Double, isSimulation: Bool) -> Single<OrcaSwap.SwapResponse> {
        fatalError()
    }
}

private class FakeFeeRelayerAPIClient: FeeRelayerAPIClientType {
    let version: Int = 1
    let maxCount: Int
    var count: Int
    
    init(maxCount: Int, count: Int) {
        self.maxCount = maxCount
        self.count = count
    }
    
    func getFeePayerPubkey() -> Single<String> {
        .just("FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT")
    }
    
    func requestFreeFeeLimits(for authority: String) -> Single<FeeRelayer.Relay.FeeLimitForAuthorityResponse> {
        return .just(.init(authority: [], limits: .init(useFreeFee: true, maxAmount: 10000000, maxCount: maxCount, period: .init(secs: 86400, nanos: 0)), processedFee: .init(totalAmount: 0, count: count)))
    }
    
    func sendTransaction(_ requestType: FeeRelayer.RequestType) -> Single<String> {
        .just("")
    }
    
    func sendTransaction<T>(_ requestType: FeeRelayer.RequestType, decodedTo: T.Type) -> Single<T> where T : Decodable {
        fatalError()
    }
}
