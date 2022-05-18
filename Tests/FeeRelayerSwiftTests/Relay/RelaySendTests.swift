//
//  File.swift
//  
//
//  Created by Chung Tran on 16/02/2022.
//

import XCTest
import RxBlocking
import SolanaSwift
@testable import FeeRelayerSwift
import RxSwift
import OrcaSwapSwift

class RelaySendTests: RelayTests {
    func testRelaySendNativeSOL() throws {
        try runRelaySendNativeSOL(testsInfo.relaySendNativeSOL!)
    }
    
    func testUSDTTransfer() throws {
        try runRelaySendSPLToken(testsInfo.usdtTransfer!)
    }
    
    func testUSDTBackTransfer() throws {
        try runRelaySendSPLToken(testsInfo.usdtBackTransfer!)
    }
    
    func testUSDTTransferToNonCreatedToken() throws {
        try runRelaySendSPLToken(testsInfo.usdtTransferToNonCreatedToken!)
    }
    
    // MARK: - Helpers
    private func runRelaySendNativeSOL(_ test: RelayTransferNativeSOLTestInfo) throws {
        let feeRelayerAPIClient = try loadTest(test)
        
        let payingToken = FeeRelayer.Relay.TokenInfo(
            address: test.payingTokenAddress,
            mint: test.payingTokenMint
        )
        
        let feePayer = try feeRelayerAPIClient.getFeePayerPubkey().toBlocking().first()!
        
        let preparedTransaction = try solanaClient.prepareSendingNativeSOL(
            to: test.destination,
            amount: test.inputAmount,
            feePayer: try SolanaSDK.PublicKey(string: feePayer)
        ).toBlocking().first()!
        
        XCTAssertEqual(preparedTransaction.expectedFee.total, test.expectedFee)
        
        let signature = try relayService.topUpAndRelayTransaction(
            preparedTransaction: preparedTransaction,
            payingFeeToken: payingToken,
            statsInfo: .init(
                operationType: .transfer,
                deviceType: .iOS,
                currency: "SOL",
                build: "1.0.0(1234)"
            )
        ).toBlocking().first()
        print(signature ?? "Nothing")
    }
    
    private func runRelaySendSPLToken(_ test: RelayTransferTestInfo) throws {
        let feeRelayerAPIClient = try loadTest(test)
        
        let payingToken = FeeRelayer.Relay.TokenInfo(
            address: test.payingTokenAddress,
            mint: test.payingTokenMint
        )
        
        let feePayer = try feeRelayerAPIClient.getFeePayerPubkey().toBlocking().first()!
        
        let preparedTransaction = try solanaClient.prepareSendingSPLTokens(
            mintAddress: test.mint,
            decimals: 6,
            from: test.sourceTokenAddress,
            to: test.destinationAddress,
            amount: 100,
            feePayer: try SolanaSDK.PublicKey(string: feePayer),
            transferChecked: true
        ).toBlocking().first()!.preparedTransaction
        
        XCTAssertEqual(preparedTransaction.expectedFee.total, test.expectedFee)
        
        let signature = try relayService.topUpAndRelayTransaction(
            preparedTransaction: preparedTransaction,
            payingFeeToken: payingToken,
            statsInfo: .init(
                operationType: .transfer,
                deviceType: .iOS,
                currency: test.mint,
                build: "1.0.0(1234)"
            )
        ).toBlocking().first()
        print(signature ?? "Nothing")
    }
}
