import Foundation
import OrcaSwapSwift
import SolanaSwift

class SwapTransactionBuilderImpl : SwapTransactionBuilder2 {
    
    let solanaAPIClient: SolanaAPIClient
    let orcaSwap: OrcaSwapType
    let relayContextManager: RelayContextManager
    
    init(
        solanaAPIClient: SolanaAPIClient,
        orcaSwap: OrcaSwapType,
        relayContextManager: RelayContextManager
    ) {
        self.solanaAPIClient = solanaAPIClient
        self.orcaSwap = orcaSwap
        self.relayContextManager = relayContextManager
    }
    
    func prepareSwapTransaction(input: SwapTransactionBuilderInput) async throws -> SwapTransactionBuilderOutput {
        // get context
        let relayContext = try await relayContextManager.getCurrentContext()
        
        // form output
        var output = SwapTransactionBuilderOutput()
        output.userSource = input.sourceTokenAccount.address
        
        // assert userSource
        let associatedToken = try PublicKey.associatedTokenAddress(
            walletAddress: relayContext.feePayerAddress,
            tokenMintAddress: input.sourceTokenAccount.mint
        )
        guard output.userSource != associatedToken else { throw FeeRelayerError.wrongAddress }
        
        // check transit token
        try await checkTransitTokenAccount(
            owner: input.userAccount.publicKey,
            poolsPair: input.pools,
            output: &output
        )
        
        // check source
        try await checkSource(
            owner: input.userAccount.publicKey,
            sourceMint: input.sourceTokenAccount.mint,
            inputAmount: input.inputAmount,
            output: &output
        )
        
        // check destination
        try await checkDestination(
            owner: input.userAccount,
            destinationMint: input.destinationTokenMint,
            destinationAddress: input.destinationTokenAddress,
            recentBlockhash: input.blockhash,
            output: &output
        )
        
//        fatalError()
    }
    
    func makeTransaction(
        instructions: [TransactionInstruction],
        signers: [Account],
        blockhash: String,
        accountCreationFee: UInt64
    ) async throws -> PreparedTransaction {
        let context = try await relayContextManager.getCurrentContext()
        
        var transaction = Transaction()
        transaction.instructions = instructions
        transaction.recentBlockhash = blockhash
        transaction.feePayer = context.feePayerAddress
    
        try transaction.sign(signers: signers)
        
        // calculate fee first
        let expectedFee = FeeAmount(
            transaction: try transaction.calculateTransactionFee(lamportsPerSignatures: context.lamportsPerSignature),
            accountBalances: accountCreationFee
        )
        
        return .init(transaction: transaction, signers: signers, expectedFee: expectedFee)
    }
}
