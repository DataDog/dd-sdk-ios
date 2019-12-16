import Foundation

/// Basic HTTP request representation - limited to information that SDK needs to use.
struct HTTPRequest {
    let url: URL
    let headers: [String: String]
    let method: String
    let body: Data
}

/// Basic HTTP response representation - limited to information that SDK needs to use.
struct HTTPResponse {
    let code: Int
}

/// Error related to request delivery, like unreachable server, no internet connection etc.
struct HTTPRequestDeliveryError: Error {
    let details: Error
}

/// Client for sending requests over HTTP.
final class HTTPClient {
    private let transport: HTTPTransport
    
    init(transport: HTTPTransport) {
        self.transport = transport
    }

    func send(request: HTTPRequest, completion: @escaping (Result<HTTPResponse, HTTPRequestDeliveryError>) -> Void) {
        let urlRequest = buildURLRequest(from: request)
        transport.send(request: urlRequest) { result in
            switch result {
            case .response(let response, _):
                completion(.success(HTTPResponse(code: response.statusCode)))
            case .error(let error, _):
                completion(.failure(HTTPRequestDeliveryError(details: error)))
            }
        }
    }
    
    private func buildURLRequest(from httpRequest: HTTPRequest) -> URLRequest {
        var request = URLRequest(url: httpRequest.url)
        request.httpMethod = httpRequest.method
        request.allHTTPHeaderFields = httpRequest.headers
        request.httpBody = httpRequest.body
        return request
    }
}
