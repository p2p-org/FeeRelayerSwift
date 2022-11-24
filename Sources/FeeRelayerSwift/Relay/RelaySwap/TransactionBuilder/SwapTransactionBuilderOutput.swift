import Foundation
import OrcaSwapSwift
import SolanaSwift

struct SwapTransactionBuilderOutput {
    var userSource: PublicKey? = nil
    var sourceWSOLNewAccount: Account? = nil
    
    var transitTokenMintPubkey: PublicKey?
    var transitTokenAccountAddress: PublicKey?
    var needsCreateTransitTokenAccount: Bool?

    var destinationNewAccount: Account? = nil
    var userDestinationTokenAccountAddress: PublicKey? = nil

    var instructions = [TransactionInstruction]()
    var additionalTransaction: PreparedTransaction? = nil

    var signers: [Account] = []

    // Building fee
    var accountCreationFee: Lamports = 0
    var additionalPaybackFee: UInt64 = 0
}
