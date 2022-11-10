import Foundation
import OrcaSwapSwift
import SolanaSwift


protocol SwapTransactionBuilder2 {
    func prepareSwapTransaction(input: SwapTransactionBuilderInput) async throws -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64)
}
