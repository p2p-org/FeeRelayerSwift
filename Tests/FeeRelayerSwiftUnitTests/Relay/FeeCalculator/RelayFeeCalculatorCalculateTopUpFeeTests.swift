import Foundation
import XCTest
import OrcaSwapSwift
import SolanaSwift
@testable import FeeRelayerSwift

class RelayFeeCalculatorCalculateTopUpFeeTests: XCTestCase {
    
    let calculator = DefaultRelayFeeCalculator()
    
    func testCalculateExpectedFeeForTopUpWhenFreeTransactionAvailable() throws {
        let expectedFeeForTopUpWhenRelayAccountIsNotYetCreated = try calculator.calculateExpectedFeeForTopUp(
            .init(
                minimumTokenAccountBalance: minimumTokenAccountBalance,
                minimumRelayAccountBalance: minimumRelayAccountBalance,
                feePayerAddress: .feePayerAddress,
                lamportsPerSignature: lamportsPerSignature,
                relayAccountStatus: .notYetCreated, // relay account has not been created
                usageStatus: .init( // free transaction available
                    maxUsage: 10000000,
                    currentUsage: 0,
                    maxAmount: 10000000,
                    amountUsed: 0
                )
            )
        )
        XCTAssertEqual(expectedFeeForTopUpWhenRelayAccountIsNotYetCreated, minimumRelayAccountBalance + minimumTokenAccountBalance)
        
        let expectedFeeForTopUpWhenRelayAccountIsCreated = try calculator.calculateExpectedFeeForTopUp(
            .init(
                minimumTokenAccountBalance: minimumTokenAccountBalance,
                minimumRelayAccountBalance: minimumRelayAccountBalance,
                feePayerAddress: .feePayerAddress,
                lamportsPerSignature: lamportsPerSignature,
                relayAccountStatus: .created(balance: 890880), // relay account has been created
                usageStatus: .init( // free transaction available
                    maxUsage: 10000000,
                    currentUsage: 0,
                    maxAmount: 10000000,
                    amountUsed: 0
                )
            )
        )
        XCTAssertEqual(expectedFeeForTopUpWhenRelayAccountIsCreated, minimumTokenAccountBalance)
    }
    
    func testCalculateExpectedFeeForTopUpWhenFreeTransactionNotAvailable() throws {
        let expectedFeeForTopUpWhenRelayAccountIsNotYetCreated = try calculator.calculateExpectedFeeForTopUp(
            .init(
                minimumTokenAccountBalance: minimumTokenAccountBalance,
                minimumRelayAccountBalance: minimumRelayAccountBalance,
                feePayerAddress: .feePayerAddress,
                lamportsPerSignature: lamportsPerSignature,
                relayAccountStatus: .notYetCreated, // relay account has not been created
                usageStatus: .init( // free transaction is not available
                    maxUsage: 100,
                    currentUsage: 100,
                    maxAmount: 10000000,
                    amountUsed: 0
                )
            )
        )
        XCTAssertEqual(
            expectedFeeForTopUpWhenRelayAccountIsNotYetCreated,
            lamportsPerSignature * 2 +
            minimumRelayAccountBalance + minimumTokenAccountBalance
        )
        
        let expectedFeeForTopUpWhenRelayAccountIsCreated = try calculator.calculateExpectedFeeForTopUp(
            .init(
                minimumTokenAccountBalance: minimumTokenAccountBalance,
                minimumRelayAccountBalance: minimumRelayAccountBalance,
                feePayerAddress: .feePayerAddress,
                lamportsPerSignature: lamportsPerSignature,
                relayAccountStatus: .created(balance: 890880), // relay account has been created
                usageStatus: .init( // free transaction is not available
                    maxUsage: 100,
                    currentUsage: 100,
                    maxAmount: 10000000,
                    amountUsed: 0
                )
            )
        )
        XCTAssertEqual(
            expectedFeeForTopUpWhenRelayAccountIsCreated,
            lamportsPerSignature * 2 +
            minimumTokenAccountBalance
        )
    }
}
