import Foundation
import OrcaSwapSwift
import SolanaSwift

/// Interface for a top up transaction builder
public protocol TopUpTransactionBuilder {
    /// Build top up transaction from given data
    /// - Parameters:
    ///   - account: User account
    ///   - context: Relay context
    ///   - network: Solana network
    ///   - sourceToken: fromToken to top up
    ///   - userAuthorityAddress: user's authority address
    ///   - topUpPools: pools using for top up with swap
    ///   - targetAmount: amount for topping up
    ///   - expectedFee: expected top up fee
    ///   - blockhash: recent blockhash
    ///   - needsCreateTransitTokenAccount: indicate if creating transit token is required
    ///   - transitTokenMintPubkey: transit token mint
    ///   - transitTokenAccountAddress: transit token account address
    /// - Returns: swap data to pass to fee relayer api client and prepared top up transaction
    func buildTopUpTransaction(
        account: Account,
        context: RelayContext,
        network: Network,
        sourceToken: TokenAccount,
        topUpPools: PoolsPair,
        targetAmount: UInt64,
        expectedFee: UInt64,
        blockhash: String,
        needsCreateTransitTokenAccount: Bool?,
        transitTokenMintPubkey: PublicKey?,
        transitTokenAccountAddress: PublicKey?
    ) async throws -> (swapData: FeeRelayerRelaySwapType, preparedTransaction: PreparedTransaction)
}
