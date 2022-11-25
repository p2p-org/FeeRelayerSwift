// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation

public protocol FeeRelayerAPIClient {
    /// Get current version of fee relayer server
    var version: Int { get }

    /// Environment identifier
    var environment: FeeRelayerAPIEnvironment { get }

    /// Get fee payer address
    func getFeePayerPubkey() async throws -> String

    /// Get fee token data
    func feeTokenData(mint: String) async throws -> FeeTokenData

    /// Get current user's usage
    func requestFreeFeeLimits(for authority: String) async throws -> FeeLimitForAuthorityResponse

    /// Submit transaction
    func sendTransaction(_ requestType: RequestType) async throws -> String
}

public enum FeeRelayerAPIEnvironment: String {
    case prod
    case dev
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
    public let environment: FeeRelayerAPIEnvironment
    private let baseUrlString: String
    private var httpClient: HTTPClient

    // MARK: - Initializers

    public init(
        httpClient: HTTPClient = FeeRelayerHTTPClient(),
        baseUrlString: String,
        version: Int,
        environment: FeeRelayerAPIEnvironment = .dev
    ) {
        self.version = version
        self.environment = environment
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
        var components = URLComponents(string: urlString)
        guard let url = components?.url else { throw APIClientError.invalidURL }
        var request = URLRequest(url: url)
        request.addValue(environment.rawValue, forHTTPHeaderField: "X-Environment")

        var res: String?
        do {
            res = try await httpClient.sendRequest(request: request, decoder: JSONDecoder())
        } catch let HTTPClientError.cantDecode(data) {
            res = String(data: data, encoding: .utf8)
            Logger.log(event: "FeeRelayerSwift getFeePayerPubkey", message: res, logLevel: .debug)
        }
        guard let res = res else { throw APIClientError.unknown }
        return res
    }

    public func requestFreeFeeLimits(for authority: String) async throws -> FeeLimitForAuthorityResponse {
        var urlString = baseUrlString
        if version > 1 {
            urlString += "/v\(version)"
        }
        urlString += "/free_fee_limits/\(authority)"
        var components = URLComponents(string: urlString)
        guard let url = components?.url else { throw APIClientError.invalidURL }

        var urlRequest: URLRequest
        urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue(environment.rawValue, forHTTPHeaderField: "X-Environment")

        Logger.log(event: "FeeRelayerSwift requestFreeFeeLimits", message: urlRequest.cURL(), logLevel: .debug)

        do {
            return try await httpClient.sendRequest(request: urlRequest, decoder: JSONDecoder()) as FeeLimitForAuthorityResponse
        } catch let HTTPClientError.unexpectedStatusCode(_, data) {
            Logger.log(event: "FeeRelayerSwift: requestFreeFeeLimits", message: String(data: data, encoding: .utf8), logLevel: .error)
            let decodedError = try JSONDecoder().decode(FeeRelayerError.self, from: data)
            throw decodedError
        }
    }

    public func feeTokenData(mint: String) async throws -> FeeTokenData {
        var urlString = baseUrlString
        if version > 1 {
            urlString += "/v\(version)"
        }
        urlString += "/fee_token_data/\(mint)"
        var components = URLComponents(string: urlString)
        guard let url = components?.url else { throw APIClientError.invalidURL }

        var urlRequest: URLRequest
        urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue(environment.rawValue, forHTTPHeaderField: "X-Environment")

        Logger.log(event: "FeeRelayerSwift getFeeTokenData", message: urlRequest.cURL(), logLevel: .debug)

        do {
            return try await httpClient.sendRequest(request: urlRequest, decoder: JSONDecoder())
        } catch let HTTPClientError.unexpectedStatusCode(_, data) {
            Logger.log(event: "FeeRelayerSwift: getFeeTokenData", message: String(data: data, encoding: .utf8), logLevel: .error)
            let decodedError = try JSONDecoder().decode(FeeRelayerError.self, from: data)
            throw decodedError
        }
    }

    /// Send transaction to fee relayer
    public func sendTransaction(_ requestType: RequestType) async throws -> String {
        do {
            let response: String = try await httpClient.sendRequest(request: urlRequest(requestType), decoder: JSONDecoder())
            return response
        } catch let HTTPClientError.cantDecode(data) {
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

    private func urlRequest(_ requestType: RequestType) throws -> URLRequest {
        var urlString = baseUrlString
        if version > 1 {
            urlString += "/v\(version)"
        }
        urlString += requestType.path
        var components = URLComponents(string: urlString)
        guard let url = components?.url else { throw APIClientError.invalidURL }
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue(environment.rawValue, forHTTPHeaderField: "X-Environment")
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

private extension URLRequest {
    func cURL(pretty: Bool = false) -> String {
        let newLine = pretty ? "\\\n" : ""
        let method = (pretty ? "--request " : "-X ") + "\(httpMethod ?? "GET") \(newLine)"
        let url: String = (pretty ? "--url " : "") + "\'\(self.url?.absoluteString ?? "")\' \(newLine)"

        var cURL = "curl "
        var header = ""
        var data = ""

        if let httpHeaders = allHTTPHeaderFields, httpHeaders.keys.count > 0 {
            for (key, value) in httpHeaders {
                header += (pretty ? "--header " : "-H ") + "\'\(key): \(value)\' \(newLine)"
            }
        }

        if let bodyData = httpBody, let bodyString = String(data: bodyData, encoding: .utf8), !bodyString.isEmpty {
            data = "--data '\(bodyString)'"
        }

        cURL += method + url + header + data

        return cURL
    }
}
