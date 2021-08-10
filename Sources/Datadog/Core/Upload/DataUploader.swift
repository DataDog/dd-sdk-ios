/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates the upload url with given query items.
internal class UploadURLProvider {
    enum QueryItem {
        /// `ddsource={source}` query item
        case ddsource(source: String)
        /// `ddtags={tag1},{tag2},...` query item
        case ddtags(tags: [String])

        var urlQueryItem: URLQueryItem {
            switch self {
            case .ddsource(let source):
                return URLQueryItem(name: "ddsource", value: source)
            case .ddtags(let tags):
                return URLQueryItem(name: "ddtags", value: tags.joined(separator: ","))
            }
        }
    }

    let url: URL

    init(url: URL, queryItems: [QueryItem]) {
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems.map { $0.urlQueryItem }
        }

        if urlComponents?.url == nil { // sanity check - should not happen
            userLogger.error("🔥 Failed to create upload URL from \(url) and \(queryItems)")
        }

        self.url = urlComponents?.url ?? url
    }
}

/// Synchronously uploads data to server using `HTTPClient`.
internal final class DataUploader {
    private let urlProvider: UploadURLProvider
    private let httpClient: HTTPClient
    private let httpHeaders: HTTPHeadersProvider
    private let internalMonitor: InternalMonitor?

    init(
        urlProvider: UploadURLProvider,
        httpClient: HTTPClient,
        httpHeaders: HTTPHeadersProvider,
        internalMonitor: InternalMonitor? = nil
    ) {
        self.urlProvider = urlProvider
        self.httpClient = httpClient
        self.httpHeaders = httpHeaders
        self.internalMonitor = internalMonitor
    }

    /// Uploads data synchronously (will block current thread) and returns upload status.
    /// Uses timeout configured for `HTTPClient`.
    func upload(data: Data) -> DataUploadStatus {
        let request = createRequestWith(data: data)
        var uploadStatus: DataUploadStatus?

        let semaphore = DispatchSemaphore(value: 0)

        httpClient.send(request: request) { [weak self] result in
            switch result {
            case .success(let httpResponse):
                uploadStatus = DataUploadStatus(from: httpResponse)
            case .failure(let error):
                self?.internalMonitor?.sdkLogger.error("Failed to upload data", error: error)
                uploadStatus = .networkError
            }

            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .distantFuture)

        return uploadStatus ?? .unknown
    }

    private func createRequestWith(data: Data) -> URLRequest {
        var request = URLRequest(url: urlProvider.url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = httpHeaders.headers
        request.httpBody = data
        return request
    }
}

internal enum DataUploadStatus: Equatable, Hashable {
    /// Corresponds to HTTP 2xx response status codes.
    case success
    /// Corresponds to HTTP 3xx response status codes.
    case redirection
    /// Corresponds to HTTP 403 response status codes,
    /// which means client token is invalid
    case clientTokenError
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
        case 403: self = .clientTokenError
        case 400...499: self = .clientError
        case 500...599: self = .serverError
        default:        self = .unknown
        }
    }
}
