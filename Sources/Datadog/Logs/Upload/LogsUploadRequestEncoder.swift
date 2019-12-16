import Foundation

/// Builds `HTTPRequest` for sending logs to the server.
struct LogsUploadRequestEncoder {
    private let url: URL
    private let headers = ["Content-Type": "application/json"]
    private let method = "POST"
    private let jsonEncoder: JSONEncoder
    
    init(uploadURL: URL) {
        self.url = uploadURL
        self.jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
    }
    
    func encodeRequest(with logs: [Log]) throws -> HTTPRequest {
        return HTTPRequest(url: url, headers: headers, method: method, body: try jsonEncoder.encode(logs))
    }
}
