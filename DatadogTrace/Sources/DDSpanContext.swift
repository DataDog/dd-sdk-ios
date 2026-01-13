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
    /// The sample rate used for sampling this span.
    ///
    /// It is a value between `0.0` (drop) and `100.0` (keep), determined by the local or distributed trace sampler.
    let sampleRate: Float
    /// The sampling decision for the span.
    let samplingDecision: SamplingDecision

    /// Delegate method called by ``DDSpan.setTag(key:value:)`` that filters and runs custom actions for specific tags.
    ///
    /// Currently, two special tags are supported: ``SpanTags.manualKeep`` and ``SpanTags.manualDrop``. Iff the value
    /// os those tags is set to true, the span is marked with a manual override to be sampled, or not, respectively.
    ///
    /// - parameters:
    ///    - span: The span where a tag is being set.
    ///    - key: The tag key.
    ///    - value: The tag value.
    /// - returns: `true` if the tag should be kept by the span as it would normally be, `false` if the tag should be ignored
    /// and not kept by the span.
    mutating func span(_ span: DDSpan, willSetTagWithKey key: String, value: Encodable) -> Bool {
        if key == SpanTags.manualDrop && value as? Bool == true {
            samplingDecision.addManualDropOverride()
            return false
        } else if key == SpanTags.manualKeep && value as? Bool == true {
            samplingDecision.addManualKeepOverride()
            return false
        }
        return true
    }

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
