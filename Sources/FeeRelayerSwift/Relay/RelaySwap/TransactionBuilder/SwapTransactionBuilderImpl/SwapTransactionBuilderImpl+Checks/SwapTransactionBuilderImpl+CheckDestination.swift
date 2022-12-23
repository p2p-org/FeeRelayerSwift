import Foundation
import SolanaSwift
import OrcaSwapSwift

extension SwapTransactionBuilderImpl {
    func checkDestination(
        owner: Account,
        destinationMint: PublicKey,
        destinationAddress: PublicKey?,
        recentBlockhash: String,
        output: inout SwapTransactionBuilderOutput
    ) async throws {
        var destinationNewAccount: Account?
        
        let destinationInfo = try await destinationManager.findRealDestination(
            owner: owner.publicKey,
            mint: destinationMint,
            givenDestination: destinationAddress
        )
        
        var userDestinationTokenAccountAddress = destinationInfo.destination.address
        
        if destinationInfo.needsCreation {
            if destinationInfo.destination.mint == .wrappedSOLMint {
                // For native solana, create and initialize WSOL
                destinationNewAccount = try await Account(network: network)
                output.instructions.append(contentsOf: [
                    SystemProgram.createAccountInstruction(
                        from: feePayerAddress,
                        toNewPubkey: destinationNewAccount!.publicKey,
                        lamports: minimumTokenAccountBalance,
                        space: AccountInfo.BUFFER_LENGTH,
                        programId: TokenProgram.id
                    ),
                    TokenProgram.initializeAccountInstruction(
                        account: destinationNewAccount!.publicKey,
                        mint:  destinationInfo.destination.mint,
                        owner: owner.publicKey
                    ),
                ])
                userDestinationTokenAccountAddress = destinationNewAccount!.publicKey
                output.accountCreationFee += minimumTokenAccountBalance
            } else {
                // For other token, create associated token address
                let associatedAddress = try PublicKey.associatedTokenAddress(
                    walletAddress: owner.publicKey,
                    tokenMintAddress:  destinationInfo.destination.mint
                )

                let instruction = try AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
                    mint:  destinationInfo.destination.mint,
                    owner: owner.publicKey,
                    payer: feePayerAddress
                )

                // SPECIAL CASE WHEN WE SWAP FROM SOL TO NON-CREATED SPL TOKEN, THEN WE NEEDS ADDITIONAL TRANSACTION BECAUSE TRANSACTION IS TOO LARGE
                if output.sourceWSOLNewAccount != nil {
                    output.additionalTransaction = try makeTransaction(
                        instructions: [instruction],
                        signers: [owner],
                        blockhash: recentBlockhash,
                        accountCreationFee: minimumTokenAccountBalance
                    )
                } else {
                    output.instructions.append(instruction)
                    output.accountCreationFee += minimumTokenAccountBalance
                }
                userDestinationTokenAccountAddress = associatedAddress
            }
        }
        
        output.destinationNewAccount = destinationNewAccount
        output.userDestinationTokenAccountAddress = userDestinationTokenAccountAddress
    }
}
