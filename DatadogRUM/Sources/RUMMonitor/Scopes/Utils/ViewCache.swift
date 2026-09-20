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
    let dateProvider: DateProvider
    let ttl: Int64
    let capacity: Int

    private struct View: Hashable {
        let timestamp: Int64
        let id: String
        let hasReplay: Bool?
        var inactiveSince: Int64?
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
    ///   - isActive: `true` if the view is currently active.
    func insert(
        id: String,
        timestamp: Int64,
        hasReplay: Bool? = nil,
        isActive: Bool = false
    ) {
        let now = currentTimestamp

        _views.mutate { views in
            let view = View(
                timestamp: timestamp,
                id: id,
                hasReplay: hasReplay,
                inactiveSince: isActive ? nil : timestamp
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

        if views.count > capacity {
            views.removeSubrange(capacity...)
        }
    }
}
