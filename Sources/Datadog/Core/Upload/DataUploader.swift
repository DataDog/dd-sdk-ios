/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates the upload url with given query items.
internal class UploadURL {
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

        self.url = urlComponents?.url ?? url
    }
}

/// A type that performs data uploads.
internal protocol DataUploaderType {
    func upload(data: Data) -> DataUploadStatus
}

/// Synchronously uploads data to server using `HTTPClient`.
internal final class DataUploader: DataUploaderType {
    /// An unreachable upload status - only meant to satisfy the compiler.
    private static let unreachableUploadStatus = DataUploadStatus(needsRetry: false, userDebugDescription: "", userErrorMessage: nil, internalMonitoringError: nil)

    private let httpClient: HTTPClient
    private let uploadURL: UploadURL
    private let headersProvider: HTTPHeadersProvider

    init(
        httpClient: HTTPClient,
        uploadURL: UploadURL,
        headersProvider: HTTPHeadersProvider
    ) {
        self.httpClient = httpClient
        self.uploadURL = uploadURL
        self.headersProvider = headersProvider
    }

    /// Uploads data synchronously (will block current thread) and returns the upload status.
    /// Uses timeout configured for `HTTPClient`.
    func upload(data: Data) -> DataUploadStatus {
        let (request, ddRequestID) = createRequestWith(data: data)
        var uploadStatus: DataUploadStatus?

        let semaphore = DispatchSemaphore(value: 0)

        httpClient.send(request: request) { result in
            switch result {
            case .success(let httpResponse):
                uploadStatus = DataUploadStatus(httpResponse: httpResponse, ddRequestID: ddRequestID)
            case .failure(let error):
                uploadStatus = DataUploadStatus(networkError: error)
            }

            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .distantFuture)

        return uploadStatus ?? DataUploader.unreachableUploadStatus
    }

    private func createRequestWith(data: Data) -> (request: URLRequest, ddRequestID: String?) {
        var request = URLRequest(url: uploadURL.url)
        let headers = headersProvider.headers
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = data
        return (request: request, ddRequestID: headers[HTTPHeadersProvider.HTTPHeader.ddRequestIDHeaderField])
    }
}
