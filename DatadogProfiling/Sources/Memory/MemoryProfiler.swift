/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS)

@_implementationOnly import DatadogMachProfiler

/// Owns the memory (heap) profiling lifecycle: allocation interception, the emission window, the
/// RUM correlation accumulated for that window, and the capture and upload of `heap.pprof`.
///
/// It is deliberately NOT a scheduler. `DatadogProfiler` owns the single periodic timer and drives
/// this type at its boundary — either pulling a heap attachment for a CPU profile it is already
/// writing (`heapAttachment(fittingAlongside:attributes:operation:)`) or asking for a standalone
/// heap-only profile (`emitPeriodicHeapProfile(end:)`). Keeping the timer on one side means memory
/// can never reschedule, start or stop the CPU profiler.
///
/// Every method documented as "must be called on `queue`" runs on `DatadogProfiler`'s own serial
/// queue, which this type shares. That shared queue — rather than a second one — is what keeps the
/// two units' ordering deterministic without locks.
internal final class MemoryProfiler: ProfilingHandler {
    enum Constants {
        /// Minimum wall time between two heap emissions from any path.
        ///
        /// Hangs and memory warnings arrive in bursts — a memory-pressure storm can post several
        /// warnings a second — and each emission is an upload. A trigger inside this window is
        /// folded rather than dropped: its correlation is already recorded, so it still reaches the
        /// product on the next emission.
        ///
        /// Matches the `minProfileDuration` the CPU machine already uses for custom profiling.
        static let minHeapEmissionInterval: TimeInterval = 5
    }

    let featureScope: FeatureScope
    let telemetryController: ProfilingTelemetryController
    let encoder: JSONEncoder

    private let profilingSamplerProvider: ProfilingSamplerProvider
    private let quotaChecker: ProfilingQuotaChecking
    private let profilingConditions: ProfilingConditions
    private let dateProvider: DateProvider

    @ReadWriteLock
    private(set) var attributes: [AttributeKey: AttributeValue] = [:]
    /// Interval between device and server time.
    @ReadWriteLock
    private(set) var currentServerTimeOffset: TimeInterval = .zero

    // MARK: - Queue-confined state

    /// Correlation for the memory window, accumulated separately from the CPU state machine's.
    ///
    /// The CPU collections follow the CPU lifecycle: `cleanUpState` clears them whenever the CPU
    /// window ends, which in a memory-only session (continuous not configured, so the native
    /// profiler is always `.stopped`) happens on every operation step and every app-state change.
    /// Memory windows do not end at those moments, so reading the CPU's collections meant heap
    /// profiles losing correlation the CPU no longer needed.
    ///
    /// These are fed from the same message handlers and cleared only when a heap profile is
    /// actually emitted.
    private var vitals: [String: Vital] = [:]
    private var hangs: [DurationEvent] = []
    private var longTasks: [DurationEvent] = []
    private var warnings: [DurationEvent] = []

    /// Start of the current emission window, used to bound a heap-only `ProfileEvent` (which has no
    /// CPU profile to source timestamps from). Advanced only when allocation totals are drained.
    private var windowStart: Date
    private var didDrainAllocationWindow = false
    /// Whether memory interception is currently installed. Tracked so reconciliation only calls
    /// start/stop on an actual state change.
    private(set) var isRecording = false
    /// Latched when native recording could not start. Retrying a failed install on each context
    /// update would repeat telemetry without restoring a complete allocation lifecycle.
    private var hasInterceptionFailed = false
    /// Lets the sampler run optimistically at launch (before the RUM memory sampling decision
    /// arrives) so the first window covers app launch. Consumed once a definitive decision arrives.
    private var isGraceAvailable: Bool
    /// Whether the heap has already been emitted since profiling conditions were last lost.
    /// Memory keeps recording in the background, so without this latch every flush arriving while
    /// conditions are blocked would upload the same live set again as a fresh profile.
    /// Re-armed on a genuine return to use (conditions restored and the app `.active`).
    private var hasEmittedSinceConditionsLost = false
    /// When the last heap profile was emitted, by any path. `nil` until the first one, so the
    /// launch trigger is never throttled.
    private var lastEmission: Date?
    private var hasConditionsToProfile = true
    /// Consent remains fail-open while `.pending`; only `.notGranted` disables collection.
    private var isTrackingConsentAllowed = true

    init(
        core: DatadogCoreProtocol,
        profilingSamplerProvider: ProfilingSamplerProvider,
        quotaChecker: ProfilingQuotaChecking,
        telemetryController: ProfilingTelemetryController,
        profilingConditions: ProfilingConditions,
        dateProvider: DateProvider,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.featureScope = core.scope(for: ProfilerFeature.self)
        self.profilingSamplerProvider = profilingSamplerProvider
        self.quotaChecker = quotaChecker
        self.telemetryController = telemetryController
        self.profilingConditions = profilingConditions
        self.encoder = encoder
        self.dateProvider = dateProvider
        self.windowStart = dateProvider.now
        self.isGraceAvailable = profilingSamplerProvider.isMemoryProfilingConfigured
            && profilingSamplerProvider.memoryProfilingSampled == nil

        // Adopt any interception already installed pre-`main` by the native load-time constructor
        // (`dd_profiler_auto_start`), which starts memory sampling during app launch — before
        // `Profiling.enable()` runs — so the launch window is covered. Seeding the running flag from
        // the live native state lets the reconciliation below either keep that sampler running (this
        // launch re-enabled memory) or tear it down (this launch disabled memory), without a
        // table-clearing restart that would drop the launch-window live set.
        isRecording = dd_memory_profiler_is_running()

        // Memory profiling runs on its own RUM-composed session decision, independent of the
        // continuous/custom CPU state machine. Reconcile it here — as early as possible, optimistically
        // during the launch grace — so the first window covers app launch; it is reconciled again
        // (started/stopped) as the decision and foreground/background conditions change.
        updateState()
    }

    deinit {
        if profilingSamplerProvider.isMemoryProfilingConfigured {
            stopInterception()
        }
    }
}

// MARK: - Coordinator interface

internal extension MemoryProfiler {
    /// Whether the periodic emission timer should be kept alive for memory profiling.
    ///
    /// Recording is passive and continues regardless of conditions (see `shouldRecord()`), but
    /// uploading costs battery, so the timer stays gated on the full `ProfilingConditions` set.
    /// Keying it off the recording gate instead would leave it firing every interval while
    /// backgrounded — flushing a null CPU profile and emitting profile-absence telemetry for
    /// windows that were never going to upload.
    ///
    /// Allocations observed while the timer is held off are not lost: they accumulate in the native
    /// alloc window (capture-and-reset, drained only when a profile is actually emitted) and are
    /// attributed to the first window that does emit. The bounded recorder drops new allocation
    /// records at capacity; live-set admission remains independent.
    var shouldEmitPeriodicProfile: Bool {
        shouldRecord() && hasConditionsToProfile
    }

    /// Whether the window currently being closed may still carry a heap snapshot.
    ///
    /// Not `shouldEmitPeriodicProfile`: the flush triggered by the background transition is what
    /// closes out the foreground window, and `hasConditionsToProfile` has already flipped false by
    /// the time it runs — gating on it alone would drop that window's heap. Since recording
    /// continues in the background, the latch instead allows exactly one emission once conditions
    /// are lost and none until they return, so no later flush re-uploads the same live set and
    /// double-counts the memory in the product.
    var canEmitSnapshot: Bool {
        hasConditionsToProfile || !hasEmittedSinceConditionsLost
    }

    /// Applies the parts of a context update that memory profiling owns.
    ///
    /// Must be called on the shared queue, and **before** the coordinator runs its CPU state
    /// machine for this context: a background transition drives an emission from inside
    /// `updateProfilerState`, and that emission consults `canEmitSnapshot`, which is only correct
    /// once the new conditions have landed here. Interception is reconciled separately, by
    /// `updateState()`, which the coordinator calls at the end of the same update.
    func update(context: DatadogContext) {
        isTrackingConsentAllowed = context.trackingConsent != .notGranted
        hasConditionsToProfile = profilingConditions.canProfileApplication(with: context)

        // Re-arm the closing heap emission only on a genuine return to use. `.active` is required
        // rather than merely `hasConditionsToProfile`: `ProfilingConditions` does not treat
        // `.inactive` as a blocker, so `background → inactive → background` — the user starting to
        // foreground the app and abandoning it — would otherwise re-arm mid-flicker and upload the
        // same live set twice.
        if hasConditionsToProfile, context.applicationStateHistory.currentState == .active {
            hasEmittedSinceConditionsLost = false
        }

        // Consume the launch grace once the RUM memory decision is definitive.
        if profilingSamplerProvider.memoryProfilingSampled != nil {
            isGraceAvailable = false
        }
    }

    func update(serverTimeOffset: TimeInterval) {
        currentServerTimeOffset = serverTimeOffset
    }

    func update(attributes: [AttributeKey: AttributeValue]) {
        guard isRecording else {
            return
        }
        self.attributes = attributes
    }

    func record(vital: Vital) {
        guard isRecording else {
            return
        }
        vitals[vital.key] = vital
    }

    /// Closes an operation this window is tracking, stamping its duration against the start
    /// *memory* recorded. That start can differ from the CPU machine's, which clears on its own
    /// schedule — so the duration is computed here rather than taken from the coordinator.
    func recordOperationEnd(_ operation: Vital) {
        guard isRecording else {
            return
        }
        guard var vital = vitals[operation.key] else {
            return
        }
        vital.duration = operation.date.timeIntervalSince(vital.date).dd.toInt64Nanoseconds
        vitals[operation.key] = vital
    }

    func record(hang: DurationEvent) {
        guard isRecording else {
            return
        }
        hangs.append(hang)
    }

    func record(longTask: DurationEvent) {
        guard isRecording else {
            return
        }
        longTasks.append(longTask)
    }

    func record(warning: DurationEvent) {
        guard isRecording else {
            return
        }
        warnings.append(warning)
    }

    /// Memory warnings awaiting a profile to correlate on.
    ///
    /// Unlike vitals, hangs and long tasks, a memory warning is recorded *only* here — the CPU
    /// state machine never sees one. So when the coupled path is the emitter for this window it
    /// must carry these, or the warning is lost outright.
    var pendingWarnings: [DurationEvent] {
        warnings
    }

    /// Adds pending heap correlation to the current CPU window, preserving CPU values for matching IDs.
    func correlation(
        merging cpuVitals: [Vital],
        hangs cpuHangs: [DurationEvent],
        longTasks cpuLongTasks: [DurationEvent]
    ) -> (vitals: [Vital], hangs: [DurationEvent], longTasks: [DurationEvent], warnings: [DurationEvent]) {
        (
            vitals: appendingMissing(cpuVitals, from: Array(vitals.values), identifiedBy: \.id),
            hangs: appendingMissing(cpuHangs, from: hangs, identifiedBy: \.id),
            longTasks: appendingMissing(cpuLongTasks, from: longTasks, identifiedBy: \.id),
            warnings: warnings
        )
    }

    /// Reconciles the interception state with `shouldRecord()`, starting or stopping only on an
    /// actual transition. Safe to call repeatedly.
    func updateState() {
        let shouldRun = shouldRecord()
        if shouldRun, !isRecording {
            guard startInterception() else {
                // Fail closed if the native owner cannot install the complete allocation lifecycle.
                // Latch the failure so context updates do not retry or repeat telemetry.
                hasInterceptionFailed = true
                stopInterception()
                return
            }
            isRecording = true
            // A start from a stopped state creates a fresh native generation, which
            // clears the sample table and the alloc window, so this window's data begins now.
            // Without advancing, a restart after a quota rejection would keep a `windowStart` from
            // before the rejection and claim to cover a span it holds no samples for.
            //
            // Launch adoption does not reach here: `isRecording` is seeded from
            // `dd_memory_profiler_is_running()`, so an already-running pre-`main` sampler takes no
            // start branch and keeps its original window start.
            windowStart = dateProvider.now
            didDrainAllocationWindow = false
        } else if !shouldRun, isRecording {
            stopInterception()
            isRecording = false
            didDrainAllocationWindow = false
            vitals.removeAll()
            hangs.removeAll()
            longTasks.removeAll()
            warnings.removeAll()
            attributes = [:]
        }
    }

    /// Emits the heap-only profile for this window — used when memory profiling is active but there
    /// is no writable CPU/wall profile. Must be called on the shared queue.
    ///
    /// `operation` is supplied per call rather than stored: the coordinator decides it, and it can
    /// change during the very context update that drives this emission.
    func emitPeriodicHeapProfile(end: Date, operation: ProfilingOperation) {
        let didEmit = writeHeapOnlyProfile(
            start: windowStart,
            end: end,
            operation: operation,
            rumVitals: Array(vitals.values),
            hangs: hangs,
            longTasks: longTasks,
            errors: warnings
        )
        advanceWindow(to: end)
        if didEmit {
            recordEmission(at: end)
        }
    }

    /// Captures a heap snapshot for a RUM event of interest, outside the periodic cadence.
    ///
    /// Deliberately never touches the periodic timer — `DatadogProfiler` owns it. An event snapshot
    /// captures the live set without draining the allocation window or moving its start. The next
    /// periodic emission retains the full delta and duration.
    ///
    /// Must be called on the shared queue.
    func trigger(_ trigger: HeapSnapshotTrigger, operation: ProfilingOperation) {
        guard isRecording, canEmitSnapshot else {
            return
        }
        let now = dateProvider.now
        if let lastEmission, now.timeIntervalSince(lastEmission) < Constants.minHeapEmissionInterval {
            // Folded. The correlation for this event is already recorded, so it still reaches the
            // product on the next emission — it just does not get an upload of its own.
            return
        }

        let didEmit = writeHeapOnlyProfile(
            start: windowStart,
            end: now,
            operation: operation,
            rumVitals: Array(vitals.values),
            trigger: trigger,
            hangs: hangs,
            longTasks: longTasks,
            errors: warnings
        )
        // The window start deliberately does NOT move: this snapshot took no delta, so the
        // periodic profile must still claim the full span its `alloc_*` covers. Correlation is
        // consumed only once something reported it.
        if didEmit {
            recordEmission(at: now)
        }
    }

    /// Advances the window start only after a successful draining capture. A failed capture retains
    /// allocation records and their original start; an empty capture or later encoding failure still
    /// ends the allocation window if the native drain succeeded.
    func advanceWindow(to date: Date) {
        guard didDrainAllocationWindow else {
            return
        }
        didDrainAllocationWindow = false
        windowStart = date
    }

    /// Records that a profile carrying this window's heap was actually written: stamps the
    /// emission cooldown, spends the one emission allowed while conditions are lost, and (unless
    /// the caller opts out) consumes the correlation that profile reported.
    ///
    /// Only call this when an event reached the writer. A capture that produced no bytes, or a
    /// profile dropped by a size guard, reported nothing — consuming the correlation there would
    /// discard a hang or memory warning that no profile ever carried.
    ///
    /// Ongoing operations carry forward the way the CPU machine's `cleanUpState` does: an
    /// operation still running spans this window and the next, so it correlates with both.
    func recordEmission(at date: Date, consumingCorrelation: Bool = true) {
        lastEmission = date

        if !hasConditionsToProfile {
            hasEmittedSinceConditionsLost = true
        }

        guard consumingCorrelation else {
            return
        }
        vitals = vitals.ongoingOperations()
        hangs.removeAll()
        longTasks.removeAll()
        warnings.removeAll()
    }
}

// MARK: - Heap capture

extension MemoryProfiler {
    /// Captures the heap snapshot only if it fits alongside the other serialized attachments.
    /// Returns `nil` when there is nothing to attach or no room.
    ///
    /// The budget is shared, not per-attachment. All attachments travel in one `ProfileAttachments`
    /// metadata block, which the core writer caps at `performance.maxObjectSize`; `Data` fields are
    /// JSON-encoded as base64, so the encoded block is ~4/3 of the raw bytes. Exceeding the cap does
    /// not fail loudly — `FileWriter` logs, writes the event *without* its metadata, and the upload
    /// is then rejected for missing metadata, all while the caller has already reported a
    /// successful profile. Keeping the raw total inside `maxObjectSize` keeps the encoded block
    /// inside the writer's larger limit with room to spare.
    ///
    /// When the heap does not fit, the CPU profile is still written: the heap is the supplementary
    /// attachment, so dropping it preserves the more valuable payload rather than losing both.
    func heapAttachment(
        fittingAlongside otherAttachmentsSize: Int,
        attributes: [AttributeKey: AttributeValue],
        operation: ProfilingOperation,
        drainingAllocWindow: Bool
    ) -> Data? {
        guard let heapPprof = captureHeapPprof(attributes: attributes, drainingAllocWindow: drainingAllocWindow) else {
            return nil
        }
        let budget = Int(ProfilerFeature.Constants.maxObjectSize)
        guard otherAttachmentsSize + heapPprof.count <= budget else {
            telemetryController.sendProfileDropped(for: operation, reason: .profileTooLarge)
            return nil
        }
        return heapPprof
    }
}

// MARK: - Interception lifecycle

private extension MemoryProfiler {
    /// Whether memory (heap) profiling should currently be sampling — independent of the
    /// continuous/custom CPU decision, and deliberately NOT gated on `hasConditionsToProfile`.
    ///
    /// Unlike the CPU profiler — whose sampling thread actively burns CPU and must stop in
    /// background / Low Power / low battery — allocation interception is passive: a Poisson-sampled
    /// table write on allocations the app makes anyway, costing nothing while the process is
    /// suspended. Recording therefore continues through every environmental condition, and
    /// `shouldEmitPeriodicProfile` gates the part that does cost battery: the upload.
    ///
    /// That is also what preserves the live set. A stop followed by a start takes the native
    /// new-generation path, which clears the sample table — so a background round-trip used
    /// to erase every long-lived object, i.e. precisely the objects `inuse_*` exists to surface.
    /// The conditions that DO stop memory profiling (consent revoked, sampled out, install failure,
    /// quota rejection) are ones where clearing is the correct semantics, so no window ever ships
    /// with a silent hole in it.
    ///
    /// Consent is checked here — not only by the CPU machine — because memory profiling has its own
    /// lifecycle: `.notGranted` must disable allocation observation, not merely stop the CPU
    /// profiler.
    func shouldRecord() -> Bool {
        guard isTrackingConsentAllowed,
              !hasInterceptionFailed,
              profilingSamplerProvider.isMemoryProfilingConfigured,
              !quotaChecker.isRejectedByQuota else {
            return false
        }
        switch profilingSamplerProvider.memoryProfilingSampled {
        case .some(true):
            return true
        case .some(false):
            return false
        case .none: // Waiting for the RUM decision — run optimistically during the launch grace.
            return isGraceAvailable
        }
    }

    /// Starts the native owner, which connects both reviewed interception paths to the recorder.
    func startInterception() -> Bool {
        guard dd_memory_profiler_start() else {
            telemetryController.sendMemoryInterceptionInstallFailure(path: "allocation observers", status: "unavailable")
            return false
        }
        return true
    }

    func stopInterception() {
        // The native owner drains callbacks before stopping the recorder. Installed trampolines
        // keep forwarding to the implementations captured at installation.
        dd_memory_profiler_stop()
    }

    /// Captures a live-heap snapshot on the profiling queue and serializes it to `heap.pprof`
    /// bytes, tagged with the current RUM correlation IDs. Returns `nil` when there are no live
    /// heap samples this period (nothing to attach).
    ///
    /// RUM correlation IDs are attached as per-sample string labels (Go-aligned keys:
    /// `session_id`, `view_id`, `application_id`). All samples in the snapshot carry the same
    /// values because it is a point-in-time capture (documented approximation).
    ///
    /// `view.id` is stored in the attributes dictionary as `[String]` (the RUM SDK wraps it in
    /// an array); we take the first element as the label value.
    func captureHeapPprof(
        attributes: [AttributeKey: AttributeValue],
        drainingAllocWindow: Bool
    ) -> Data? {
        // A periodic capture drains alloc_* and snapshots inuse_* at the same boundary. A
        // trigger captures only the live set and leaves periodic allocation totals untouched.
        didDrainAllocationWindow = false
        var aggregates = dd_memory_aggregation_view_t()
        guard dd_memory_profiler_capture(drainingAllocWindow, &aggregates) else {
            return nil
        }
        didDrainAllocationWindow = drainingAllocWindow

        // Extract RUM correlation IDs from attributes using the same keys the wall
        // profiling path receives from the RUM feature message.
        // `view.id` is sent by the RUM SDK as [String] (array); take the first element.
        let sessionID     = attributes[RUMCoreContext.IDs.sessionID]     as? String
        let viewID        = (attributes[RUMCoreContext.IDs.viewID] as? [String])?.first
        let applicationID = attributes[RUMCoreContext.IDs.applicationID] as? String

        var raw: UnsafeMutablePointer<UInt8>? = nil
        // Pass each ID as a C string only when non-nil; the converter treats NULL and
        // empty-string identically (omits the label), so we pass NULL for absent IDs.
        let size = withOptionalCString(sessionID) { sidPtr in
            withOptionalCString(viewID) { vidPtr in
                withOptionalCString(applicationID) { aidPtr in
                    dd_memory_aggregates_to_pprof(&aggregates, sidPtr, vidPtr, aidPtr, &raw)
                }
            }
        }

        guard size > 0, let raw else {
            // No heap samples this period (neither live set nor window allocations)
            // — nothing to attach.
            return nil
        }

        let heapData = Data(bytes: raw, count: Int(size))
        free(raw)
        return heapData
    }
}

// MARK: - Dictionary Helpers

private extension Dictionary where Key == String, Value == Vital {
    func ongoingOperations() -> [String: Vital] {
        filter { $0.value.stepType == .start && $0.value.duration == nil }
    }
}

/// Appends pending events absent from the current window without replacing its event values.
private func appendingMissing<Event>(
    _ current: [Event],
    from pending: [Event],
    identifiedBy id: KeyPath<Event, String>
) -> [Event] {
    var result = current
    var seenIDs = Set(current.lazy.map { $0[keyPath: id] })
    for event in pending where seenIDs.insert(event[keyPath: id]).inserted {
        result.append(event)
    }
    return result
}

/// Calls `body` with a `UnsafePointer<CChar>?` for the given optional String.
/// Passes `nil` when `string` is `nil`; otherwise bridges via `withCString`.
/// This avoids duplicate `withCString` nesting with sentinel empty strings.
private func withOptionalCString<R>(
    _ string: String?,
    body: (UnsafePointer<CChar>?) -> R
) -> R {
    guard let string else {
        return body(nil)
    }
    return string.withCString { body($0) }
}

#endif
