/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Client for sending requests over HTTP.
internal class URLSessionClient: HTTPClient {
    internal let session: URLSession

    convenience init(proxyConfiguration: [AnyHashable: Any]? = nil) {
        let configuration: URLSessionConfiguration = .ephemeral
        // NOTE: RUMM-610 Default behaviour of `.ephemeral` session is to cache requests.
        // To not leak requests memory (including their `.httpBody` which may be significant)
        // we explicitly opt-out from using cache. This cannot be achieved using `.requestCachePolicy`.
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = proxyConfiguration

        // URLSession does not set the `Proxy-Authorization` header automatically when using a proxy
        // configuration. We manually set the HTTP basic authentication header.
        if
            let user = proxyConfiguration?[kCFProxyUsernameKey] as? String,
            let password = proxyConfiguration?[kCFProxyPasswordKey] as? String
        {
            let authorization = basicHTTPAuthentication(username: user, password: password)
            configuration.httpAdditionalHeaders = ["Proxy-Authorization": authorization]
        }

        self.init(session: URLSession(configuration: configuration))
    }

    init(session: URLSession) {
        self.session = session
    }

    func send(request: URLRequest, completion: @escaping (Result<HTTPURLResponse, Error>) -> Void) {
        let task = session.dataTask(with: request) { data, response, error in
            completion(httpClientResult(for: (data, response, error)))
        }
        task.resume()
    }
}

/// An error returned if `URLSession` response state is inconsistent (like no data, no response and no error).
/// The code execution in `URLSessionTransport` should never reach its initialization.
internal struct URLSessionTransportInconsistencyException: Error {}

/// Returns a `Basic` `Authorization` header using the `username` and `password` provided.
///
/// - Parameters:
///   - username: The username of the header.
///   - password: The password of the header.
/// - Returns: The HTTP Basic authentication header value
private func basicHTTPAuthentication(username: String, password: String) -> String {
    let credential = Data("\(username):\(password)".utf8).base64EncodedString()
    return "Basic \(credential)"
}

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
