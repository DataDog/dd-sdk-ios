/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A temporary uploader managing upload of multiple `URLRequests`. It will be fully replaced with `DatadogCore`.
///
/// TODO: RUMM-RUMM-2509 Remove this class once multiple `URLRequest` can be passed to `DatadogCore`
internal class Uploader {
    private let session: URLSession

    init() {
        // Counterpart of `URLSession` configuration in `DatadogCore/HTTPClient`
        let configuration: URLSessionConfiguration = .ephemeral
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    func upload(requests: ArraySlice<URLRequest>) {
        requests.forEach { request in
            let task = session.dataTask(with: request) { data, response, error in
                switch httpClientResult(for: (data, response, error)) {
                case .failure(let error):
                    print("[DATADOG Session Replay] 🐶🎥 →  an error occured when performing arbitrary upload: \(error)")
                case .success(let response):
                    if response.statusCode != 202 {
                        print("[DATADOG Session Replay] 🐶🎥 →  arbitrary upload completed with unexpected status code: \(response.statusCode)")
                    } else if SessionReplay.arbitraryUploadsVerbosity {
                        print("[DATADOG Session Replay] 🐶🎥 →  arbitrary upload completed with status code: \(response.statusCode)")
                    }
                }
            }
            task.resume()
        }
    }
}

/// An error returned if `URLSession` response state is inconsistent (like no data, no response and no error).
/// The code execution in `URLSessionTransport` should never reach its initialization.
internal struct URLSessionTransportInconsistencyException: Error {}

/// As `URLSession` returns 3-values-tuple for request execution, this function applies consistency constraints and turns
/// it into only two possible states of `HTTPTransportResult`.
private func httpClientResult(for urlSessionTaskCompletion: (Data?, URLResponse?, Error?)) -> Result<HTTPURLResponse, Error> {
    let (_, response, error) = urlSessionTaskCompletion

    if let error = error {
        return .failure(error)
    }

    if let httpResponse = response as? HTTPURLResponse {
        return .success(httpResponse)
    }

    return .failure(URLSessionTransportInconsistencyException())
}
