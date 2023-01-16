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
        
        let targetAmount: Lamports = minimumTokenAccountBalance
        
        // CASE 1: RelayAccount is not yet created
        let transaction1 = try await builder?.buildTopUpTransaction(
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
        
        // swap data
        let transaction1SwapData = transaction1?.swapData as! DirectSwapData
        XCTAssertEqual(
            transaction1SwapData,
            .init(
                programId: "DjVE6JNiYqPL2QXyCUUh8rNjHrbz9hXHNYt99MQ59qw1",
                accountPubkey: topUpPools[0].account,
                authorityPubkey: topUpPools[0].authority,
                transferAuthorityPubkey: PublicKey.owner.base58EncodedString,
                sourcePubkey: topUpPools[0].tokenAccountA,
                destinationPubkey: topUpPools[0].tokenAccountB,
                poolTokenMintPubkey: topUpPools[0].poolTokenMint,
                poolFeeAccountPubkey: topUpPools[0].feeAccount,
                amountIn: 48891,
                minimumAmountOut: 2039280
            )
        )
        
        // prepared transaction
        XCTAssertEqual(
            transaction1?.preparedTransaction.expectedFee.total,
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
