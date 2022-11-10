import Foundation
import XCTest
@testable import FeeRelayerSwift

final class SwapTransactionBuilderTests: XCTestCase {
    var swapTransactionBuilder: SwapTransactionBuilderImpl!
    
    override func tearDown() async throws {
        swapTransactionBuilder = nil
    }
    
    func testBuildSwapSOLToCreatedSPL() async throws {
//        let output = try await swapTransactionBuilder.prepareSwapTransaction(
//            input: .init(
//                userAccount: <#T##Account#>,
//                pools: <#T##PoolsPair#>,
//                inputAmount: <#T##UInt64#>,
//                slippage: <#T##Double#>,
//                sourceTokenAccount: <#T##TokenAccount#>,
//                destinationTokenMint: <#T##PublicKey#>,
//                destinationTokenAddress: <#T##PublicKey?#>,
//                blockhash: <#T##String#>
//            )
//        )
    }
}
