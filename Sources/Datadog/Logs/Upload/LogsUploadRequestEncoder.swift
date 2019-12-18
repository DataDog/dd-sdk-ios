import Foundation

/// Builds `HTTPRequest` for sending logs to the server.
internal struct LogsUploadRequestEncoder {
    private let url: URL
    private let headers = ["Content-Type": "application/json"]
    private let method = "POST"
    private let jsonEncoder: JSONEncoder

    init(uploadURL: URL) {
        self.url = uploadURL
        self.jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
    }

    func encodeRequest(with logs: [Log]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.allHTTPHeaderFields = headers
        request.httpBody = try jsonEncoder.encode(logs)
        return request
    }
}
