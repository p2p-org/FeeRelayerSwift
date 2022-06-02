import Foundation
import SolanaSwift
import FeeRelayerSwift
import OrcaSwapSwift
import Cuckoo

func getDataFromJSONTestResourceFile<T: Decodable>(fileName: String, decodedTo type: T.Type) throws -> T {
    let file = try Resource(name: fileName, type: "json")
    let data = try Data(contentsOf: file.url)
    return try JSONDecoder().decode(type, from: data)
}

//func makeFeeRelayerContext(solanaAPIClient: MockFakeJSONRPCAPIClient, feeRelayerAPIClient: MockFakeFeeRelayerAPIClient, accountStorage: SolanaAccountStorage) async throws -> FeeRelayerContext {
//    
//    var fakeFee: Fee = {
//        let fee = "{\"context\":{\"slot\":131770081},\"value\":{\"blockhash\":\"7jvToPQ4ASj3xohjM117tMqmtppQDaWVADZyaLFnytFr\",\"feeCalculator\":{\"lamportsPerSignature\":5000},\"lastValidBlockHeight\":119512694,\"lastValidSlot\":131770381}}".data(using: .utf8)!
//        return try! JSONDecoder().decode(Rpc<Fee>.self, from: fee).value
//    }()
//    
//    var fakeAccountInfo: BufferInfo<EmptyInfo>? = {
//        let fee = "{\"context\":{\"slot\":131421172},\"value\":{\"data\":[\"xvp6877brTo9ZfNqq8l0MbG75MLS9uDkfKYCA0UvXWF9P8kKbTPTsQZqMMzOan8jwyOl0jQaxrCPh8bU1ysTa96DDAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"base64\"],\"executable\":false,\"lamports\":2039280,\"owner\":\"TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA\",\"rentEpoch\":304}}".data(using: .utf8)!
//        return try! JSONDecoder().decode(Rpc<BufferInfo<EmptyInfo>?>.self, from: fee).value
//    }()
//    
//    stub(solanaAPIClient) { stub in
//        when(stub.getMinimumBalanceForRentExemption(dataLength: UInt64(165), commitment: any()))
//            .thenReturn(0)
//        when(stub.getMinimumBalanceForRentExemption(dataLength: UInt64(0), commitment: any()))
//            .thenReturn(0)
//        when(stub.getFees(commitment: any())).thenReturn(fakeFee)
//        when(stub.getAccountInfo(account: any())).thenReturn(fakeAccountInfo)
//    }
//    
//    stub(feeRelayerAPIClient) { stub in
//        when(stub.getFeePayerPubkey()).thenReturn("FG4Y3yX4AAchp1HvNZ7LfzFTewF2f6nDoMDCohTFrdpT")
//        when(stub.requestFreeFeeLimits(for: any())).thenReturn(FeeLimitForAuthorityResponse(authority: [231], limits: .init(useFreeFee: true, maxAmount: 10000000, maxCount: 100, period: .init(secs: 86400, nanos: 0)), processedFee: .init(totalAmount: 0, count: 0)))
//    }
//    
//    let contextManager = FeeRelayerContextManagerImpl(
//        accountStorage: accountStorage,
//        solanaAPIClient: solanaAPIClient,
//        feeRelayerAPIClient: feeRelayerAPIClient
//    )
//    try await contextManager.update()
//    let ctx = try await contextManager.getCurrentContext()
//    return ctx
//}
