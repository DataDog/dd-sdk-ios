/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Keeps slots in cache during webviews lifecycle.
///
/// Uppon recording, the cache should be reset to clear deallocated web-views.
///
/// **Note**: This class is not thread-safe and must be called on the main thread during recording only.
internal final class WebViewSlotCache {
    /// The current dictionary of slots.
    private(set) var slots: [Int: WebViewSlot] = [:]

    /// Inserts the given slot into the cache.
    ///
    /// If a slot id  is already contained in the cache, the new slot replaces
    /// the existing one.
    ///
    /// - Parameter slot: A slot to insert into the cache
    /// - Complexity O(1)
    func update(_ slot: WebViewSlot) {
        slots[slot.id] = slot
    }

    /// Purges the cache by removing deallocated webviews.
    ///
    /// - Complexity O(n)
    func purge() {
        slots = slots.compactMapValues { $0.purge() }
    }
}
