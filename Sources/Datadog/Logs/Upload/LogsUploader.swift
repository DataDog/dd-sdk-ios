import Foundation

/// Sends logs to server.
internal final class LogsUploader {
    private let httpClient: HTTPClient
    private let requestEncoder: LogsUploadRequestEncoder

    convenience init(validURL: ValidURL) {
        self.init(validURL: validURL, httpClient: HTTPClient())
    }

    init(validURL: ValidURL, httpClient: HTTPClient) {
        self.httpClient = httpClient
        self.requestEncoder = LogsUploadRequestEncoder(uploadURL: validURL.url)
    }

    func upload(logs: [Log], completion: @escaping (LogsDeliveryStatus) -> Void) throws {
        let request = try requestEncoder.encodeRequest(with: logs)
        httpClient.send(request: request) { result in
            switch result {
            case .success(let httpResponse):
                completion(LogsDeliveryStatus(from: httpResponse, logs: logs))
            case .failure(let httpRequestDeliveryError):
                completion(LogsDeliveryStatus(from: httpRequestDeliveryError, logs: logs))
            }
        }
    }

    // MARK: - URL validation

    struct ValidURL {
        let url: URL

        init(endpointURL: String, clientToken: String) throws {
            guard !endpointURL.isEmpty, let endpointURL = URL(string: endpointURL) else {
                throw ProgrammerError(description: "`endpointURL` cannot be empty.")
            }
            guard !clientToken.isEmpty else {
                throw ProgrammerError(description: "`clientToken` cannot be empty.")
            }
            let endpointURLWithClientToken = endpointURL.appendingPathComponent(clientToken)
            guard let url = URL(string: "\(endpointURLWithClientToken.absoluteString)?ddsource=mobile") else {
                throw ProgrammerError(description: "Cannot build logs upload URL.")
            }
            self.url = url
        }
    }
}
