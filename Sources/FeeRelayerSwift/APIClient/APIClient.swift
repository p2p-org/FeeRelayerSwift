// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation

public protocol FeeRelayerAPIClient {
    var version: Int { get }
    func getFeePayerPubkey() async throws -> String
    func requestFreeFeeLimits(for authority: String) async throws -> FeeLimitForAuthorityResponse
    func sendTransaction(_ requestType: RequestType) async throws -> String
//    func sendTransaction<T: Decodable>(_ requestType: RequestType) async throws -> T
}

enum APIClientError: Error {
    case invalidURL
    case custom(error: Error)
    case cantDecodeError
    case unknown
}

public class APIClient: FeeRelayerAPIClient {
    
    // MARK: - Properties

    public let version: Int
    private let baseUrlString: String
    private var httpClient: HTTPClient

    // MARK: - Initializers

    public init(httpClient: HTTPClient = FeeRelayerHTTPClient(), baseUrlString: String, version: Int) {
        self.version = version
        self.httpClient = httpClient
        self.baseUrlString = baseUrlString
    }

    // MARK: - Methods

    /// Get fee payer for free transaction
    /// - Returns: Account's public key that is responsible for paying fee
    public func getFeePayerPubkey() async throws -> String {
        var urlString = baseUrlString
        if version > 1 {
            urlString += "/v\(version)"
        }
        urlString += "/fee_payer/pubkey"
        guard let url = URL(string: urlString) else { throw APIClientError.invalidURL }
        let request = URLRequest(url: url)
        var res: String?
        do {
            res = try await httpClient.sendRequest(request: request, decoder: JSONDecoder())
        } catch HTTPClientError.cantDecode(let data) {
            res = String(data: data, encoding: .utf8)
            Logger.log(event: "FeeRelayerSwift getFeePayerPubkey", message: res, logLevel: .debug)
        }
        guard let res = res else { throw APIClientError.unknown }
        return res
    }
    
    public func requestFreeFeeLimits(for authority: String) async throws -> FeeLimitForAuthorityResponse {
        var url = baseUrlString
        if version > 1 {
            url += "/v\(version)"
        }
        url += "/free_fee_limits/\(authority)"
        guard let url = URL(string: url) else { throw APIClientError.unknown }

        var urlRequest: URLRequest
        urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

        Logger.log(event: "FeeRelayerSwift requestFreeFeeLimits", message: urlRequest.cURL(), logLevel: .debug)

        do {
            return try await httpClient.sendRequest(request: urlRequest, decoder: JSONDecoder()) as FeeLimitForAuthorityResponse
        } catch HTTPClientError.unexpectedStatusCode(_, let data) {
            Logger.log(event: "FeeRelayerSwift: requestFreeFeeLimits", message: String(data: data, encoding: .utf8), logLevel: .error)
            let decodedError = try JSONDecoder().decode(FeeRelayerError.self, from: data)
            throw decodedError
        }
    }
    
    /// Send transaction to fee relayer
    /// - Parameters:
    ///   - path: additional path for request
    ///   - params: request's parameters
    /// - Returns: transaction id
    public func sendTransaction(_ requestType: RequestType) async throws -> String {
        do {
            let response: String = try await httpClient.sendRequest(request: urlRequest(requestType), decoder: JSONDecoder())
            return response
        } catch HTTPClientError.cantDecode(let data) {
            guard let ret = String(data: data, encoding: .utf8) else { throw APIClientError.unknown }
            
            let signature = ret.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "").replacingOccurrences(of: "\"", with: "")
            Logger.log(
                event: "FeeRelayerSwift sendTransaction",
                message: "Transaction has been successfully sent with signature: \(signature)",
                logLevel: .debug
            )
            return signature
        }
    }
    
//    public func sendTransaction<T: Decodable>(_ requestType: FeeRelayer.RequestType) async throws -> T {
//        do {
//            return try await httpClient.sendRequest(request: urlRequest(requestType), decoder: JSONDecoder()) as T
//        } catch HTTPClientError.cantDecode(let data) {
//            do {
//                let error = try JSONDecoder().decode(FeeRelayer.Error.self, from: data)
//                throw APIClientError.custom(error: error)
//            } catch {
//                throw APIClientError.cantDecodeError
//            }
//        }
//    }
    
    private func urlRequest(_ requestType: RequestType) throws -> URLRequest {
        var url = baseUrlString
        if version > 1 {
            url += "/v\(version)"
        }
        url += requestType.path
        var urlRequest = URLRequest(url: URL(string: url)!)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try requestType.getParams()

        Logger.log(
            event: "FeeRelayerSwift urlRequest",
            message: urlRequest.cURL(),
            logLevel: .debug
        )
        return urlRequest
    }
}

extension URLRequest {
    fileprivate func cURL(pretty: Bool = false) -> String {
        let newLine = pretty ? "\\\n" : ""
        let method = (pretty ? "--request " : "-X ") + "\(self.httpMethod ?? "GET") \(newLine)"
        let url: String = (pretty ? "--url " : "") + "\'\(self.url?.absoluteString ?? "")\' \(newLine)"

        var cURL = "curl "
        var header = ""
        var data: String = ""

        if let httpHeaders = self.allHTTPHeaderFields, httpHeaders.keys.count > 0 {
            for (key, value) in httpHeaders {
                header += (pretty ? "--header " : "-H ") + "\'\(key): \(value)\' \(newLine)"
            }
        }

        if let bodyData = self.httpBody, let bodyString = String(data: bodyData, encoding: .utf8), !bodyString.isEmpty {
            data = "--data '\(bodyString)'"
        }

        cURL += method + url + header + data

        return cURL
    }
}
