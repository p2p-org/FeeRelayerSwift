//
//  FeeRelayer.swift
//  FeeRelayerSwift
//
//  Created by Chung Tran on 16/07/2021.
//

import Foundation
import RxSwift
import RxAlamofire

public struct FeeRelayer {
    // MARK: - Constants
    static let feeRelayerUrl = "https://fee-relayer.solana.p2p.org"
    
    // MARK: - Initializers
    public init() {}
    
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
                    debugPrint(string)
                    throw getError(responseString: string)
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
                        throw getError(responseString: string)
                    }
                    return string
                }
                .take(1)
                .asSingle()
        } catch {
            return .error(error)
        }
    }
    
    /// Parse error from responseString
    /// - Parameter responseString: string that is responded from server
    /// - Returns: custom FeeRelayer's Error
    func getError(responseString: String) -> Error {
        // get type
        var errorType: ErrorType?
        var data: FeeRelayerErrorDataType? = responseString
        
        if let rawValue = responseString.slice(to: "("),
           let type = ErrorType(rawValue: rawValue)
        {
            errorType = type
        }
        
        else if let rawValue = responseString.slice(to: " "),
                let type = ErrorType(rawValue: rawValue)
        {
            errorType = type
        }
        
        if let rawValue = responseString.slice(to: "(") ?? responseString.slice(to: " "),
           let type = ErrorType(rawValue: rawValue)
        {
            errorType = type
        }
        
        if let errorType = errorType {
            let dataString = responseString.replacingOccurrences(of: errorType.rawValue, with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "Some(", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: ",,", with: ",")
            data = dataString
            
            if let parsedData = dataString.data(using: .utf8),
               let reason = try? JSONDecoder().decode(FeeRelayerErrorData.self, from: parsedData)
            {
                data = reason
            }
        }
        
        
        return Error(type: errorType ?? .unknown, data: data)
    }
}

private extension String {
    func slice(to: String) -> String? {
        guard let rangeTo = range(of: to)?.lowerBound else { return nil }
        return String(self[..<rangeTo])
    }
    
    func slice(from: String, to: String) -> String? {
        guard let rangeFrom = range(of: from)?.upperBound else { return nil }
        guard let rangeTo = self[rangeFrom...].range(of: to)?.lowerBound else { return nil }
        return String(self[rangeFrom..<rangeTo])
    }
}
