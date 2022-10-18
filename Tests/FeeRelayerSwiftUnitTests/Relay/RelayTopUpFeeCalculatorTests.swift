import Foundation
import XCTest
import OrcaSwapSwift
import SolanaSwift
@testable import FeeRelayerSwift

class RelayTopUpFeeCalculatorTests: XCTestCase {
    
    let calculator = DefaultFreeRelayerCalculator()
    
    // MARK: - TopUp
    func testCalculateNeededTopUpAmountWhenRelayAccountIsNotYetCreated() async throws {
        let expectedTxFee = FeeAmount(
            transaction: UInt64.random(in: 1...2) * lamportsPerSignature,
            accountBalances: UInt64.random(in: 1...2) * minimumTokenAccountBalance
        )
        
        // user is paying with SOL, relay account creation is not needed
        let case1 = try await calculator.calculateNeededTopUpAmount(
            getContext(
                relayAccountStatus: .notYetCreated,
                exceededFreeTransactionLimit: false // always false when relay account is not yet created
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .wrappedSOLMint
        )
        
        XCTAssertEqual(
            case1,
            FeeAmount(transaction: 0, accountBalances: expectedTxFee.accountBalances)
        )
        
        // user is paying with another token, relay account creation is required
        let case2 = try await calculator.calculateNeededTopUpAmount(
            getContext(
                relayAccountStatus: .notYetCreated,
                exceededFreeTransactionLimit: false // always false when relay account is not yet created
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .usdtMint
        )
        
        XCTAssertEqual(
            case2,
            FeeAmount(transaction: minimumRelayAccountBalance, accountBalances: expectedTxFee.accountBalances)
        )
    }
    
    func testFeeCalculatorWhenRelayAccountHasAlreadyBeenCreated() async throws {
        // TO KEEP RELAY ACCOUNT ALIVE, WE MUST ALWAYS KEEPS minimumRelayAccountBalance (890880 LAMPORTS AT THE MOMENT) IN THIS ACCOUNT
        // AFTER ANY TRANSACTION
        
        let expectedTxFee = FeeAmount(
            transaction: UInt64.random(in: 1...2) * lamportsPerSignature,
            accountBalances: UInt64.random(in: 1...2) * minimumTokenAccountBalance
        )
        
        var currentRelayAccountBalance: UInt64 = 0
        
        // CASE 1: currentRelayAccountBalance is less than minimumRelayAccountBalance,
        // we must top up some lamports to compensate and keep it alive after transaction
        
        currentRelayAccountBalance = UInt64.random(in: 0..<minimumRelayAccountBalance)
        
        let case1 = try await calculator.calculateNeededTopUpAmount(
            getContext(
                relayAccountStatus: .created(balance: currentRelayAccountBalance),
                exceededFreeTransactionLimit: false
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .usdtMint
        )
        
        XCTAssertEqual(
            case1,
            FeeAmount(
                transaction: minimumRelayAccountBalance - currentRelayAccountBalance, // the transaction fee is free, but we needs to top up additional amount to keeps relay account alive
                accountBalances: expectedTxFee.accountBalances
            )
        )
        
        // CASE 2: currentRelayAccountBalance is already more than minimumRelayAccountBalance
        // and the amount left can cover part of expected account creation fee
        
        currentRelayAccountBalance = minimumRelayAccountBalance
        currentRelayAccountBalance += UInt64.random(in: 0..<expectedTxFee.accountBalances)
        
        let case2 = try await calculator.calculateNeededTopUpAmount(
            getContext(
                relayAccountStatus: .created(balance: currentRelayAccountBalance),
                exceededFreeTransactionLimit: false
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .usdtMint
        )
        
        let amountLeftAfterFillingMinimumRelayAccountBalance = currentRelayAccountBalance - minimumRelayAccountBalance
        
        XCTAssertEqual(
            case2,
            FeeAmount(
                transaction: 0, // the transaction fee is free, but we needs to top up additional amount to keeps relay account alive
                accountBalances: expectedTxFee.accountBalances - amountLeftAfterFillingMinimumRelayAccountBalance
            )
        )
        
        // CASE 3: currentRelayAccountBalance is already more than minimumRelayAccountBalance
        // and the amount left can cover entirely expected account creation fee
        
        currentRelayAccountBalance = minimumRelayAccountBalance + expectedTxFee.accountBalances
        currentRelayAccountBalance += UInt64.random(in: 0..<1000)
        
        let case3 = try await calculator.calculateNeededTopUpAmount(
            getContext(
                relayAccountStatus: .created(balance: currentRelayAccountBalance),
                exceededFreeTransactionLimit: false
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .usdtMint
        )
        
        XCTAssertEqual(
            case3,
            .zero
        )
    }
    
    func testFeeCalculatorWhenTopUpAmountIsTooSmall() throws {
        
    }
    
    private func getContext(
        relayAccountStatus: RelayAccountStatus,
        exceededFreeTransactionLimit: Bool
    ) -> FeeRelayerContext {
        FeeRelayerContext(
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            minimumRelayAccountBalance: minimumRelayAccountBalance,
            feePayerAddress: .feePayerAddress,
            lamportsPerSignature: lamportsPerSignature,
            relayAccountStatus: relayAccountStatus,
            usageStatus: .init(
                maxUsage: 10000000,
                currentUsage: exceededFreeTransactionLimit ? 10000000: 0,
                maxAmount: 10000000,
                amountUsed: 0
            )
        )
    }
}



//    var service: FeeRelayerService!
//
//    override func setUp() async throws {
//        service = .init(
//            orcaSwap: MockOrcaSwap(),
//            accountStorage: try await MockAccountStorage(),
//            solanaApiClient: MockSolanaAPIClient(),
//            feeRelayerAPIClient: MockFeeRelayerAPIClient(),
//            deviceType: .iOS,
//            buildNumber: "1.0.0"
//        )
//    }
//
//    override func tearDown() async throws {
//        service = nil
//    }

//        let freeTransactionFeeLimit = FeeLimitForAuthorityResponse(
//            authority: [],
//            limits: .init(
//                useFreeFee: true,
//                maxAmount: 10000000,
//                maxCount: 100,
//                period: .init(secs: 86400, nanos: 0)
//            ),
//            processedFee: .init(
//                totalAmount: 20000,
//                count: 2
//            )
//        )

private class MockOrcaSwap: MockOrcaSwapBase {
    
}

private class MockAccountStorage: SolanaAccountStorage {
    let account: SolanaSwift.Account?
    
    init() async throws {
        account = try await Account(
            phrase: "miracle pizza supply useful steak border same again youth silver access hundred".components(separatedBy: " "),
            network: .mainnetBeta
        )
    }
    
    func save(_ account: SolanaSwift.Account) throws {}
}

private class MockSolanaAPIClient: MockSolanaAPIClientBase {
    
}

private class MockFeeRelayerAPIClient: MockFeeRelayerAPIClientBase {
    
}
