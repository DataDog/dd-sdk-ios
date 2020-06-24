/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct DDSpanContext: OTSpanContext {
    /// This span's trace ID.
    let traceID: TracingUUID
    /// This span ID.
    let spanID: TracingUUID
    /// The ID of the parent span or `nil` if this span is the root span.
    let parentSpanID: TracingUUID?
    /// The baggage items of this span.
    let baggageItems: BaggageItems

    // MARK: - Open Tracing interface

    func forEachBaggageItem(callback: (String, String) -> Bool) {
        for (itemKey, itemValue) in baggageItems.all {
            if callback(itemKey, itemValue) {
                break
            }
        }
    }
}

/// Baggage items are used to propagate span information from parent to child. This propagation is
/// unidirectional and recursive, so the grandchild of a span `A` will contain the `A's` baggage items,
/// but `A` won't contain items of its descendants.
internal class BaggageItems {
    /// Queue used to synchronize `unsafeItems` access.
    private let queue: DispatchQueue
    /// Baggage items of the parent `DDSpan` or`nil` for items of the root span.
    private let parent: BaggageItems?

    /// Unsynchronized baggage items dictionary. Use `queue` to synchronize the access.
    private var unsafeItems: [String: String] = [:]

    init(targetQueue: DispatchQueue, parentSpanItems: BaggageItems?) {
        self.queue = DispatchQueue(label: "com.datadoghq.BaggageItem", target: targetQueue)
        self.parent = parentSpanItems
    }

    func set(key: String, value: String) {
        queue.async { self.unsafeItems[key] = value }
    }

    func get(key: String) -> String? {
        queue.sync { self.unsafeItems[key] }
    }

    var all: [String: String] {
        queue.sync { self.unsafeAll }
    }

    /// Returns all baggage items for the span, including its parent items.
    /// This property is unsafe and should be accessed using `queue`.
    private var unsafeAll: [String: String] {
        let parentItems = parent?.unsafeAll ?? [:]
        let selfItems = unsafeItems

        let allItems = parentItems.merging(selfItems) { _, selfItem -> String in
            return selfItem
        }

        return allItems
    }
}
