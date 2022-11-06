//
//  File.swift
//  
//
//  Created by Chung Tran on 06/11/2022.
//

import Foundation
import OrcaSwapSwift
import SolanaSwift

struct SwapTransactionBuilderInput {
    let userAccount: Account

    let pools: PoolsPair
    let inputAmount: UInt64
    let slippage: Double

    let sourceTokenAccount: TokenAccount
    let destinationTokenMint: PublicKey
    let destinationTokenAddress: PublicKey?
    
    let blockhash: String
}
