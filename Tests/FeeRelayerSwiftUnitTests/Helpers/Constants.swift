import SolanaSwift

let minimumTokenAccountBalance: UInt64 = 2039280
let minimumRelayAccountBalance: UInt64 = 890880
let lamportsPerSignature: UInt64 = 5000


extension PublicKey {
    static var feePayerAddress: PublicKey {
        "FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT"
    }
    
    static var usdtMint: PublicKey {
        "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
    }
}
