/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates URL and adds query items before providing them
internal class UploadURLProvider {
    private let urlWithClientToken: URL
    private let queryItemProviders: [QueryItemProvider]

    class QueryItemProvider {
        let value: () -> URLQueryItem

        /// Creates `ddsource=ios` query item.
        static func ddsource(source: String) -> QueryItemProvider {
            let queryItem = URLQueryItem(name: "ddsource", value: source)
            return QueryItemProvider { queryItem }
        }

        /// Creates `ddtags=tag1,tag2,...` query item.
        static func ddtags(tags: [String]) -> QueryItemProvider {
            let queryItem = URLQueryItem(name: "ddtags", value: tags.joined(separator: ","))
            return QueryItemProvider { queryItem }
        }

        private init(value: @escaping () -> URLQueryItem) {
            self.value = value
        }
    }

    var url: URL {
        // In RUMM-655 we've removed the last dynamic query item and this `url` may just become constant
        // in the future.

        var urlComponents = URLComponents(url: urlWithClientToken, resolvingAgainstBaseURL: false)

        if !queryItemProviders.isEmpty {
            urlComponents?.queryItems = queryItemProviders.map { $0.value() }
        }

        guard let url = urlComponents?.url else {
            userLogger.error("🔥 Failed to create URL from \(urlWithClientToken) with \(queryItemProviders)")
            return urlWithClientToken
        }
        return url
    }

    init(urlWithClientToken: URL, queryItemProviders: [QueryItemProvider]) {
        self.urlWithClientToken = urlWithClientToken
        self.queryItemProviders = queryItemProviders
    }
}

/// Synchronously uploads data to server using `HTTPClient`.
internal final class DataUploader {
    private let urlProvider: UploadURLProvider
    private let httpClient: HTTPClient
    private let httpHeaders: HTTPHeaders
    private let internalMonitor: InternalMonitor?

    init(
        urlProvider: UploadURLProvider,
        httpClient: HTTPClient,
        httpHeaders: HTTPHeaders,
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
