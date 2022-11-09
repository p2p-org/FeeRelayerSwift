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
    
    func prepareSwapTransaction(input: SwapTransactionBuilderInput) async throws -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
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
        
        // build swap data
        let swapData = try await buildSwapData(
            userAccount: input.userAccount,
            pools: input.pools,
            inputAmount: input.inputAmount,
            minAmountOut: nil,
            slippage: input.slippage,
            transitTokenMintPubkey: output.transitTokenMintPubkey,
            needsCreateTransitTokenAccount: output.needsCreateTransitTokenAccount == true
        )
        
        // check swap data
        try await checkSwapData(
            owner: input.userAccount.publicKey,
            poolsPair: input.pools,
            env: &output,
            swapData: swapData
        )
        
        // closing accounts
        try checkClosingAccount(
            owner: input.userAccount.publicKey,
            feePayer: relayContext.feePayerAddress,
            destinationTokenMint: input.destinationTokenMint,
            minimumTokenAccountBalance: relayContext.minimumTokenAccountBalance,
            env: &output
        )
        
        // check signers
        checkSigners(
            ownerAccount: input.userAccount,
            env: &output
        )
        
        var transactions: [PreparedTransaction] = []
        
        // include additional transaciton
        if let additionalTransaction = output.additionalTransaction { transactions.append(additionalTransaction) }
        
        // make primary transaction
        transactions.append(
            try await makeTransaction(
                instructions: output.instructions,
                signers: output.signers,
                blockhash: input.blockhash,
                accountCreationFee: output.accountCreationFee
            )
        )
        
        return (transactions: transactions, additionalPaybackFee: output.additionalPaybackFee)
        
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
