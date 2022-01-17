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
    var version: Int {get}
    func getFeePayerPubkey() -> Single<String>
    func sendTransaction(_ requestType: FeeRelayer.RequestType) -> Single<String>
    func sendTransaction<T: Decodable>(_ requestType: FeeRelayer.RequestType, decodedTo: T.Type) -> Single<T>
}


extension FeeRelayer {
    public struct APIClient: FeeRelayerAPIClientType {
        // MARK: - Properties
        public  let version: Int
        
        // MARK: - Initializers
        public init(version: Int) {
            self.version = version
        }
        
        // MARK: - Methods
        /// Get fee payer for free transaction
        /// - Returns: Account's public key that is responsible for paying fee
        public func getFeePayerPubkey() -> Single<String>
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
        public func sendTransaction(_ requestType: RequestType) -> Single<String> {
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
            decodedTo: T.Type
        ) -> Single<T> {
            do {
                var url = FeeRelayer.feeRelayerUrl
                if version > 1 {
                    url += "/v\(version)"
                }
                url += requestType.path
                var urlRequest = try URLRequest(
                    url: url,
                    method: .post,
                    headers: ["Content-Type": "application/json"]
                )
                urlRequest.httpBody = try requestType.getParams()
                
                #if DEBUG
                print(NSString(string: urlRequest.cURL()))
                #endif
                
                return request(urlRequest)
                    .responseData()
                    .take(1)
                    .asSingle()
                    .map { response, data -> T in
                        // Print
                        guard (200..<300).contains(response.statusCode) else {
                            #if DEBUG
                            let rawString = String(data: data, encoding: .utf8) ?? ""
                            print(NSString(string: rawString))
                            #endif
                            
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

private extension URLRequest {
    func cURL(pretty: Bool = false) -> String {
        let newLine = pretty ? "\\\n" : ""
        let method = (pretty ? "--request " : "-X ") + "\(self.httpMethod ?? "GET") \(newLine)"
        let url: String = (pretty ? "--url " : "") + "\'\(self.url?.absoluteString ?? "")\' \(newLine)"
        
        var cURL = "curl "
        var header = ""
        var data: String = ""
        
        if let httpHeaders = self.allHTTPHeaderFields, httpHeaders.keys.count > 0 {
            for (key,value) in httpHeaders {
                header += (pretty ? "--header " : "-H ") + "\'\(key): \(value)\' \(newLine)"
            }
        }
        
        if let bodyData = self.httpBody, let bodyString = String(data: bodyData, encoding: .utf8),  !bodyString.isEmpty {
            data = "--data '\(bodyString)'"
        }
        
        cURL += method + url + header + data
        
        return cURL
    }
}
