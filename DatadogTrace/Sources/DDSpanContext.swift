/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct DDSpanContext: OTSpanContext {
    /// This span's trace ID.
    let traceID: TraceID
    /// This span ID.
    let spanID: SpanID
    /// The ID of the parent span or `nil` if this span is the root span.
    let parentSpanID: SpanID?
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
    /// Baggage items of the parent `DDSpan` or`nil` for items of the root span.
    private let parent: BaggageItems?

    /// Baggage items dictionary. This property uses a read-write lock.
    @ReadWriteLock
    private var items: [String: String] = [:]

    init(parent: BaggageItems? = nil) {
        self.parent = parent
    }

    func set(key: String, value: String) {
        _items.mutate { $0[key] = value }
    }

    func get(key: String) -> String? {
        all[key]
    }

    /// Returns all baggage items for the span, including its parent items.
    var all: [String: String] {
        guard let parent = parent?.all else {
            return items
        }
        return parent.merging(items) { $1 }
    }
}
