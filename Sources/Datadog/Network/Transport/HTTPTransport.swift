import Foundation

/// A result of request sending request with `HTTPTransport`.
enum HTTPTransportResult {
    /// Means successful request delivery.
    case response(HTTPURLResponse, Data?)
    /// Means transportation error (unreachable server, no internet connection, ...).
    case error(Error, Data?)
}

/// A type sending requests over HTTP.
protocol HTTPTransport {
    func send(request: URLRequest, callback: @escaping (HTTPTransportResult) -> Void)
}
