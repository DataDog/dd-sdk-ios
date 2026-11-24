/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS) && !os(macOS)

/// Captured profile data and its RUM context, ready to be written independently of the profiler.
///
/// CPU samples have timestamps and can be selected within an event's time range.
/// Heap `inuse_*` values describe sampled objects still live at capture end, including
/// surviving allocations from earlier windows; `alloc_*` totals cover the collection interval.
/// Heap aggregates have no individual timestamps, so neither metric can be sliced to an event.
internal struct ProfileSnapshot: @unchecked Sendable {
    /// This attachment's own bounds, which can differ from other snapshots on the same tick.
    let start: Date
    let end: Date
    let attachment: PprofAttachment
    let rumEvents: [RUMEvent]
    let attributes: [AttributeKey: AttributeValue]
    /// Captured with the profile, or resolved by the first session decision for a pending launch.
    var rumContext: RUMCoreContext? = nil
    /// Owned diagnostics travel with this capture, including through delayed writes.
    var memoryDiagnostics: MemoryDiagnostics? = nil
}

internal protocol ProfileSnapshotProvider: AnyObject, Sendable {
    /// Enqueues a capture on the profiler's queue and completes exactly once with owned data,
    /// or nil when unavailable. Reject ticks scheduled before the current profiling window.
    func captureSnapshot(scheduledFor time: DispatchTime, completion: @escaping @Sendable (ProfileSnapshot?) -> Void)
}

#endif
