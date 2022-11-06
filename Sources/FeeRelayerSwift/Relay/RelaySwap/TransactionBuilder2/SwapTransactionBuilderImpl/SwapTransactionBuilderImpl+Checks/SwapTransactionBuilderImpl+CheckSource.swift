import Foundation
import SolanaSwift
import OrcaSwapSwift

extension SwapTransactionBuilderImpl {
    func checkSource(
        owner: PublicKey,
        sourceMint: PublicKey,
        inputAmount: UInt64,
        output: inout SwapTransactionBuilderOutput
    ) async throws {
        let relayContext = try await relayContextManager.getCurrentContext()
        let feePayer = relayContext.feePayerAddress
        let minimumTokenAccountBalance = relayContext.minimumTokenAccountBalance
        
        var sourceWSOLNewAccount: Account?
        
        // Check if source token is NATIVE SOL
        // Treat SPL SOL like another SPL Token (WSOL new account is not needed)
        
        if sourceMint == PublicKey.wrappedSOLMint &&
           (output.userSource == nil || output.userSource == owner) // check for native sol
        {
            sourceWSOLNewAccount = try await Account(network: solanaAPIClient.endpoint.network)
            output.instructions.append(contentsOf: [
                SystemProgram.transferInstruction(
                    from: owner,
                    to: feePayer,
                    lamports: inputAmount
                ),
                SystemProgram.createAccountInstruction(
                    from: feePayer,
                    toNewPubkey: sourceWSOLNewAccount!.publicKey,
                    lamports: minimumTokenAccountBalance + inputAmount,
                    space: AccountInfo.BUFFER_LENGTH,
                    programId: TokenProgram.id
                ),
                TokenProgram.initializeAccountInstruction(
                    account: sourceWSOLNewAccount!.publicKey,
                    mint: .wrappedSOLMint,
                    owner: owner
                ),
            ])
            output.userSource = sourceWSOLNewAccount!.publicKey
            output.additionalPaybackFee += minimumTokenAccountBalance
        }
        
        output.sourceWSOLNewAccount = sourceWSOLNewAccount
    }
}
