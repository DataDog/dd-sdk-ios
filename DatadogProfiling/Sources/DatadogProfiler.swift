/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@preconcurrency import DatadogInternal

#if !os(watchOS)

// Keep this implementation-only. Otherwise, Swift 6 records DatadogMachProfiler as a
// transitive module dependency, but it is not distributed as an XCFramework.
@_implementationOnly import DatadogMachProfiler

internal final class DatadogProfiler: ProfilingHandler, @unchecked Sendable {
    enum Constants {
        /// Default profile duration during continuous profiling.
        static let maxProfileDuration: TimeInterval = 60 // 1 minute profiles
        /// Minimum profile duration during continuous profiling.
        static let minProfileDuration: TimeInterval = 5 // 5 seconds profiles
        /// Maximum time to keep profiling alive while waiting for RUM events.
        static let cutOffTime: TimeInterval = 60 // 1 minute cutoff
    }

    static let defaultQueue = DispatchQueue(
        label: "com.datadoghq.datadog-profiler",
        qos: .utility
    )

    /// The queue used to synchronize the profiling data and the writes.
    private let queue: DispatchQueue
    private let profilingSamplerProvider: ProfilingSamplerProvider
    private let quotaChecker: ProfilingQuotaChecking
    private let profilingConditions: ProfilingConditions
    private let profilingInterval: TimeInterval
    private let minProfileDuration: TimeInterval
    /// Whether the native profiler started at process launch and the latest configuration permits harvesting it.
    private let hasAppLaunchProfileToHarvest: Bool
    private var timer: DispatchSourceTimer?

    let featureScope: FeatureScope
    let telemetryController: ProfilingTelemetryController
    let encoder: JSONEncoder
    let dateProvider: DateProvider

    private var lastProfilingContext: ProfilingContext?

    @ReadWriteLock
    private(set) var attributes: [String: AttributeValue] = [:]
    /// Whether TTID has been received.
    @ReadWriteLock
    private var hasReceivedAppLaunchVital = false
    /// Whether TTID has reached the profiler queue.
    private var hasProcessedAppLaunchVital = false
    // Interval between device and server time.
    @ReadWriteLock
    private(set) var currentServerTimeOffset: TimeInterval = .zero
    // Ongoing RUM Operations to attach to profiles.
    private var currentRUMVitals: [String: Vital] = [:]
    // App hangs to attach to profiles.
    private var hangs: [DurationEvent] = []
    // Long tasks to attach to profiles.
    private var longTasks: [DurationEvent] = []
    /// Start of the current native profile cycle.
    private var profileStartDate: Date
    private var hasConditionsToProfile = true
    /// Whether this profiler instance may collect RUM-linked profiling data.
    /// Consent remains fail-open while `.pending`; only `.notGranted` disables collection.
    private var isTrackingConsentAllowed = true
    private var previousAppState: AppState?
    /// Current RUM session.
    private var currentRUMSessionID: String?
    // Current profiling mode
    private(set) var operation: ProfilingOperation
    /// Allows continuous profiling to temporarily run while waiting for the first
    /// RUM-linked sampling decision. The grace is consumed when a definitive decision
    /// arrives, on the first timer cycle, or when the app backgrounds before a decision
    /// is received.
    private var isContinuousProfilingGraceAvailable: Bool
    /// Mirrors `isContinuousProfilingGraceAvailable` for memory profiling: lets the sampler run
    /// optimistically at launch (before the RUM memory sampling decision arrives) so the first
    /// window covers app launch. Consumed once a definitive memory decision is received.
    private var isMemoryProfilingGraceAvailable: Bool
    /// Whether memory interception is currently enabled. Tracked so reconciliation only calls
    /// start/stop on an actual state change.
    private var isMemoryProfilingRunning = false
    /// Latched once neither interception path could install. Memory profiling then stays off for
    /// the lifetime of this profiler — the failure (a sample table that could not be allocated, or
    /// both hook targets unresolvable) is not transient, so retrying each context update would only
    /// repeat the telemetry.
    private var hasMemoryInterceptionFailed = false
    /// Start of the current memory-profiling emission window, used to bound a heap-only
    /// `ProfileEvent` (which has no CPU profile to source timestamps from). Advanced on each emission.
    private var memoryWindowStart: Date
    /// Tracks profiler stops caused by quota rejection so a later session quota reset can
    /// restart profiling without waiting for an unrelated app-state or condition change.
    private var isStoppedByQuota = false
    /// Whether the heap has already been emitted since profiling conditions were last lost.
    /// Memory keeps recording in the background, so without this latch every flush arriving while
    /// conditions are blocked would upload the same live set again as a fresh profile.
    /// Re-armed on a genuine return to use (conditions restored and the app `.active`).
    private var hasEmittedHeapSinceConditionsLost = false

    init(
        core: DatadogCoreProtocol,
        profilingSamplerProvider: ProfilingSamplerProvider,
        quotaChecker: ProfilingQuotaChecking,
        queue: DispatchQueue = DatadogProfiler.defaultQueue,
        telemetryController: ProfilingTelemetryController = .init(),
        profilingConditions: ProfilingConditions = .init(),
        profilingInterval: TimeInterval = Constants.maxProfileDuration,
        minProfileDuration: TimeInterval = Constants.minProfileDuration,
        isAppLaunchProfilingEnabled: Bool = false,
        encoder: JSONEncoder = JSONEncoder(),
        dateProvider: DateProvider = SystemDateProvider()
    ) {
        self.featureScope = core.scope(for: ProfilerFeature.self)
        self.queue = queue
        self.profilingSamplerProvider = profilingSamplerProvider
        self.quotaChecker = quotaChecker
        self.telemetryController = telemetryController
        self.profilingConditions = profilingConditions
        self.profilingInterval = profilingInterval
        self.minProfileDuration = minProfileDuration
        self.hasAppLaunchProfileToHarvest = isAppLaunchProfilingEnabled && dd_profiler_was_started_at_launch()
        self.encoder = encoder
        self.dateProvider = dateProvider
        self.profileStartDate = dateProvider.now
        self.memoryWindowStart = dateProvider.now
        self.operation = profilingSamplerProvider.isContinuousProfilingConfigured ? .continuousProfiling : .customProfiling
        self.isContinuousProfilingGraceAvailable = profilingSamplerProvider.isContinuousProfilingConfigured
            && profilingSamplerProvider.continuousProfilingSampled == nil
        self.isMemoryProfilingGraceAvailable = profilingSamplerProvider.isMemoryProfilingConfigured
            && profilingSamplerProvider.memoryProfilingSampled == nil

        quotaChecker.onQuotaResultUpdate = { [weak self] result in
            self?.handle(quotaResult: result)
        }

        // Adopt any interception already installed pre-`main` by the native load-time constructor
        // (`dd_profiler_auto_start`), which starts memory sampling during app launch — before
        // `Profiling.enable()` runs — so the launch window is covered. Seeding the running flag from
        // the live native state lets the reconciliation below either keep that sampler running (this
        // launch re-enabled memory) or tear it down (this launch disabled memory), without a
        // table-clearing restart that would drop the launch-window live set.
        isMemoryProfilingRunning = dd_memory_profiler_is_running()

        // Memory profiling runs on its own RUM-composed session decision, independent of the
        // continuous/custom CPU state machine. Reconcile it here — as early as possible, optimistically
        // during the launch grace — so the first window covers app launch; it is reconciled again
        // (started/stopped) as the decision and foreground/background conditions change.
        updateMemoryProfilingState()

        // The emission timer runs when EITHER continuous CPU profiling or memory profiling is
        // configured, so memory can emit a heap-only profile even when CPU profiling is not running.
        if profilingSamplerProvider.isContinuousProfilingConfigured
            || profilingSamplerProvider.isMemoryProfilingConfigured {
            startTimer()
        }
    }

    deinit {
        stopTimer()

        if profilingSamplerProvider.isMemoryProfilingConfigured {
            stopMemoryProfiling()
        }
    }
}

// MARK: - FeatureMessageReceiver

extension DatadogProfiler: FeatureMessageReceiver {
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case .context(let context):
            handle(context: context)
            return false
        case .payload(let message):
            switch message {
            case let message as TTIDMessage:
                handleAppLaunch(message: message)
                return true
            case let message as OperationMessage:
                handleOperation(message: message)
                // Every OperationMessage is consumed by the active profiler after app launch vital.
                return hasReceivedAppLaunchVital
            case let message as AppHangMessage:
                handleAppHang(message: message)
                return true
            case let message as LongTaskMessage:
                handleLongTask(message: message)
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}

// MARK: - Timer

private extension DatadogProfiler {
    func startTimer() {
        guard self.timer == nil else {
            // reset timer
            fireTimer(after: profilingInterval)
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + profilingInterval, repeating: profilingInterval)
        timer.setEventHandler { [weak self] in
            self?.updateProfilerAndSendProfile()
        }
        timer.resume()
        self.timer = timer
    }

    func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    func fireTimer(after interval: TimeInterval) {
        let delay = dateProvider.now.addingTimeInterval(interval).timeIntervalSinceNow
        timer?.schedule(deadline: .now() + max(0, delay), repeating: profilingInterval)
    }
}

// MARK: - Handle Messages and context

private extension DatadogProfiler {
    func handle(context: DatadogContext) {
        telemetryController.register(context: context)
        currentServerTimeOffset = context.serverTimeOffset
        dd_profiler_set_server_time_offset_ns(context.serverTimeOffset.dd.toInt64Nanoseconds)

        queue.async { [weak self] in
            guard let self else {
                return
            }

            if let sessionID = context.additionalContext(ofType: RUMCoreContext.self)?.sessionID,
               sessionID != currentRUMSessionID {
                currentRUMSessionID = sessionID
                telemetryController.resetContinuousCycleIndex()
            }

            // Memory profiling follows its own decision + conditions, so reconcile it on EVERY
            // context update regardless of the early-returns below — including the consent
            // revocation below, which returns before any continuous-profiling path is reached.
            defer { updateMemoryProfilingState() }

            let wasTrackingConsentAllowed = isTrackingConsentAllowed
            isTrackingConsentAllowed = context.trackingConsent != .notGranted
            if !isTrackingConsentAllowed {
                cleanUpState(preservingOngoingOperations: false)
                updateProfilerState(canProfile: false)
                return
            }

            let previousConditions = hasConditionsToProfile
            hasConditionsToProfile = profilingConditions.canProfileApplication(with: context)
            let currentAppState = context.applicationStateHistory.currentState
            // Re-arm the closing heap emission only on a genuine return to use. `.active` is
            // required rather than merely `hasConditionsToProfile`: `ProfilingConditions` does not
            // treat `.inactive` as a blocker, so `background → inactive → background` — the user
            // starting to foreground the app and abandoning it — would otherwise re-arm
            // mid-flicker and upload the same live set twice.
            if hasConditionsToProfile, currentAppState == .active {
                hasEmittedHeapSinceConditionsLost = false
            }
            defer { previousAppState = currentAppState }

            // Consume the launch grace once the RUM memory decision is definitive.
            if profilingSamplerProvider.memoryProfilingSampled != nil {
                isMemoryProfilingGraceAvailable = false
            }

            switch profilingSamplerProvider.continuousProfilingSampled {
            case true?:
                operation = .continuousProfiling
            case false?:
                operation = .customProfiling

                if currentRUMVitals.isEmpty == false, shouldHarvestAppLaunchProfileOnTTID {
                    stopAndWriteAppLaunchProfile()
                    return
                }

                if isContinuousProfilingGraceAvailable {
                    // The profiler was running optimistically while waiting for the RUM
                    // sampling decision. If that decision samples out continuous profiling,
                    // stop the optimistic profiler unless app-launch profiling still needs
                    // the native profiler to harvest TTID.
                    isContinuousProfilingGraceAvailable = false
                    let canProfile = shouldKeepProfilerRunning()
                    if canProfile || !shouldWaitForAppLaunchVital {
                        updateProfilerState(canProfile: canProfile)
                    }
                    return
                }
            case .none: break
            }

            if currentAppState == .background {
                // Updates the profiler state if the app was or is about to have foreground time
                guard context.applicationStateHistory
                    .containsState(during: context.launchInfo.processLaunchDate...dateProvider.now, where: { $0 == .active }) else {
                    return
                }

                if profilingSamplerProvider.continuousProfilingSampled == nil {
                    isContinuousProfilingGraceAvailable = false
                }

                updateProfilerState(canProfile: shouldKeepProfilerRunning(), shouldSendProfile: true)
            }
            // If the conditions are the same, ignore the update profiler state
            else if currentAppState != previousAppState
                        || hasConditionsToProfile != previousConditions
                        || isTrackingConsentAllowed != wasTrackingConsentAllowed {
                switch ProfilingContext.Status.current {
                case .running, .stopped, .unknown:
                    updateProfilerState(canProfile: shouldKeepProfilerRunning())
                default:
                    break
                }
            }
        }
    }

    func handleOperation(message: OperationMessage) {
        queue.async { [weak self] in
            guard let self, isTrackingConsentAllowed, !quotaChecker.isRejectedByQuota else {
                return
            }
            attributes = message.attributes

            // Capture vitals like TTFD that are not operation steps.
            if message.operation.stepType == nil {
                currentRUMVitals[message.operation.key] = message.operation
            } else if message.operation.stepType == .start {
                currentRUMVitals[message.operation.key] = message.operation
                updateProfilerState(canProfile: shouldKeepProfilerRunning())
            } else if message.operation.stepType == .end {
                if var startVital = currentRUMVitals[message.operation.key] {
                    // Add duration to vital to help Profiling backend label correctly the samples of this vital
                    let duration = message.operation.date.timeIntervalSince(startVital.date)
                    startVital.duration = duration.dd.toInt64Nanoseconds
                    currentRUMVitals[message.operation.key] = startVital

                    if currentRUMVitals.hasCompletedAllOperations(),
                       isCustomProfiling,
                       hasProcessedAppLaunchVital || !shouldWaitForAppLaunchVital {
                        let customProfilingDuration = dateProvider.now.timeIntervalSince(profileStartDate)
                        let fireInterval = customProfilingDuration < minProfileDuration ? minProfileDuration - customProfilingDuration : 0
                        fireTimer(after: fireInterval)
                    }
                }
            }
        }
    }

    func handleAppHang(message: AppHangMessage) {
        queue.async { [weak self] in
            guard let self, isTrackingConsentAllowed, !quotaChecker.isRejectedByQuota else {
                return
            }
            attributes = message.attributes
            hangs.append(message.hang)
        }
    }

    func handleLongTask(message: LongTaskMessage) {
        queue.async { [weak self] in
            guard let self, isTrackingConsentAllowed, !quotaChecker.isRejectedByQuota else {
                return
            }
            attributes = message.attributes
            longTasks.append(message.longTask)
        }
    }

    func updateProfilerAndSendProfile() {
        isContinuousProfilingGraceAvailable = false
        updateProfilerState(canProfile: shouldKeepProfilerRunning(), shouldSendProfile: true)
    }

    /// Updates the native profiler lifecycle.
    /// `canProfile` must already account for tracking consent, quota, and runtime conditions.
    /// Profiles stopped without being sent are discarded.
    func updateProfilerState(canProfile: Bool, shouldSendProfile: Bool = false) {
        if !canProfile, !shouldEmitMemoryProfile {
            // Only stop the timer if memory profiling doesn't still need it (heap-only emission).
            stopTimer()
        }

        var currentStatus = ProfilingContext.Status.current
        if currentStatus == .running && !canProfile {
            dd_profiler_stop()
            currentStatus = ProfilingContext.Status.current
        }

        let hasTimedOut = currentStatus == .stopped(reason: .timeout)
        let shouldSendCurrentProfile = shouldSendProfile || (hasTimedOut && canProfile && !isCustomProfiling)
        if shouldSendCurrentProfile {
            sendProfile()
        } else if !canProfile && !shouldWaitForAppLaunchVital {
            discardCurrentProfile()
            cleanUpState()
        }

        if hasTimedOut && shouldSendCurrentProfile {
            // Join the finished native threads after harvesting the timed-out profile.
            dd_profiler_stop()
            currentStatus = ProfilingContext.Status.current
        }

        switch currentStatus {
        case .stopped, .unknown: // When `.unknown` status, mostly profiler NOT_CREATED, it will try to start the profiler
            if isCustomProfiling {
                cleanUpState(preservingOngoingOperations: false)
            } else if canProfile {
                dd_profiler_start()
                profileStartDate = dateProvider.now
                startTimer()
            }
            // Memory can emit even when the CPU profiler isn't started (e.g. continuous sampled
            // out): keep the timer alive so a heap-only profile is uploaded on the window boundary.
            if timer == nil, shouldEmitMemoryProfile {
                startTimer()
            }
        case .running:
            if canProfile, timer == nil {
                startTimer()
            }
        default: break
        }

        updateProfilingContext(quotaReason: quotaChecker.isRejectedByQuota ? quotaChecker.quotaResult?.reason : nil)
    }

    func sendProfile() {
        let windowStart = memoryWindowStart
        let windowEnd = dateProvider.now
        profileStartDate = windowEnd

        let cpuProfile = dd_profiler_flush_and_get_profile()
        defer { if let cpuProfile { dd_pprof_destroy(cpuProfile) } }

        // Emit the heap snapshot only when memory sampling is active, this window may still emit
        // one (see `canEmitHeapSnapshot`), AND there is a RUM event of interest to correlate with
        // (vital / hang / long task) — the same signal the CPU `canWriteProfile` gate keys off. On a
        // skipped window the snapshot is not taken: the live set is a point-in-time view that
        // carries forward, and the alloc window keeps accumulating (its capture-and-reset lives in
        // `captureHeapPprof`, which we don't call here), so the next emitted window covers the full
        // span. Nothing is lost; write/upload work is saved.
        let wantsHeap = isMemoryProfilingRunning && hasRUMEventsOfInterest && canEmitHeapSnapshot

        if let cpuProfile {
            if canWriteProfile {
                // Coupled path: CPU/wall profile; heap is attached when memory is active.
                write(
                    profile: cpuProfile,
                    operation: operation,
                    rumVitals: Array(self.currentRUMVitals.values),
                    hangs: hangs,
                    longTasks: longTasks,
                    captureHeapProfile: wantsHeap
                )
            } else if wantsHeap {
                // CPU profile isn't writable this window, but memory is active with a correlated
                // event — emit a heap-only profile carrying that event.
                writeHeapOnlyProfile(
                    start: windowStart,
                    end: windowEnd,
                    operation: operation,
                    rumVitals: Array(self.currentRUMVitals.values),
                    hangs: hangs,
                    longTasks: longTasks
                )
            } else if quotaChecker.isRejectedByQuota || shouldReportProfileAbsence {
                telemetryController.sendProfileDropped(for: operation, reason: profileDropReason)
            }
        } else if wantsHeap {
            // No CPU profile at all (CPU profiling not running) — independent heap-only emission
            // carrying the correlated RUM event(s).
            writeHeapOnlyProfile(
                start: windowStart,
                end: windowEnd,
                operation: operation,
                rumVitals: Array(self.currentRUMVitals.values),
                hangs: hangs,
                longTasks: longTasks
            )
        } else if shouldReportProfileAbsence {
            telemetryController.sendNoProfile(for: operation)
        }

        // Advance the memory window only when the heap was actually captured this cycle (the alloc
        // window is reset inside `captureHeapPprof`). Skipped windows leave `memoryWindowStart`
        // untouched so the accumulated allocations are attributed to the next emitted window.
        if wantsHeap {
            memoryWindowStart = windowEnd
            // Spend the one emission allowed while conditions are lost; re-armed in
            // `handle(context:)` on a return to use.
            if !hasConditionsToProfile {
                hasEmittedHeapSinceConditionsLost = true
            }
        }

        cleanUpState()
    }

    func cleanUpState(preservingOngoingOperations: Bool = true) {
        if preservingOngoingOperations, canExtendCustomProfiling() {
            currentRUMVitals = currentRUMVitals.ongoingOperations()
        } else {
            currentRUMVitals.removeAll()
        }
        hangs.removeAll()
        longTasks.removeAll()
    }

    func discardCurrentProfile() {
        guard let profile = dd_profiler_flush_and_get_profile() else {
            return
        }
        dd_pprof_destroy(profile)
    }
}

// MARK: - App launch

private extension DatadogProfiler {
    func handleAppLaunch(message: TTIDMessage) {
        guard hasReceivedAppLaunchVital == false else {
            return
        }
        hasReceivedAppLaunchVital = true
        currentServerTimeOffset = message.ttid.serverTimeOffset
        dd_profiler_set_server_time_offset_ns(message.ttid.serverTimeOffset.dd.toInt64Nanoseconds)

        queue.async { [weak self] in
            guard let self else {
                return
            }
            hasProcessedAppLaunchVital = true

            guard isTrackingConsentAllowed else {
                return
            }
            let shouldHarvestAppLaunchProfile = shouldHarvestAppLaunchProfileOnTTID
            attributes = message.attributes
            currentRUMVitals[message.ttid.key] = message.ttid

            guard !quotaChecker.isRejectedByQuota else {
                cleanUpState(preservingOngoingOperations: false)
                telemetryController.sendProfileDropped(for: .appLaunch, reason: .quotaRejected(quotaChecker.quotaResult?.reason))
                updateProfilerState(canProfile: false)
                return
            }

            if shouldHarvestAppLaunchProfile {
                stopAndWriteAppLaunchProfile()
            } else {
                if shouldKeepProfilerRunning() {
                    updateProfilerState(canProfile: true)
                } else if currentRUMVitals.hasCompletedAllOperations(), isCustomProfiling {
                    let customProfilingDuration = dateProvider.now.timeIntervalSince(profileStartDate)
                    let fireInterval = customProfilingDuration < minProfileDuration ? minProfileDuration - customProfilingDuration : 0
                    fireTimer(after: fireInterval)
                }
            }
        }
    }

    func stopAndWriteAppLaunchProfile() {
        stopTimer()
        // The app-launch harvest stops the CPU profiler and the emission timer. Memory profiling
        // emits independently (heap-only) and can be sampled in even when continuous CPU is sampled
        // out — the only case that reaches this standalone-launch harvest. Restart the timer on every
        // exit path so heap-only windows keep emitting after launch; the CPU profiler is intentionally
        // NOT restarted here.
        defer {
            if timer == nil, shouldEmitMemoryProfile {
                startTimer()
            }
        }
        dd_profiler_stop()
        updateProfilingContext()

        guard let profile = dd_profiler_flush_and_get_profile() else {
            telemetryController.sendNoProfile(for: .appLaunch)
            cleanUpState()
            return
        }

        if hasAppLaunchProfileToHarvest {
            writeAppLaunchProfile(profile)
        }
        cleanUpState()
        dd_pprof_destroy(profile)
    }

    func writeAppLaunchProfile(_ profile: OpaquePointer) {
        // Preserve the existing fail-open behavior while quota is pending:
        // only an explicit quota rejection blocks the app-launch upload.
        guard !quotaChecker.isRejectedByQuota else {
            telemetryController.sendProfileDropped(for: .appLaunch, reason: .quotaRejected(quotaChecker.quotaResult?.reason))
            return
        }

        // When memory profiling is running (its own independent decision — it can be sampled in
        // even when continuous CPU is sampled out), attach the launch heap window to the app-launch
        // profile: `inuse_*` is the live set at TTID and `alloc_*` covers everything allocated since
        // the load-time constructor installed the hooks. This is what puts memory profiling in the
        // app-launch / TTID window. The live set is NOT reset here — capturing the alloc window is
        // capture-and-reset, but the live set carries forward into the continuous windows.
        write(
            profile: profile,
            operation: .appLaunch,
            rumVitals: Array(currentRUMVitals.values),
            hangs: hangs,
            longTasks: longTasks,
            captureHeapProfile: isMemoryProfilingRunning
        )

        if isMemoryProfilingRunning {
            // The launch allocations were just captured (alloc window reset); advance the memory
            // window so a subsequent heap-only emission is bounded from TTID, not from launch.
            memoryWindowStart = dateProvider.now
        }
    }
}

// MARK: - Quota

private extension DatadogProfiler {
    func handle(quotaResult: ProfilingQuotaResult?) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            if quotaResult?.decision == .quotaKO {
                // Quota is evaluated per RUM session. Once rejected, disable profiling for
                // continuous, custom and app-launch profiles in that session.
                cleanUpState(preservingOngoingOperations: false)
                isStoppedByQuota = true
                updateProfilerState(canProfile: shouldKeepProfilerRunning())
            } else if isStoppedByQuota {
                // A new session clears the previous quota result before the next check completes.
                isStoppedByQuota = false
                // Restart immediately when profiling is otherwise allowed, matching quota fail-open.
                let canProfile = shouldKeepProfilerRunning()
                updateProfilerState(canProfile: canProfile)
                if canProfile && timer == nil {
                    startTimer()
                }
            }
            // Memory profiling honours quota too (shouldRunMemoryProfiling checks it): stop on
            // rejection, resume on reset.
            updateMemoryProfilingState()
        }
    }
}

// MARK: - Helpers

private extension DatadogProfiler {
    func updateProfilingContext(quotaReason: DDProfiling.QuotaReason? = nil) {
        let context = ProfilingContext(status: .current, quotaReason: quotaReason)
        guard lastProfilingContext?.status != context.status || lastProfilingContext?.quotaReason != context.quotaReason else {
            return
        }

        lastProfilingContext = context
        featureScope.set(context: context)
    }

    var profileDropReason: ProfilingSessionMetric.ProfileDropReason {
        quotaChecker.isRejectedByQuota ? .quotaRejected(quotaChecker.quotaResult?.reason) : .noProfiledEvents
    }

    // Report only when continuous profiling is actually running.
    var shouldReportProfileAbsence: Bool {
        profilingSamplerProvider.isContinuousProfilingConfigured
            && profilingSamplerProvider.continuousProfilingSampled != false
    }

    var canWriteProfile: Bool {
        // Custom profiling is only handled by operation steps
        let hasCustomProfilingData = currentRUMVitals.contains { $0.value.stepType == .start }
        let hasContinuousProfilingVitals = operation == .continuousProfiling && currentRUMVitals.isEmpty == false
        let hasContinuousProfilingEvents = profilingSamplerProvider.continuousProfilingSampled == true
            && (hangs.isEmpty == false || longTasks.isEmpty == false)

        // Keep quota fail-open while the check is pending. Only explicit rejection prevents writing.
        return (hasCustomProfilingData || hasContinuousProfilingVitals || hasContinuousProfilingEvents)
            && !quotaChecker.isRejectedByQuota
    }

    /// Whether there is at least one RUM event of interest this window — a vital (including ongoing
    /// operations/views), an app hang (error), or a long task. This is the condition under which the
    /// heap snapshot is emitted, mirroring (and a superset of) the events the CPU `canWriteProfile`
    /// gate keys off.
    var hasRUMEventsOfInterest: Bool {
        currentRUMVitals.isEmpty == false
            || hangs.isEmpty == false
            || longTasks.isEmpty == false
    }

    /// Whether memory (heap) profiling should currently be sampling — independent of the
    /// continuous/custom CPU decision, and deliberately NOT gated on `hasConditionsToProfile`.
    ///
    /// Unlike the CPU profiler — whose sampling thread actively burns CPU and must stop in
    /// background / Low Power / low battery — allocation interception is passive: a Poisson-sampled
    /// table write on allocations the app makes anyway, costing nothing while the process is
    /// suspended. Recording therefore continues through every environmental condition, and
    /// `shouldEmitMemoryProfile` gates the part that does cost battery: the upload.
    ///
    /// That is also what preserves the live set. A stop followed by a start takes the native
    /// `start_new_session()` path, which clears the sample table — so a background round-trip used
    /// to erase every long-lived object, i.e. precisely the objects `inuse_*` exists to surface.
    /// The conditions that DO stop memory profiling (consent revoked, sampled out, install failure,
    /// quota rejection) are ones where clearing is the correct semantics, so no window ever ships
    /// with a silent hole in it.
    ///
    /// Consent is checked here — not only in `shouldKeepProfilerRunning()` — because memory
    /// profiling has its own lifecycle: `.notGranted` must uninstall the interception outright,
    /// not merely stop the CPU profiler.
    func shouldRunMemoryProfiling() -> Bool {
        guard isTrackingConsentAllowed,
              !hasMemoryInterceptionFailed,
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
            return isMemoryProfilingGraceAvailable
        }
    }

    /// Whether the periodic emission timer should be kept alive for memory profiling.
    ///
    /// Recording is passive and continues regardless of conditions (see
    /// `shouldRunMemoryProfiling()`), but uploading costs battery, so the timer stays gated on the
    /// full `ProfilingConditions` set. Keying it off the recording gate instead would leave it
    /// firing every interval while backgrounded — flushing a null CPU profile and emitting
    /// `shouldReportProfileAbsence` telemetry for windows that were never going to upload.
    ///
    /// Allocations observed while the timer is held off are not lost: they accumulate in the native
    /// alloc window (capture-and-reset, drained only when a profile is actually emitted) and are
    /// attributed to the first window that does emit. A long accumulation widens the sampling
    /// interval under back-pressure rather than dropping samples.
    var shouldEmitMemoryProfile: Bool {
        shouldRunMemoryProfiling() && hasConditionsToProfile
    }

    /// Whether the window currently being closed may still carry a heap snapshot.
    ///
    /// Not `shouldEmitMemoryProfile`: the flush triggered by the background transition is what
    /// closes out the foreground window, and `hasConditionsToProfile` has already flipped false by
    /// the time it runs — gating on it alone would drop that window's heap. Since recording now
    /// continues in the background, the latch instead allows exactly one emission once conditions
    /// are lost and none until they return, so no later flush re-uploads the same live set and
    /// double-counts the memory in the product.
    var canEmitHeapSnapshot: Bool {
        hasConditionsToProfile || !hasEmittedHeapSinceConditionsLost
    }

    /// Reconciles the memory interception state with `shouldRunMemoryProfiling()`, starting or
    /// stopping only on an actual transition. Safe to call repeatedly.
    func updateMemoryProfilingState() {
        let shouldRun = shouldRunMemoryProfiling()
        if shouldRun, !isMemoryProfilingRunning {
            guard startMemoryProfiling() else {
                // Neither path installed — fail closed rather than report a running profiler that
                // can never produce a sample. Latched so the next context update does not retry a
                // failure that is not transient (and re-emit its telemetry every cycle).
                hasMemoryInterceptionFailed = true
                stopMemoryProfiling()
                return
            }
            isMemoryProfilingRunning = true
            // A start from a stopped state takes the native `start_new_session()` path, which
            // clears the sample table and the alloc window, so this window's data begins now.
            // Without advancing, a restart after a quota rejection would keep a `memoryWindowStart`
            // from before the rejection and claim to cover a span it holds no samples for.
            //
            // Launch adoption does not reach here: `isMemoryProfilingRunning` is seeded from
            // `dd_memory_profiler_is_running()`, so an already-running pre-`main` sampler takes no
            // start branch and keeps its original window start.
            memoryWindowStart = dateProvider.now
        } else if !shouldRun, isMemoryProfilingRunning {
            stopMemoryProfiling()
            isMemoryProfilingRunning = false
        }
    }

    /// Evaluates every condition required to keep or restart the native profiler.
    func shouldKeepProfilerRunning() -> Bool {
        guard isTrackingConsentAllowed, !quotaChecker.isRejectedByQuota else {
            return false
        }

        if profilingSamplerProvider.isContinuousProfilingConfigured {
            switch profilingSamplerProvider.continuousProfilingSampled {
            case .some(true): // It is Continuous Profiling running
                return hasConditionsToProfile
            case .some(false): // It is Custom Profiling running
                return hasConditionsToProfile && currentRUMVitals.ongoingOperations().isEmpty == false
            case .none: // Waiting for RUM context info
                return hasConditionsToProfile && isContinuousProfilingGraceAvailable
            }
        } else { // It is Custom Profiling running
            return hasConditionsToProfile && canExtendCustomProfiling()
        }
    }

    var shouldWaitForAppLaunchVital: Bool {
        // If continuous profiling samples out before TTID, keep the native profiler
        // briefly so it can harvest the launch profile.
        hasAppLaunchProfileToHarvest
            && isTrackingConsentAllowed
            && !quotaChecker.isRejectedByQuota
            && hasConditionsToProfile
            && hasProcessedAppLaunchVital == false
            && dateProvider.now.timeIntervalSince(profileStartDate) < Constants.cutOffTime
    }

    var isCustomProfiling: Bool {
        profilingSamplerProvider.isContinuousProfilingConfigured == false
            || profilingSamplerProvider.continuousProfilingSampled == false
    }

    func canExtendCustomProfiling() -> Bool {
        guard !quotaChecker.isRejectedByQuota else {
            return false
        }

        return currentRUMVitals.ongoingOperations().contains {
            dateProvider.now.timeIntervalSince($1.date) < Constants.cutOffTime
        }
    }

    /// Installs both interception paths.
    ///
    /// - Returns: `true` when at least one path is observing. A single-path failure still returns
    ///   `true`: the surviving path yields real (if narrower) attribution, and the failure is
    ///   reported via telemetry. Only a total failure — typically the shared sampler failing to
    ///   start, which takes both paths down — returns `false`, so the caller can fail closed rather
    ///   than emit windows that can never contain a sample.
    func startMemoryProfiling() -> Bool {
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

    func stopMemoryProfiling() {
        // Never-restore: the +allocWithZone: / -dealloc trampolines stay installed and keep
        // forwarding; dd_objc_alloc_hook_stop only clears the observing flag and disables the
        // sampler. Safe to call even when not running.
        ObjCAllocInterception.stop()
        // Stop recording pure-Swift allocations. Never-restore: the rebound
        // trampolines stay installed and keep forwarding; they simply stop
        // observing. Safe to call even when not running.
        SwiftAllocInterception.stop()
    }

    var shouldHarvestAppLaunchProfileOnTTID: Bool {
        // TTID may still be attached to continuous/custom profiles when standalone
        // app-launch upload is disabled; this gate only decides standalone launch harvesting.
        guard hasAppLaunchProfileToHarvest
                && hasProcessedAppLaunchVital
                && !quotaChecker.isRejectedByQuota else {
            return false
        }

        if profilingSamplerProvider.isContinuousProfilingConfigured,
           profilingSamplerProvider.continuousProfilingSampled != false {
            return false
        }

        return currentRUMVitals.hasCompletedOperations() == false
            && canExtendCustomProfiling() == false
    }
}

// MARK: - ProfilingContext.Status

extension ProfilingContext.Status {
    static var current: Self { .init(dd_profiler_get_status()) }

    init(_ status: dd_profiler_status_t) {
        switch status {
        case DD_PROFILER_STATUS_NOT_STARTED:
            self = .stopped(reason: .notStarted)
        case DD_PROFILER_STATUS_RUNNING:
            self = .running
        case DD_PROFILER_STATUS_STOPPED:
            self = .stopped(reason: .manual)
        case DD_PROFILER_STATUS_TIMEOUT:
            self = .stopped(reason: .timeout)
        case DD_PROFILER_STATUS_PREWARMED:
            self = .stopped(reason: .prewarmed)
        case DD_PROFILER_STATUS_ALLOCATION_FAILED:
            self = .error(reason: .memoryAllocationFailed)
        default:
            self = .unknown
        }
    }
}

// MARK: - Dictionary Helpers

private extension Dictionary where Key == String, Value == Vital {
    func ongoingOperations() -> [String: Vital] {
        filter { $0.value.stepType == .start && $0.value.duration == nil }
    }

    func hasCompletedOperations() -> Bool {
        contains { $0.value.stepType == .start && $0.value.duration != nil }
    }

    func hasCompletedAllOperations() -> Bool {
        hasCompletedOperations()
            && contains { $0.value.stepType == .start && $0.value.duration == nil } == false
    }
}

#endif
