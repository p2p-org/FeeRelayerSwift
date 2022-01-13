//
//  FeeRelayer.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 16/07/2021.
//

import Foundation
import RxSwift
import RxAlamofire
import Alamofire

public protocol FeeRelayerAPIClientType {
    func getFeePayerPubkey(version: Int) -> Single<String>
    func sendTransaction(
        _ requestType: FeeRelayer.RequestType,
        version: Int
    ) -> Single<String>
    func sendTransaction<T: Decodable>(
        _ requestType: FeeRelayer.RequestType,
        version: Int,
        decodedTo: T.Type
    ) -> Single<T>
}


extension FeeRelayer {
    public struct APIClient: FeeRelayerAPIClientType {
        // MARK: - Initializers
        public init() {}
        
        // MARK: - Methods
        /// Get fee payer for free transaction
        /// - Returns: Account's public key that is responsible for paying fee
        public func getFeePayerPubkey(version: Int) -> Single<String>
        {
            var url = FeeRelayer.feeRelayerUrl
            if version > 1 {
                url += "/v\(version)"
            }
            url += "/fee_payer/pubkey"
            return request(.get, url)
                .responseStringCatchFeeRelayerError()
        }
        
        /// Send transaction to fee relayer
        /// - Parameters:
        ///   - path: additional path for request
        ///   - params: request's parameters
        /// - Returns: transaction id
        public func sendTransaction(
            _ requestType: RequestType,
            version: Int
        ) -> Single<String> {
            do {
                let url = FeeRelayer.feeRelayerUrl + "/v\(version)" + requestType.path
                var urlRequest = try URLRequest(
                    url: url,
                    method: .post,
                    headers: ["Content-Type": "application/json"]
                )
                urlRequest.httpBody = try requestType.getParams()
                
                return request(urlRequest)
                    .responseStringCatchFeeRelayerError()
            } catch {
                return .error(error)
            }
        }
        
        public func sendTransaction<T: Decodable>(
            _ requestType: RequestType,
            version: Int,
            decodedTo: T.Type
        ) -> Single<T> {
            do {
                let url = FeeRelayer.feeRelayerUrl + "/v\(version)" + requestType.path
                var urlRequest = try URLRequest(
                    url: url,
                    method: .post,
                    headers: ["Content-Type": "application/json"]
                )
                urlRequest.httpBody = try requestType.getParams()
                
                return request(urlRequest)
                    .responseData()
                    .take(1)
                    .asSingle()
                    .map { response, data -> T in
                        // Print
                        guard (200..<300).contains(response.statusCode) else {
                            debugPrint(String(data: data, encoding: .utf8) ?? "")
                            let decodedError = try JSONDecoder().decode(FeeRelayer.Error.self, from: data)
                            throw decodedError
                        }
                        return try JSONDecoder().decode(T.self, from: data)
                    }
            } catch {
                return .error(error)
            }
        }
    }
}

private extension ObservableType where Element == DataRequest {
    func responseStringCatchFeeRelayerError(encoding: String.Encoding? = nil) -> Single<String> {
        responseString(encoding: encoding)
            .take(1)
            .asSingle()
            .map { (response, string) in
                // Print
                guard (200..<300).contains(response.statusCode) else {
                    debugPrint(string)
                    guard let data = string.data(using: .utf8) else {
                        throw FeeRelayer.Error.unknown
                    }
                    let decodedError = try JSONDecoder().decode(FeeRelayer.Error.self, from: data)
                    throw decodedError
                }
                return string.replacingOccurrences(of: "[", with: "")
                    .replacingOccurrences(of: "]", with: "")
            }
    }
}
