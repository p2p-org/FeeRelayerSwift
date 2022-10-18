import Foundation
import XCTest
import OrcaSwapSwift
import SolanaSwift
@testable import FeeRelayerSwift

class RelayFeeCalculatorWithoutFreeTransactionTests: XCTestCase {
    
    let calculator = DefaultFreeRelayerCalculator()
    
    func testWhenRelayAccountHasAlreadyBeenCreated() async throws {
        // TO KEEP RELAY ACCOUNT ALIVE, WE MUST ALWAYS KEEPS minimumRelayAccountBalance (890880 LAMPORTS AT THE MOMENT) IN THIS ACCOUNT
        // AFTER ANY TRANSACTION
        
        let expectedTxFee = FeeAmount(
            transaction: UInt64.random(in: 1...2) * lamportsPerSignature,
            accountBalances: UInt64.random(in: 1...2) * minimumTokenAccountBalance
        )

        var currentRelayAccountBalance: UInt64 = 0
        let topUpFee = 2 * lamportsPerSignature

        // CASE 1: currentRelayAccountBalance is less than minimumRelayAccountBalance,
        // we must top up some lamports to compensate and keep it alive after transaction

        currentRelayAccountBalance = UInt64.random(in: 0..<minimumRelayAccountBalance)

        let case1 = try await calculator.calculateNeededTopUpAmount(
            getContext(
                relayAccountStatus: .created(balance: currentRelayAccountBalance),
                exceededFreeTransactionLimit: true
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .usdtMint
        )

        XCTAssertEqual(
            case1,
            FeeAmount(
                transaction: minimumRelayAccountBalance
                    - currentRelayAccountBalance
                    + expectedTxFee.transaction
                    + topUpFee,
                accountBalances: expectedTxFee.accountBalances
            )
        )
        
        // CASE 2: currentRelayAccountBalance is already more than minimumRelayAccountBalance
        // and the amount left can cover part of expected transaction fee and topup fee
        
        currentRelayAccountBalance = minimumRelayAccountBalance

        let totalTransactionFee = expectedTxFee.transaction + topUpFee

        currentRelayAccountBalance += UInt64.random(in: 0..<totalTransactionFee)

        let case2 = try await calculator.calculateNeededTopUpAmount(
            getContext(
                relayAccountStatus: .created(balance: currentRelayAccountBalance),
                exceededFreeTransactionLimit: true
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .usdtMint
        )

        XCTAssertEqual(
            case2,
            FeeAmount(
                transaction: totalTransactionFee - (currentRelayAccountBalance - minimumRelayAccountBalance),
                accountBalances: expectedTxFee.accountBalances
            )
        )
        
        // CASE 3: currentRelayAccountBalance is already more than minimumRelayAccountBalance
        // and the amount left can cover entirely expected transaction fee + top up fee
        // as so as part of account creation fee

        currentRelayAccountBalance = minimumRelayAccountBalance + expectedTxFee.transaction + topUpFee
        currentRelayAccountBalance += UInt64.random(in: 0..<expectedTxFee.accountBalances)

        let case3 = try await calculator.calculateNeededTopUpAmount(
            getContext(
                relayAccountStatus: .created(balance: currentRelayAccountBalance),
                exceededFreeTransactionLimit: true
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .usdtMint
        )

        let amountCovered = currentRelayAccountBalance - minimumRelayAccountBalance - expectedTxFee.transaction - topUpFee

        XCTAssertEqual(
            case3,
            FeeAmount(
                transaction: 0,
                accountBalances: expectedTxFee.accountBalances - amountCovered
            )
        )
        
        // CASE 4: currentRelayAccountBalance is already more than minimumRelayAccountBalance
        // and the amount left can cover entirely expected transaction fee + top up fee + account creation fee

        currentRelayAccountBalance = minimumRelayAccountBalance + expectedTxFee.transaction + topUpFee + expectedTxFee.accountBalances
        currentRelayAccountBalance += UInt64.random(in: 0..<1000)

        let case4 = try await calculator.calculateNeededTopUpAmount(
            getContext(
                relayAccountStatus: .created(balance: currentRelayAccountBalance),
                exceededFreeTransactionLimit: true
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .usdtMint
        )

        XCTAssertEqual(
            case4,
            .zero
        )
    }
    
    func testWhenTopUpAmountIsTooSmall() async throws {
        let expectedTxFee = FeeAmount(
            transaction: UInt64.random(in: 1...2) * lamportsPerSignature,
            accountBalances: UInt64.random(in: 1...2) * minimumTokenAccountBalance
        )
        var currentRelayAccountBalance: UInt64 = 0
        let topUpFee = 2 * lamportsPerSignature
        
        // CASE 1: currentRelayAccountBalance is already more than minimumRelayAccountBalance
        // and the amount left can cover big part of expected account creation fee
        
        currentRelayAccountBalance = minimumRelayAccountBalance + expectedTxFee.transaction + topUpFee + expectedTxFee.accountBalances
        currentRelayAccountBalance -= UInt64.random(in: 0..<1000)
        
        let case3 = try await calculator.calculateNeededTopUpAmount(
            getContext(
                relayAccountStatus: .created(balance: currentRelayAccountBalance),
                exceededFreeTransactionLimit: true
            ),
            expectedFee: expectedTxFee,
            payingTokenMint: .usdtMint
        )
        
        let amountLeft = expectedTxFee.accountBalances - (currentRelayAccountBalance - minimumRelayAccountBalance - expectedTxFee.transaction - topUpFee)
        XCTAssertTrue(amountLeft < 1000)
        
        XCTAssertEqual(case3.total, 1000)
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
