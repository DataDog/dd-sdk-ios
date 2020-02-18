/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// URL of the endpoint for data uploads. It's being validated during its creation.
internal struct DataUploadURL {
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

/// Synchronously uploads data to server using `HTTPClient`.
internal final class DataUploader {
    private let uploadURL: DataUploadURL
    private let httpClient: HTTPClient
    private let httpHeaders: HTTPHeaders

    init(url: DataUploadURL, httpClient: HTTPClient, httpHeaders: HTTPHeaders) {
        self.uploadURL = url
        self.httpClient = httpClient
        self.httpHeaders = httpHeaders
    }

    /// Uploads data synchronously (will block current thread) and returns upload status.
    /// Uses timeout configured for `HTTPClient`.
    func upload(data: Data) -> DataUploadStatus {
        let request = createRequestWith(data: data)
        var uploadStatus: DataUploadStatus?

        let semaphore = DispatchSemaphore(value: 0)

        httpClient.send(request: request) { result in
            switch result {
            case .success(let httpResponse):
                uploadStatus = DataUploadStatus(from: httpResponse)
            case .failure(let error):
                developerLogger?.error("🔥 Failed to upload data: \(error)")
                uploadStatus = .networkError
            }

            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .distantFuture)

        return uploadStatus ?? .unknown
    }

    private func createRequestWith(data: Data) -> URLRequest {
        var request = URLRequest(url: uploadURL.url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = httpHeaders.all
        request.httpBody = data
        return request
    }
}

internal enum DataUploadStatus: Equatable, Hashable {
    /// Corresponds to HTTP 2xx response status codes.
    case success
    /// Corresponds to HTTP 3xx response status codes.
    case redirection
    /// Corresponds to HTTP 4xx response status codes.
    case clientError
    /// Corresponds to HTTP 5xx response status codes.
    case serverError
    /// Means transportation error and no delivery at all.
    case networkError
    /// Corresponds to unknown HTTP response status code.
    case unknown

    init(from httpResponse: HTTPURLResponse) {
        switch httpResponse.statusCode {
        case 200...299: self = .success
        case 300...399: self = .redirection
        case 400...499: self = .clientError
        case 500...599: self = .serverError
        default:        self = .unknown
        }
    }
}
