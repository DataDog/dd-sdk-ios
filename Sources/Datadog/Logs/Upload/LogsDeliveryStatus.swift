import Foundation

internal enum LogsDeliveryStatus: Equatable {
    /// Corresponds to HTTP 2xx response status codes.
    case success(logs: [Log])
    /// Corresponds to HTTP 3xx response status codes.
    case redirection(logs: [Log])
    /// Corresponds to HTTP 4xx response status codes.
    case clientError(logs: [Log])
    /// Corresponds to HTTP 5xx response status codes.
    case serverError(logs: [Log])
    /// Means transportation error and no delivery at all.
    case networkError(logs: [Log])
    /// Corresponds to unknown HTTP response status code.
    case unknown(logs: [Log])

    init(from httpResponse: HTTPURLResponse, logs: [Log]) {
        switch httpResponse.statusCode {
        case 200...299: self = .success(logs: logs)
        case 300...399: self = .redirection(logs: logs)
        case 400...499: self = .clientError(logs: logs)
        case 500...599: self = .serverError(logs: logs)
        default:        self = .unknown(logs: logs)
        }
    }

    init(from httpRequestDeliveryError: Error, logs: [Log]) {
        self = .networkError(logs: logs)
    }
}
