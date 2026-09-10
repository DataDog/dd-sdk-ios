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

    /// Owns the memory (heap) profiling lifecycle — interception, window, correlation and heap
    /// emission — on this profiler's own queue. This coordinator keeps the single periodic timer
    /// and drives it; memory never schedules, starts or stops the CPU profiler.
    private let memoryProfiler: MemoryProfiler
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
    /// Tracks profiler stops caused by quota rejection so a later session quota reset can
    /// restart profiling without waiting for an unrelated app-state or condition change.
    private var isStoppedByQuota = false

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
        self.operation = profilingSamplerProvider.isContinuousProfilingConfigured ? .continuousProfiling : .customProfiling
        self.isContinuousProfilingGraceAvailable = profilingSamplerProvider.isContinuousProfilingConfigured
            && profilingSamplerProvider.continuousProfilingSampled == nil
        // Memory profiling runs on its own RUM-composed session decision, independent of the
        // continuous/custom CPU state machine. Constructing it here reconciles its interception as
        // early as possible — optimistically during the launch grace — so the first window covers
        // app launch; it is reconciled again as the decision and conditions change.
        self.memoryProfiler = MemoryProfiler(
            core: core,
            profilingSamplerProvider: profilingSamplerProvider,
            quotaChecker: quotaChecker,
            telemetryController: telemetryController,
            profilingConditions: profilingConditions,
            encoder: encoder,
            dateProvider: dateProvider
        )

        quotaChecker.onQuotaResultUpdate = { [weak self] result in
            self?.handle(quotaResult: result)
        }

        // The emission timer runs when EITHER continuous CPU profiling or memory profiling is
        // configured, so memory can emit a heap-only profile even when CPU profiling is not running.
        if profilingSamplerProvider.isContinuousProfilingConfigured
            || profilingSamplerProvider.isMemoryProfilingConfigured {
            startTimer()
        }
    }

    deinit {
        stopTimer()
        // Memory interception is torn down by `MemoryProfiler.deinit`, which runs as this
        // coordinator releases it.
    }

    /// `ProfilingHandler` asks the handler for a heap attachment while writing a CPU profile. The
    /// coordinator owns no heap state — it forwards to the unit that does.
    func heapAttachment(
        fittingAlongside cpuProfileSize: Int,
        attributes: [AttributeKey: AttributeValue],
        operation: ProfilingOperation
    ) -> Data? {
        memoryProfiler.heapAttachment(
            fittingAlongside: cpuProfileSize,
            attributes: attributes,
            operation: operation
        )
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
        memoryProfiler.update(serverTimeOffset: context.serverTimeOffset)
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

            // Memory profiling follows its own decision + conditions, so reconcile its
            // interception on EVERY context update regardless of the early-returns below —
            // including the consent revocation below, which returns before any
            // continuous-profiling path is reached.
            defer { memoryProfiler.updateState() }

            // Memory's own view of consent and conditions must land BEFORE the CPU state machine
            // runs: a background transition drives an emission from inside `updateProfilerState`,
            // and that emission consults `canEmitSnapshot`.
            memoryProfiler.update(context: context)

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
            defer { previousAppState = currentAppState }

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
            memoryProfiler.update(attributes: message.attributes)

            // Capture vitals like TTFD that are not operation steps.
            if message.operation.stepType == nil {
                currentRUMVitals[message.operation.key] = message.operation
                memoryProfiler.record(vital: message.operation)
            } else if message.operation.stepType == .start {
                currentRUMVitals[message.operation.key] = message.operation
                memoryProfiler.record(vital: message.operation)
                // Note this can clear `currentRUMVitals` (custom profiling with a stopped native
                // profiler), which is exactly why memory keeps its own copy.
                updateProfilerState(canProfile: shouldKeepProfilerRunning())
            } else if message.operation.stepType == .end {
                memoryProfiler.recordOperationEnd(message.operation)
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
            memoryProfiler.update(attributes: message.attributes)
            memoryProfiler.record(hang: message.hang)
            // A hang often coincides with allocation churn or a live-heap spike, so it gets its own
            // heap snapshot rather than waiting for the next periodic boundary. This only ever adds
            // a heap event — the CPU state machine above is untouched by it.
            memoryProfiler.trigger(.appHang, operation: operation)
        }
    }

    func handleLongTask(message: LongTaskMessage) {
        queue.async { [weak self] in
            guard let self, isTrackingConsentAllowed, !quotaChecker.isRejectedByQuota else {
                return
            }
            attributes = message.attributes
            longTasks.append(message.longTask)
            memoryProfiler.update(attributes: message.attributes)
            memoryProfiler.record(longTask: message.longTask)
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
        if !canProfile, !memoryProfiler.shouldEmitPeriodicProfile {
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
            if timer == nil, memoryProfiler.shouldEmitPeriodicProfile {
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
        let windowEnd = dateProvider.now
        profileStartDate = windowEnd

        let cpuProfile = dd_profiler_flush_and_get_profile()
        defer { if let cpuProfile { dd_pprof_destroy(cpuProfile) } }

        // Memory profiling is continuous: every window in which sampling is active emits its heap,
        // the same delta model the Go profiler uses. Correlation is attached when there is any, but
        // it is NOT a precondition — a window with no vital, hang or long task still carries real
        // allocation data, and withholding it would leave gaps in a curve that is meant to be
        // unbroken. A genuinely empty window costs nothing: the heap capture returns nil when
        // neither the live set nor the alloc window holds a sample, so an idle app uploads nothing.
        let wantsHeap = memoryProfiler.isRecording && memoryProfiler.canEmitSnapshot

        if let cpuProfile {
            if canWriteProfile {
                // Coupled path: CPU/wall profile; heap is attached when memory is active. The event
                // carries the CPU machine's correlation, unchanged.
                write(
                    profile: cpuProfile,
                    operation: operation,
                    rumVitals: Array(self.currentRUMVitals.values),
                    hangs: hangs,
                    longTasks: longTasks,
                    captureHeapProfile: wantsHeap
                )
            } else if wantsHeap {
                // CPU profile isn't writable this window — emit a heap-only profile carrying
                // memory's own correlation.
                memoryProfiler.emitPeriodicHeapProfile(end: windowEnd, operation: operation)
            } else if quotaChecker.isRejectedByQuota || shouldReportProfileAbsence {
                telemetryController.sendProfileDropped(for: operation, reason: profileDropReason)
            }
        } else if wantsHeap {
            // No CPU profile at all (CPU profiling not running) — independent heap-only emission.
            memoryProfiler.emitPeriodicHeapProfile(end: windowEnd, operation: operation)
        } else if shouldReportProfileAbsence {
            telemetryController.sendNoProfile(for: operation)
        }

        // The alloc window is captured-and-reset by the heap capture, so the delta this window
        // reported is gone; close the window so the next one is bounded from here. This runs
        // whenever memory was asked for a heap — including a window that turned out to hold no
        // samples, whose capture attempt still drained the native alloc window.
        if wantsHeap {
            memoryProfiler.closeWindow(at: windowEnd)
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
            if timer == nil, memoryProfiler.shouldEmitPeriodicProfile {
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
            captureHeapProfile: memoryProfiler.isRecording
        )

        if memoryProfiler.isRecording {
            // The launch allocations were just captured (alloc window reset); advance the memory
            // window so a subsequent heap-only emission is bounded from TTID, not from launch.
            // Only the window start moves: the accumulated correlation stays for the windows that
            // follow, as it did before this lifecycle moved into `MemoryProfiler`.
            memoryProfiler.advanceWindow(to: dateProvider.now)
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
            // Memory profiling honours quota too (its own recording gate checks it): stop on
            // rejection, resume on reset.
            memoryProfiler.updateState()
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
