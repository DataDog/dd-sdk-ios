/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The ``ViewCache``  keeps previous view ids in memory.
///
/// This class can be used to store and retrieve previous RUM views based
/// on timestamp.
internal final class ViewCache {
    /// Ownership retained for an exact historical view ID.
    ///
    /// `legacy` is intentionally distinct from `unknown`: scene-less views
    /// predate multi-scene routing and keep the historical representative
    /// fallback, while an unknown ID must fail closed beside concurrent scenes.
    enum ViewOwnership: Equatable {
        case scene(RUMSceneIdentifier)
        case legacy
        case unknown
    }

    let dateProvider: DateProvider
    let ttl: Int64
    let capacity: Int

    private struct View: Hashable {
        let timestamp: Int64
        /// Timestamp used only for TTL eviction. It starts at view creation and
        /// moves to the time the view becomes inactive, so a long-lived view is
        /// still available for delayed child events for the full retention
        /// window after it stops.
        var retentionTimestamp: Int64
        let id: String
        let hasReplay: Bool?
        let sceneIdentifier: RUMSceneIdentifier?
        var isActive: Bool
    }

    private enum SceneBucket: Hashable {
        case scene(RUMSceneIdentifier)
        case legacy
    }

    @ReadWriteLock
    private var views: [View] = []

    /// Create a view-cache instance.
    ///
    /// - Parameters:
    ///   - dateProvider: The date provider.
    ///   - ttl: The TTL of view ids in cache.
    ///   - capacity: The maximum number of ids to store.
    init(
        dateProvider: DateProvider,
        ttl: TimeInterval = 3.minutes,
        capacity: Int = 30
    ) {
        self.dateProvider = dateProvider
        self.ttl = ttl.dd.toInt64Milliseconds
        self.capacity = capacity
        self.views.reserveCapacity(capacity)
    }

    /// Insert a view id in the cache.
    ///
    /// - Parameters:
    ///   - id: The view id to cache.
    ///   - timestamp: The view epoch timestamp in milliseconds.
    ///   - hasReplay: `true` if the view has replay.
    func insert(
        id: String,
        timestamp: Int64,
        hasReplay: Bool? = nil,
        sceneIdentifier: RUMSceneIdentifier? = nil
    ) {
        let now = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        _views.mutate { views in
            let sceneBucket = sceneIdentifier.map(SceneBucket.scene) ?? .legacy
            for index in views.indices {
                let existingBucket = views[index].sceneIdentifier.map(SceneBucket.scene) ?? .legacy
                if existingBucket == sceneBucket, views[index].isActive {
                    views[index].isActive = false
                    views[index].retentionTimestamp = now
                }
            }
            let view = View(
                timestamp: timestamp,
                retentionTimestamp: timestamp,
                id: id,
                hasReplay: hasReplay,
                sceneIdentifier: sceneIdentifier,
                isActive: true
            )
            // order views by desc epoch time
            if let index = views.firstIndex(where: { $0.timestamp < timestamp }) {
                views.insert(view, at: index)
            } else {
                views.append(view)
            }
        }

        purge()
    }

    /// Marks a view inactive so normal TTL eviction applies after its scene
    /// navigates away or disconnects. Active views are pinned regardless of
    /// age because a long-lived window can remain visible beyond the cache TTL.
    func markInactive(id: String) {
        let now = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        _views.mutate { views in
            for index in views.indices where views[index].id == id && views[index].isActive {
                views[index].isActive = false
                views[index].retentionTimestamp = now
            }
        }
        purge()
    }

    /// Gets the last view id before the specified timestamp.
    ///
    /// - Parameters:
    ///   - timestamp: The requested epoch timestamp in milliseconds.
    ///   - hasReplay: Specify `true` to get the last view with replay.
    ///   - sceneIdentifier: Restricts lookup to this scene when present.
    ///   - allowAmbiguousScene: Allows source-less lookup across scene buckets.
    ///   - allowLegacySceneFallback: Allows a scene request to use exclusively
    ///     scene-less history. Only single-scene applications may opt in.
    /// - Returns: The view id if found.
    func lastView<Integer>(
        before timestamp: Integer,
        hasReplay: Bool? = nil,
        sceneIdentifier: RUMSceneIdentifier? = nil,
        allowAmbiguousScene: Bool = true,
        allowLegacySceneFallback: Bool = false
    ) -> String? where Integer: BinaryInteger {
        purge()
        let cachedViews = views
        // Ordinary single-scene apps can use string-key views without a scene.
        // Never relax an exact lookup when any retained view has scene ownership.
        let requestedScene = allowLegacySceneFallback && cachedViews.allSatisfy({ $0.sceneIdentifier == nil })
            ? nil : sceneIdentifier
        if requestedScene == nil,
           !allowAmbiguousScene,
           Set(cachedViews.map { $0.sceneIdentifier.map(SceneBucket.scene) ?? .legacy }).count > 1 {
            return nil
        }

        return cachedViews.first(where: {
            if let requestedScene, $0.sceneIdentifier != requestedScene {
                return false
            }
            if $0.timestamp < timestamp {
                guard let hasReplay = hasReplay else {
                    return true
                }

                if $0.hasReplay == hasReplay {
                    return true
                }
            }
            return false
        })?.id
    }

    /// Returns the scene that owned a cached view ID.
    ///
    /// This reverse lookup lets delayed commands fall forward within their
    /// source scene after the original view ended, instead of crossing into a
    /// different window's representative view.
    func sceneIdentifier(forViewID viewID: String) -> RUMSceneIdentifier? {
        guard case .scene(let sceneIdentifier) = ownership(forViewID: viewID) else {
            return nil
        }
        return sceneIdentifier
    }

    /// Returns whether an exact cached view belonged to a scene, to the legacy
    /// scene-less path, or is no longer known.
    func ownership(forViewID viewID: String) -> ViewOwnership {
        purge()
        guard let view = views.first(where: { $0.id == viewID }) else {
            return .unknown
        }
        return view.sceneIdentifier.map(ViewOwnership.scene) ?? .legacy
    }

    private func purge() {
        let now = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds

        _views.mutate { views in
            guard capacity > 0 else {
                views = []
                return
            }

            let validViews = views.filter { $0.isActive || now - $0.retentionTimestamp <= ttl }
            let retentionCapacity = max(capacity, validViews.lazy.filter(\.isActive).count)
            guard validViews.count > retentionCapacity else {
                views = validViews
                return
            }

            // Allocate the fixed-size cache fairly across scenes. A busy window
            // must not evict every historical view ID for another live window,
            // because delayed resources and errors use this mapping to remain in
            // their source scene. With one scene this preserves the prior newest-
            // first eviction behavior.
            var retained = validViews.filter(\.isActive)
            retained.reserveCapacity(retentionCapacity)
            let inactiveViews = validViews.filter { !$0.isActive }
            var bucketIndexes: [SceneBucket: Int] = [:]
            var buckets: [[View]] = []
            for view in inactiveViews {
                let bucket = view.sceneIdentifier.map(SceneBucket.scene) ?? .legacy
                if let index = bucketIndexes[bucket] {
                    buckets[index].append(view)
                } else {
                    bucketIndexes[bucket] = buckets.count
                    buckets.append([view])
                }
            }

            var depth = 0
            while retained.count < retentionCapacity {
                var foundView = false
                for bucket in buckets where depth < bucket.count {
                    retained.append(bucket[depth])
                    foundView = true
                    if retained.count == retentionCapacity {
                        break
                    }
                }
                guard foundView else {
                    break
                }
                depth += 1
            }

            views = retained.sorted { $0.timestamp > $1.timestamp }
        }
    }
}
