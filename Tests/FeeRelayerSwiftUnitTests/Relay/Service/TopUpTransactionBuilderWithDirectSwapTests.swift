import Foundation
import XCTest
@testable import FeeRelayerSwift
import SolanaSwift
@testable import OrcaSwapSwift

final class TopUpTransactionBuilderWithDirectSwapTests: XCTestCase {
    var builder: TopUpTransactionBuilder?
    let topUpPools = [Pool.solUSDC.reversed]
    
    override func setUp() async throws {
        builder = TopUpTransactionBuilderImpl(
            solanaApiClient: MockSolanaAPIClientBase(),
            orcaSwap: MockOrcaSwapBase(),
            account: try await MockAccountStorage().account!
        )
    }
    
    override func tearDown() async throws {
        builder = nil
    }
    
    
    func testTopUpTransactionBuilderWhenFreeTransactionAvailable() async throws {
        let sourceToken = TokenAccount(
            address: .usdcAssociatedAddress,
            mint: .usdcMint
        )
        
        let targetAmount: Lamports = .random(in: 10000..<minimumTokenAccountBalance)
        
        // CASE 1: RelayAccount is not yet created
        let topUpTransactionWhenRelayAccountIsNotYetCreated = try await builder?.buildTopUpTransaction(
            context: getContext(
                relayAccountStatus: .notYetCreated,
                usageStatus: .init(
                    maxUsage: 100,
                    currentUsage: 0,
                    maxAmount: 10000000,
                    amountUsed: 0
                )
            ),
            sourceToken: sourceToken,
            topUpPools: topUpPools,
            targetAmount: targetAmount,
            blockhash: blockhash
        )
        XCTAssertEqual(
            topUpTransactionWhenRelayAccountIsNotYetCreated?.preparedTransaction.expectedFee.total,
            minimumRelayAccountBalance + minimumTokenAccountBalance
        )
        
//        builder?.buildTopUpTransaction(
//            context: getContext(
//                relayAccountStatus: .notYetCreated,
//                usageStatus: .init(
//                    maxUsage: 100,
//                    currentUsage: 0,
//                    maxAmount: 100000000,
//                    amountUsed: 0
//                )
//            ),
//            sourceToken: sourceToken,
//            topUpPools: topUpPools,
//            targetAmount: targetAmount,
//            blockhash: blockhash
//        )
    }
    
    // MARK: - Helpers

    private func getContext(
        relayAccountStatus: RelayAccountStatus,
        usageStatus: UsageStatus
    ) -> RelayContext {
        .init(
            minimumTokenAccountBalance: minimumTokenAccountBalance,
            minimumRelayAccountBalance: minimumRelayAccountBalance,
            feePayerAddress: .feePayerAddress,
            lamportsPerSignature: lamportsPerSignature,
            relayAccountStatus: relayAccountStatus,
            usageStatus: usageStatus
        )
    }
}
