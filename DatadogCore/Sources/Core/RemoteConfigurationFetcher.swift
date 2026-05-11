/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Fetches the remote configuration JSON document from the CDN and delegates
/// storage to `RemoteConfigurationCache`.
///
/// Rules:
/// - Fetch is always asynchronous — never blocks the caller.
/// - On success (2xx, non-empty body, valid JSON): calls `cache.save(_:)`.
/// - On any failure: reports a telemetry error and leaves the existing cache untouched.
internal final class RemoteConfigurationFetcher {
    private let cache: RemoteConfigurationCache
    private let telemetry: Telemetry
    private let session: URLSession

    init(
        cache: RemoteConfigurationCache,
        telemetry: Telemetry,
        session: URLSession = URLSession(configuration: .ephemeral)
    ) {
        self.cache = cache
        self.telemetry = telemetry
        self.session = session
    }

    /// Fires a background GET request to `endpoint`.
    ///
    /// - Parameter endpoint: The CDN URL to fetch from.
    /// - Parameter didComplete: Called when the fetch (and any write) is done.
    ///   Pass `nil` in production; inject a closure in tests to await completion.
    func fetch(from endpoint: URL, didComplete: (() -> Void)? = nil) {
        let cache = self.cache
        let telemetry = self.telemetry
        let task = session.dataTask(with: endpoint) { data, response, error in
            defer { didComplete?() }

            // 1. Network error
            if let error = error {
                telemetry.error("[RemoteConfig] Network error", error: error)
                return
            }

            // 2. Non-2xx HTTP status
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                telemetry.error("[RemoteConfig] Non-2xx response: \(code)")
                return
            }

            // 3. Empty body
            guard let data = data, !data.isEmpty else {
                telemetry.error("[RemoteConfig] Empty response body")
                return
            }

            // 4. Invalid JSON
            guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
                telemetry.error("[RemoteConfig] Response is not valid JSON")
                return
            }

            // All checks passed — persist to disk
            cache.save(data)
        }
        task.resume()
    }
}
