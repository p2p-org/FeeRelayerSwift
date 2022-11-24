import Foundation
import OrcaSwapSwift
import SolanaSwift

public protocol SwapTransactionBuilder {
    func prepareSwapTransaction(input: SwapTransactionBuilderInput) async throws -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64)
}
