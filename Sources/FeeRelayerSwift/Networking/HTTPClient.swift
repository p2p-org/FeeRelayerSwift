import Foundation

public enum HTTPClientError: Error {
    case noResponse
    case cantDecode(responseData: Data)
    case unauthorized
    case unexpectedStatusCode(code: Int, response: Data)
    case unknown(error: Error)
}

public protocol HTTPClient {
    func sendRequest<T: Decodable>(request: URLRequest, decoder: JSONDecoder) async throws -> T
}

public final class FeeRelayerHTTPClient: HTTPClient {
    
    public init() {}
    
    public func sendRequest<T: Decodable>(request: URLRequest, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
//        do {
            let (data, response) = try await URLSession.shared.data(from: request)
            guard let response = response as? HTTPURLResponse else { throw HTTPClientError.noResponse }
            switch response.statusCode {
            case 200 ... 299:
                guard let decodedResponse = try? decoder.decode(T.self, from: data) else {
                    throw HTTPClientError.cantDecode(responseData: data)
                }
                return decodedResponse
            case 401:
                throw HTTPClientError.unauthorized
            default:
                throw HTTPClientError.unexpectedStatusCode(code: response.statusCode, response: data)
            }
//        } catch let error {
//            throw error
//        }
    }
}

// TODO: Move to a separate alonside HTTPClient SPM
@available(iOS, deprecated: 15.0, message: "Use the built-in API instead")
extension URLSession {
    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: url) { data, response, error in
                guard let data = data, let response = response else {
                    let error = error ?? URLError(.badServerResponse)
                    return continuation.resume(throwing: error)
                }

                continuation.resume(returning: (data, response))
            }

            task.resume()
        }
    }
    
    func data(from urlRequest: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: urlRequest) { data, response, error in
                guard let data = data, let response = response else {
                    let error = error ?? URLError(.badServerResponse)
                    return continuation.resume(throwing: error)
                }

                continuation.resume(returning: (data, response))
            }

            task.resume()
        }
    }

}
