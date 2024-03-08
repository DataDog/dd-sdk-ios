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
        dateProvider: DateProvider = SystemDateProvider(),
        ttl: TimeInterval = 3 * 60,
        capacity: Int = 30
    ) {
        self.dateProvider = dateProvider
        self.ttl = ttl.toInt64Milliseconds
        self.capacity = capacity
        self.views.reserveCapacity(capacity)
    }

    /// Insert a view id in the cache.
    ///
    /// - Parameters:
    ///   - id: The view id to cache.
    ///   - timestamp: The view epoch timestamp in milliseconds.
    ///   - hasReplay: `true` if the view has replay.
    func insert(id: String, timestamp: Int64, hasReplay: Bool? = nil) {
        _views.mutate { views in
            let view = View(timestamp: timestamp, id: id, hasReplay: hasReplay)
            // order views by desc epoch time
            if let index = views.firstIndex(where: { $0.timestamp < timestamp }) {
                views.insert(view, at: index)
            } else {
                views.append(view)
            }
        }

        purge()
    }

    /// Gets the last view id before the specified timestamp.
    ///
    /// - Parameters:
    ///   - timestamp: The requested epoch timestamp in milliseconds.
    ///   - hasReplay: Specify `true` to get the last view with replay.
    /// - Returns: The view id if found.
    func lastView<Integer>(before timestamp: Integer, hasReplay: Bool? = nil) -> String? where Integer: BinaryInteger {
        views.first(where: {
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

    private func purge() {
        let now = dateProvider.now.timeIntervalSince1970.toInt64Milliseconds

        _views.mutate {
            var views = $0.prefix(capacity)

            if let index = views.firstIndex(where: { now - $0.timestamp > ttl }) {
                views = views.prefix(upTo: index)
            }

            $0 = Array(views)
        }
    }
}
