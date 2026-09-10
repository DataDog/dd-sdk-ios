/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS)

// swiftlint:disable duplicate_imports
#if swift(>=6.0)
internal import DatadogMachProfiler
#else
@_implementationOnly import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

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
    /// CPU profile to source timestamps from). Advanced on each emission.
    private var windowStart: Date
    /// Whether memory interception is currently installed. Tracked so reconciliation only calls
    /// start/stop on an actual state change.
    private(set) var isRecording = false
    /// Latched once neither interception path could install. Memory profiling then stays off for
    /// the lifetime of this profiler — the failure (a sample table that could not be allocated, or
    /// both hook targets unresolvable) is not transient, so retrying each context update would only
    /// repeat the telemetry.
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
        encoder: JSONEncoder = JSONEncoder(),
        dateProvider: DateProvider
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
    /// attributed to the first window that does emit. A long accumulation widens the sampling
    /// interval under back-pressure rather than dropping samples.
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
        self.attributes = attributes
    }

    func record(vital: Vital) {
        vitals[vital.key] = vital
    }

    /// Closes an operation this window is tracking, stamping its duration against the start
    /// *memory* recorded. That start can differ from the CPU machine's, which clears on its own
    /// schedule — so the duration is computed here rather than taken from the coordinator.
    func recordOperationEnd(_ operation: Vital) {
        guard var vital = vitals[operation.key] else {
            return
        }
        vital.duration = operation.date.timeIntervalSince(vital.date).dd.toInt64Nanoseconds
        vitals[operation.key] = vital
    }

    func record(hang: DurationEvent) {
        hangs.append(hang)
    }

    func record(longTask: DurationEvent) {
        longTasks.append(longTask)
    }

    func record(warning: DurationEvent) {
        warnings.append(warning)
    }

    /// Reconciles the interception state with `shouldRecord()`, starting or stopping only on an
    /// actual transition. Safe to call repeatedly.
    func updateState() {
        let shouldRun = shouldRecord()
        if shouldRun, !isRecording {
            guard startInterception() else {
                // Neither path installed — fail closed rather than report a running profiler that
                // can never produce a sample. Latched so the next context update does not retry a
                // failure that is not transient (and re-emit its telemetry every cycle).
                hasInterceptionFailed = true
                stopInterception()
                return
            }
            isRecording = true
            // A start from a stopped state takes the native `start_new_session()` path, which
            // clears the sample table and the alloc window, so this window's data begins now.
            // Without advancing, a restart after a quota rejection would keep a `windowStart` from
            // before the rejection and claim to cover a span it holds no samples for.
            //
            // Launch adoption does not reach here: `isRecording` is seeded from
            // `dd_memory_profiler_is_running()`, so an already-running pre-`main` sampler takes no
            // start branch and keeps its original window start.
            windowStart = dateProvider.now
        } else if !shouldRun, isRecording {
            stopInterception()
            isRecording = false
        }
    }

    /// Emits the heap-only profile for this window — used when memory profiling is active but there
    /// is no writable CPU/wall profile. Must be called on the shared queue.
    ///
    /// `operation` is supplied per call rather than stored: the coordinator decides it, and it can
    /// change during the very context update that drives this emission.
    func emitPeriodicHeapProfile(end: Date, operation: ProfilingOperation) {
        writeHeapOnlyProfile(
            start: windowStart,
            end: end,
            operation: operation,
            rumVitals: Array(vitals.values),
            hangs: hangs,
            longTasks: longTasks,
            errors: warnings
        )
    }

    /// Captures a heap snapshot for a RUM event of interest, outside the periodic cadence.
    ///
    /// Deliberately never touches the periodic timer — `DatadogProfiler` owns it. An event snapshot
    /// only closes the current memory window early; the next periodic emission still fires on
    /// schedule, carrying a shorter window. `alloc_*` stays correct because the window reports its
    /// true duration, and `inuse_*` is a point-in-time view either way.
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

        writeHeapOnlyProfile(
            start: windowStart,
            end: now,
            operation: operation,
            trigger: trigger,
            rumVitals: Array(vitals.values),
            hangs: hangs,
            longTasks: longTasks,
            errors: warnings
        )
        closeWindow(at: now)
    }

    /// Ends the current window: advances its start, clears the correlation it reported, stamps the
    /// emission cooldown, and spends the one emission allowed while conditions are lost.
    ///
    /// Called once per window the coordinator closes — whether or not the capture produced bytes.
    /// A window whose live set and alloc window were both empty still *happened*, and the native
    /// alloc window was drained by the attempt, so the next window must start from here.
    ///
    /// Ongoing operations carry forward the way the CPU machine's `cleanUpState` does: an operation
    /// still running spans this window and the next, so it correlates with both.
    func closeWindow(at date: Date) {
        advanceWindow(to: date)
        // Stamped for every closed window, periodic or triggered, so a trigger arriving right
        // behind a periodic emission is folded rather than uploading the same live set again.
        lastEmission = date
        vitals = vitals.ongoingOperations()
        hangs.removeAll()
        longTasks.removeAll()
        warnings.removeAll()

        if !hasConditionsToProfile {
            hasEmittedSinceConditionsLost = true
        }
    }

    /// Moves the window start without touching correlation or the conditions latch.
    ///
    /// Used by the app-launch harvest, which reports the launch window on the CPU event but leaves
    /// the accumulated correlation in place for the windows that follow.
    func advanceWindow(to date: Date) {
        windowStart = date
    }
}

// MARK: - Heap capture

extension MemoryProfiler {
    /// Captures the heap snapshot for a coupled event, but only if it fits in what the CPU profile
    /// leaves of the attachment budget. Returns `nil` when there is nothing to attach or no room.
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
        fittingAlongside cpuProfileSize: Int,
        attributes: [AttributeKey: AttributeValue],
        operation: ProfilingOperation
    ) -> Data? {
        guard let heapPprof = captureHeapPprof(attributes: attributes) else {
            return nil
        }
        let budget = Int(ProfilerFeature.Constants.maxObjectSize)
        guard cpuProfileSize + heapPprof.count <= budget else {
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
    /// `start_new_session()` path, which clears the sample table — so a background round-trip used
    /// to erase every long-lived object, i.e. precisely the objects `inuse_*` exists to surface.
    /// The conditions that DO stop memory profiling (consent revoked, sampled out, install failure,
    /// quota rejection) are ones where clearing is the correct semantics, so no window ever ships
    /// with a silent hole in it.
    ///
    /// Consent is checked here — not only by the CPU machine — because memory profiling has its own
    /// lifecycle: `.notGranted` must uninstall the interception outright, not merely stop the CPU
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

    /// Installs both interception paths.
    ///
    /// - Returns: `true` when at least one path is observing. A single-path failure still returns
    ///   `true`: the surviving path yields real (if narrower) attribution, and the failure is
    ///   reported via telemetry. Only a total failure — typically the shared sampler failing to
    ///   start, which takes both paths down — returns `false`, so the caller can fail closed rather
    ///   than emit windows that can never contain a sample.
    func startInterception() -> Bool {
        // Passive profiler start (allocates sample table, initialises Poisson sampler, flips
        // the enabled flag) MUST precede the swizzle installation so that allocations observed
        // by the +allocWithZone: trampoline have a live sample table to write into.
        // dd_objc_alloc_hook_start internally calls dd_memory_profiler_start_passive and
        // installs the swizzle in the correct order, so a single call is sufficient.
        let objcStatus = ObjCAllocInterception.start(poissonRateBytes: ObjCAllocInterception.defaultPoissonRateBytes)
        if !objcStatus.isInstalled {
            telemetryController.sendMemoryInterceptionInstallFailure(path: "Obj-C +allocWithZone:", status: "\(objcStatus)")
        }

        // Dual interception: also intercept pure-Swift class allocations
        // (swift_allocObject), which bypass the Obj-C +allocWithZone: swizzle.
        // start() joins the same passive sampler (idempotent start_passive), so
        // both paths feed one shared sampler / live-set / encoder. Samples are
        // tagged source=swift and unioned with the Obj-C path (disjoint, no
        // double-count).
        let swiftStatus = SwiftAllocInterception.start(poissonRateBytes: SwiftAllocInterception.defaultPoissonRateBytes)
        if !swiftStatus.isInstalled {
            telemetryController.sendMemoryInterceptionInstallFailure(path: "swift_allocObject", status: "\(swiftStatus)")
        }

        return objcStatus.isInstalled || swiftStatus.isInstalled
    }

    func stopInterception() {
        // Never-restore: the +allocWithZone: / -dealloc trampolines stay installed and keep
        // forwarding; dd_objc_alloc_hook_stop only clears the observing flag and disables the
        // sampler. Safe to call even when not running.
        ObjCAllocInterception.stop()
        // Stop recording pure-Swift allocations. Never-restore: the rebound
        // trampolines stay installed and keep forwarding; they simply stop
        // observing. Safe to call even when not running.
        SwiftAllocInterception.stop()
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
    func captureHeapPprof(attributes: [AttributeKey: AttributeValue]) -> Data? {
        // Live set (inuse_*) — a point-in-time view, never reset.
        var snapshot = dd_memory_snapshot_capture()
        defer { dd_memory_snapshot_destroy(&snapshot) }

        // This window's sampled allocations (alloc_*) — captured-and-reset so the
        // next window accumulates fresh. Independent of the live set: transient
        // objects allocated and freed within the window show up here but not in
        // `snapshot`, which is what makes alloc_* diverge from inuse_*.
        var allocWindow = dd_memory_alloc_window_capture()
        defer { dd_memory_snapshot_destroy(&allocWindow) }

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
                    dd_memory_snapshots_to_pprof(&snapshot, &allocWindow, sidPtr, vidPtr, aidPtr, &raw)
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

/// Calls `body` with a `UnsafePointer<CChar>?` for the given optional String.
/// Passes `nil` when `string` is `nil`; otherwise bridges via `withCString`.
/// This avoids duplicate `withCString` nesting with sentinel empty strings.
private func withOptionalCString<R>(
    _ string: String?,
    body: (UnsafePointer<CChar>?) -> R
) -> R {
    guard let string else { return body(nil) }
    return string.withCString { body($0) }
}

#endif
