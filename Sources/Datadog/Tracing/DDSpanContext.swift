/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import os.activity

// Bridging Obj-C variabled defined as c-macroses. See `activity.h` header.
private
let OS_ACTIVITY_CURRENT = unsafeBitCast( dlsym( UnsafeMutableRawPointer(bitPattern: -2), "_os_activity_current"), to: os_activity_t.self)

@_silgen_name("_os_activity_create") private
func _os_activity_create(_ dso: UnsafeRawPointer?,
                         _ description: UnsafePointer<Int8>,
                         _ parent: Unmanaged<AnyObject>?,
                         _ flags: os_activity_flag_t) -> AnyObject!

internal struct DDSpanContext: OTSpanContext {
    /// This span's trace ID.
    let traceID: TracingUUID
    /// This span ID.
    let spanID: TracingUUID
    /// The ID of the parent span or `nil` if this span is the root span.
    let parentSpanID: TracingUUID?
    /// The baggage items of this span.
    let baggageItems: BaggageItems

    let activityId: os_activity_id_t
    var activity_state = os_activity_scope_state_s()

    init(traceID: TracingUUID, spanID: TracingUUID, parentSpanID: TracingUUID?, baggageItems: BaggageItems) {
        self.traceID = traceID
        self.spanID = spanID
        self.parentSpanID = parentSpanID
        self.baggageItems = baggageItems

        let dso = UnsafeMutableRawPointer(mutating: #dsohandle)
        let activity = _os_activity_create(dso, "InitDDSpanContext", OS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT)
        activityId = os_activity_get_identifier(activity, nil)
        os_activity_scope_enter(activity, &activity_state)
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
