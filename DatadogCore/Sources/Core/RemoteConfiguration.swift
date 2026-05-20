/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Owns the remote configuration cache and fetch lifecycle.
///
/// Created by `DatadogCore` when a `remoteConfigurationID` is provided.
/// Call `start(from:connectionProxyDictionary:telemetry:)` once the core is
/// registered to fire the initial CDN fetch.
///
/// TODO: Also trigger `start()` on every app foreground transition so remote config
/// is refreshed while the app is in use, not only at SDK init (RFC §Caching Strategy).
internal final class RemoteConfiguration {
    let cache: RemoteConfigurationCache

    init(id: String, directory: Directory) {
        self.cache = RemoteConfigurationCache(id: id, directory: directory)
    }

    /// Reports any load error from the previous session and fires an async CDN fetch.
    ///
    /// - Parameter session: Injected only in tests; pass `nil` in production.
    func start(from endpoint: URL, connectionProxyDictionary: [AnyHashable: Any]?, telemetry: Telemetry, session: URLSession? = nil) {
        if let error = cache.loadError {
            telemetry.error("[RemoteConfig] Failed to load cached configuration from disk", error: error)
        }
        let fetcher: RemoteConfigurationFetcher
        if let session = session {
            fetcher = RemoteConfigurationFetcher(cache: cache, telemetry: telemetry, session: session)
        } else {
            fetcher = RemoteConfigurationFetcher(cache: cache, connectionProxyDictionary: connectionProxyDictionary, telemetry: telemetry)
        }
        fetcher.fetch(from: endpoint)
    }
}
