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
    /// Scene-less legacy views retain representative fallback; unknown IDs do not.
    enum ViewOwnership: Equatable {
        case scene(RUMSceneIdentifier)
        case legacy
        case unknown
    }

    let dateProvider: DateProvider
    let ttl: Int64
    let capacity: Int
    private let isMultiSceneTrackingEnabled: Bool

    private struct View: Hashable {
        let timestamp: Int64
        let id: String
        let hasReplay: Bool?
        var inactiveSince: Int64?
        let sceneIdentifier: RUMSceneIdentifier?
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
        capacity: Int = 30,
        isMultiSceneTrackingEnabled: Bool = false
    ) {
        self.dateProvider = dateProvider
        self.ttl = ttl.dd.toInt64Milliseconds
        self.capacity = capacity
        self.isMultiSceneTrackingEnabled = isMultiSceneTrackingEnabled
        self.views.reserveCapacity(capacity)
    }

    /// Insert a view id in the cache.
    ///
    /// - Parameters:
    ///   - id: The view id to cache.
    ///   - timestamp: The view epoch timestamp in milliseconds.
    ///   - hasReplay: `true` if the view has replay.
    ///   - isActive: `true` if the view is currently active.
    ///   - sceneIdentifier: The optional scene owner; `nil` preserves legacy ownership.
    func insert(
        id: String,
        timestamp: Int64,
        hasReplay: Bool? = nil,
        isActive: Bool = false,
        sceneIdentifier: RUMSceneIdentifier? = nil
    ) {
        let now = currentTimestamp

        _views.mutate { views in
            if isMultiSceneTrackingEnabled && isActive {
                for index in views.indices where views[index].sceneIdentifier == sceneIdentifier && views[index].inactiveSince == nil {
                    views[index].inactiveSince = now
                }
            }
            let view = View(
                timestamp: timestamp,
                id: id,
                hasReplay: hasReplay,
                inactiveSince: isActive ? nil : timestamp,
                sceneIdentifier: sceneIdentifier
            )
            // Order views by descending epoch time.
            if let index = views.firstIndex(where: { $0.timestamp < timestamp }) {
                views.insert(view, at: index)
            } else {
                views.append(view)
            }
            purge(&views, now: now)
        }
    }

    /// Marks the matching active view as inactive at the current device time.
    func markInactive(id: String) {
        let now = currentTimestamp

        _views.mutate { views in
            guard let index = views.firstIndex(where: { $0.id == id && $0.inactiveSince == nil }) else {
                return
            }

            views[index].inactiveSince = now
            purge(&views, now: now)
        }
    }

    /// Gets the last view id before the specified timestamp.
    ///
    /// - Parameters:
    ///   - timestamp: The requested epoch timestamp in milliseconds.
    ///   - hasReplay: Specify `true` to get the last view with replay.
    /// - Returns: The view id if found.
    func lastView<Integer>(before timestamp: Integer, hasReplay: Bool? = nil) -> String? where Integer: BinaryInteger {
        let now = currentTimestamp
        var result: String?

        _views.mutate { views in
            purge(&views, now: now)
            result = views.first(where: {
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

        return result
    }

    /// Returns the owner of an exact retained View ID, without guessing a current peer.
    func ownership(forViewID viewID: String) -> ViewOwnership {
        let now = currentTimestamp
        var result: ViewOwnership = .unknown

        _views.mutate { views in
            purge(&views, now: now)
            if let view = views.first(where: { $0.id == viewID }) {
                result = view.sceneIdentifier.map(ViewOwnership.scene) ?? .legacy
            }
        }

        return result
    }

    private var currentTimestamp: Int64 {
        dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
    }

    private func purge(_ views: inout [View], now: Int64) {
        views.removeAll { view in
            guard let inactiveSince = view.inactiveSince else {
                return false
            }
            return now - inactiveSince > ttl
        }

        if isMultiSceneTrackingEnabled {
            retainSceneHistory(&views)
        } else if views.count > capacity {
            views.removeSubrange(capacity...)
        }
    }

    /// Active owners are pinned; remaining history slots are shared across scene buckets.
    /// Called only while holding the existing cache write lock and only in multi-scene mode.
    private func retainSceneHistory(_ views: inout [View]) {
        guard capacity > 0 else {
            views.removeAll()
            return
        }

        let active = views.filter { $0.inactiveSince == nil }
        let limit = max(capacity, active.count)
        guard views.count > limit else {
            return
        }

        var retained = Set(views.indices.filter { views[$0].inactiveSince == nil })
        var bucketIndexes: [SceneBucket: Int] = [:]
        var buckets: [[Int]] = []
        for index in views.indices where views[index].inactiveSince != nil {
            let bucket = views[index].sceneIdentifier.map(SceneBucket.scene) ?? .legacy
            if let bucketIndex = bucketIndexes[bucket] {
                buckets[bucketIndex].append(index)
            } else {
                bucketIndexes[bucket] = buckets.count
                buckets.append([index])
            }
        }

        var depth = 0
        while retained.count < limit {
            var foundView = false
            for bucket in buckets where depth < bucket.count {
                retained.insert(bucket[depth])
                foundView = true
                if retained.count == limit {
                    break
                }
            }
            guard foundView else {
                break
            }
            depth += 1
        }
        // Preserve insertion order, including equal timestamps.
        views = views.enumerated().compactMap { retained.contains($0.offset) ? $0.element : nil }
    }
}
