import Foundation
import XCTest
import OrcaSwapSwift
import SolanaSwift
@testable import FeeRelayerSwift

class RelayFeeCalculatorWithFreeTransactionTests: XCTestCase {
    
    let calculator = DefaultRelayFeeCalculator()
    
    func testWhenTransactionIsTotallyFree() async throws {
        let expectedTxFee = FeeAmount(
            transaction: 5000,
            accountBalances: 0
        )
        
        // user is paying with SOL, relay account creation is not needed
        let case1 = try await calculator.calculateNeededTopUpAmount(
            getContextWithFreeTransactionFeesAvailable(
                relayAccountStatus: .notYetCreated // not important
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .usdtMint
        )
        
        XCTAssertEqual(
            case1,
            .zero
        )
    }
    
    func testWhenRelayAccountIsNotYetCreated() async throws {
        let expectedTxFee = FeeAmount(
            transaction: UInt64.random(in: 1...2) * lamportsPerSignature,
            accountBalances: UInt64.random(in: 1...2) * minimumTokenAccountBalance
        )
        
        // user is paying with SOL, relay account creation is not needed
        let case1 = try await calculator.calculateNeededTopUpAmount(
            getContextWithFreeTransactionFeesAvailable(
                relayAccountStatus: .notYetCreated
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
            getContextWithFreeTransactionFeesAvailable(
                relayAccountStatus: .notYetCreated
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .usdtMint
        )
        
        XCTAssertEqual(
            case2,
            FeeAmount(transaction: minimumRelayAccountBalance, accountBalances: expectedTxFee.accountBalances)
        )
    }
    
    func testWhenRelayAccountHasAlreadyBeenCreated() async throws {
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
            getContextWithFreeTransactionFeesAvailable(
                relayAccountStatus: .created(balance: currentRelayAccountBalance)
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
            getContextWithFreeTransactionFeesAvailable(
                relayAccountStatus: .created(balance: currentRelayAccountBalance)
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
            getContextWithFreeTransactionFeesAvailable(
                relayAccountStatus: .created(balance: currentRelayAccountBalance)
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .usdtMint
        )
        
        XCTAssertEqual(
            case3,
            .zero
        )
    }
    
    func testWhenTopUpAmountIsTooSmall() async throws {
        let expectedTxFee = FeeAmount(
            transaction: UInt64.random(in: 1...2) * lamportsPerSignature,
            accountBalances: UInt64.random(in: 1...2) * minimumTokenAccountBalance
        )
        var currentRelayAccountBalance: UInt64 = 0
        
        // CASE 1: currentRelayAccountBalance is already more than minimumRelayAccountBalance
        // and the amount left can cover big part of expected account creation fee
        
        currentRelayAccountBalance = minimumRelayAccountBalance
        currentRelayAccountBalance += expectedTxFee.accountBalances - UInt64.random(in: 0..<1000)
        
        let case3 = try await calculator.calculateNeededTopUpAmount(
            getContextWithFreeTransactionFeesAvailable(
                relayAccountStatus: .created(balance: currentRelayAccountBalance)
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .usdtMint
        )
        
        let amountLeft = expectedTxFee.accountBalances - (currentRelayAccountBalance - minimumRelayAccountBalance)
        XCTAssertTrue(amountLeft < 10000)
        
        XCTAssertEqual(case3.total, 10000)
    }
    
    private func getContextWithFreeTransactionFeesAvailable(
        relayAccountStatus: RelayAccountStatus
    ) -> RelayContext {
        .init(
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            minimumRelayAccountBalance: minimumRelayAccountBalance,
            feePayerAddress: .feePayerAddress,
            lamportsPerSignature: lamportsPerSignature,
            relayAccountStatus: relayAccountStatus,
            usageStatus: .init(
                maxUsage: 10000000,
                currentUsage: 0,
                maxAmount: 10000000,
                amountUsed: 0
            )
        )
    }
}
