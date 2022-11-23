import Foundation
import OrcaSwapSwift
import SolanaSwift

class SwapTransactionBuilderImpl : SwapTransactionBuilder2 {
    
    let network: Network
    let transitTokenAccountManager: TransitTokenAccountManagerType
    let destinationManager: DestinationFinder
    let orcaSwap: OrcaSwapType
    let feePayerAddress: PublicKey
    let minimumTokenAccountBalance: UInt64
    let lamportsPerSignature: UInt64
    
    init(
        network: Network,
        transitTokenAccountManager: TransitTokenAccountManagerType,
        destinationManager: DestinationFinder,
        orcaSwap: OrcaSwapType,
        feePayerAddress: PublicKey,
        minimumTokenAccountBalance: UInt64,
        lamportsPerSignature: UInt64
    ) {
        self.network = network
        self.transitTokenAccountManager = transitTokenAccountManager
        self.destinationManager = destinationManager
        self.orcaSwap = orcaSwap
        self.feePayerAddress = feePayerAddress
        self.minimumTokenAccountBalance = minimumTokenAccountBalance
        self.lamportsPerSignature = lamportsPerSignature
    }
    
    func prepareSwapTransaction(input: SwapTransactionBuilderInput) async throws -> (transactions: [PreparedTransaction], additionalPaybackFee: UInt64) {
        // form output
        var output = SwapTransactionBuilderOutput()
        output.userSource = input.sourceTokenAccount.address
        
        // assert userSource
        let associatedToken = try PublicKey.associatedTokenAddress(
            walletAddress: feePayerAddress,
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
        try checkSwapData(
            owner: input.userAccount.publicKey,
            poolsPair: input.pools,
            env: &output,
            swapData: swapData
        )
        
        // closing accounts
        try checkClosingAccount(
            owner: input.userAccount.publicKey,
            feePayer: feePayerAddress,
            destinationTokenMint: input.destinationTokenMint,
            minimumTokenAccountBalance: minimumTokenAccountBalance,
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
            try makeTransaction(
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
    ) throws -> PreparedTransaction {
        var transaction = Transaction()
        transaction.instructions = instructions
        transaction.recentBlockhash = blockhash
        transaction.feePayer = feePayerAddress
    
        try transaction.sign(signers: signers)
        
        // calculate fee first
        let expectedFee = FeeAmount(
            transaction: try transaction.calculateTransactionFee(lamportsPerSignatures: lamportsPerSignature),
            accountBalances: accountCreationFee
        )
        
        return .init(transaction: transaction, signers: signers, expectedFee: expectedFee)
    }
}
