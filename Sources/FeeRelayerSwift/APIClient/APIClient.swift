// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation

public protocol FeeRelayerAPIClient {
    var version: Int { get }
    func getFeePayerPubkey() async throws -> String
    func requestFreeFeeLimits(for authority: String) async throws -> FeeRelayer.Relay.FeeLimitForAuthorityResponse
    func sendTransaction(_ requestType: FeeRelayer.RequestType) async throws -> String
    func sendTransaction<T: Decodable>(_ requestType: FeeRelayer.RequestType) async throws -> T
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
    private var httpClient: HTTPClient

    // MARK: - Initializers

    public init(httpClient: HTTPClient = FeeRelayerHTTPClient(), version: Int) {
        self.version = version
        self.httpClient = httpClient
    }

    // MARK: - Methods

    /// Get fee payer for free transaction
    /// - Returns: Account's public key that is responsible for paying fee
    public func getFeePayerPubkey() async throws -> String {
        var urlString = FeeRelayer.feeRelayerUrl
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
        }
        guard res != nil else { throw APIClientError.unknown }
        return (res ?? "").replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
    }
    
    public func requestFreeFeeLimits(for authority: String) async throws -> FeeRelayer.Relay.FeeLimitForAuthorityResponse {
        var url = FeeRelayer.feeRelayerUrl
        if version > 1 {
            url += "/v\(version)"
        }
        url += "/free_fee_limits/\(authority)"
        guard let url = URL(string: url) else { throw APIClientError.unknown }

        var urlRequest: URLRequest
        do {
            urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "GET"
            urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
            #if DEBUG
            print(NSString(string: urlRequest.cURL()))
            #endif
        } catch {
            throw APIClientError.unknown
        }

        do {
            return try await httpClient.sendRequest(request: urlRequest, decoder: JSONDecoder()) as FeeRelayer.Relay.FeeLimitForAuthorityResponse
        } catch HTTPClientError.unexpectedStatusCode(_, let data) {
            let decodedError = try JSONDecoder().decode(FeeRelayer.Error.self, from: data)
            throw decodedError
        }
    }
    
    /// Send transaction to fee relayer
    /// - Parameters:
    ///   - path: additional path for request
    ///   - params: request's parameters
    /// - Returns: transaction id
    public func sendTransaction(_ requestType: FeeRelayer.RequestType) async throws -> String {
        do {
            let tx: String = try await httpClient.sendRequest(request: urlRequest(requestType), decoder: JSONDecoder())
            return tx
        } catch HTTPClientError.cantDecode(let data) {
            guard let ret = String(data: data, encoding: .utf8) else { throw APIClientError.unknown }
            return ret
        }
    }
    
    public func sendTransaction<T: Decodable>(_ requestType: FeeRelayer.RequestType) async throws -> T {
        do {
            return try await httpClient.sendRequest(request: urlRequest(requestType), decoder: JSONDecoder()) as T
        } catch HTTPClientError.cantDecode(let data) {
            do {
                let error = try JSONDecoder().decode(FeeRelayer.Error.self, from: data)
                throw APIClientError.custom(error: error)
            } catch {
                throw APIClientError.cantDecodeError
            }
        }
    }
    
    private func urlRequest(_ requestType: FeeRelayer.RequestType) throws -> URLRequest {
        var url = FeeRelayer.feeRelayerUrl
        if version > 1 {
            url += "/v\(version)"
        }
        url += requestType.path
        var urlRequest = URLRequest(url: URL(string: url)!)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try requestType.getParams()

        #if DEBUG
        print(NSString(string: urlRequest.cURL()))
        #endif
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
