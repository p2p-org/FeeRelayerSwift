//
//  FeeRelayer.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 16/07/2021.
//

import Foundation
import RxSwift
import RxAlamofire

public protocol FeeRelayerError: Error {
    static func createInvalidResponseError(code: Int, message: String) -> Self
}

public struct FeeRelayer {
    // MARK: - Constants
    static let feeRelayerUrl = "https://fee-relayer.solana.p2p.org"
    
    // MARK: - Properties
    private let errorType: FeeRelayerError.Type
    
    // MARK: - Initializer
    public init(errorType: FeeRelayerError.Type)
    {
        self.errorType = errorType
    }
    
    // MARK: - Methods
    /// Get fee payer for free transaction
    /// - Returns: Account's public key that is responsible for paying fee
    public func getFeePayerPubkey() -> Single<String>
    {
        request(.get, "\(FeeRelayer.feeRelayerUrl)/fee_payer/pubkey")
            .responseString()
            .map { (response, string) in
                // Print
                guard (200..<300).contains(response.statusCode) else {
                    let readableError = string.slice(from: "(", to: ")") ?? string
                    throw errorType.createInvalidResponseError(code: response.statusCode, message: readableError)
                }
                return string
            }
            .take(1)
            .asSingle()
    }
    
    /// Send transaction to fee relayer
    /// - Parameters:
    ///   - path: additional path for request
    ///   - params: request's parameters
    /// - Returns: transaction id
    public func sendTransaction(
        _ requestType: RequestType
    ) -> Single<String> {
        do {
            var urlRequest = try URLRequest(
                url: requestType.url,
                method: .post,
                headers: ["Content-Type": "application/json"]
            )
            urlRequest.httpBody = try requestType.getParams()
            
            return RxAlamofire.request(urlRequest)
                .responseString()
                .map { (response, string) in
                    // Print
                    guard (200..<300).contains(response.statusCode) else {
                        debugPrint(string)
                        throw errorType.createInvalidResponseError(code: response.statusCode, message: string)
                    }
                    return string
                }
                .take(1)
                .asSingle()
        } catch {
            return .error(error)
        }
    }
}

private extension String {
    func slice(from: String, to: String) -> String? {
        guard let rangeFrom = range(of: from)?.upperBound else { return nil }
        guard let rangeTo = self[rangeFrom...].range(of: to)?.lowerBound else { return nil }
        return String(self[rangeFrom..<rangeTo])
    }
}
