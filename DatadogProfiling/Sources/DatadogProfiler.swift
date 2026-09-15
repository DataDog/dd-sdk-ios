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

internal final class DatadogProfiler: ProfilingHandler {
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

    /// Ensures only one `ContinuousProfiler` is active at a time.
    private static var hasActiveInstance = false
    private static let lock = NSLock()

    /// The queue used to synchronize the profiling data and the writes.
    private let queue: DispatchQueue
    private let profilingSamplerProvider: ProfilingSamplerProvider
    private let quotaChecker: ProfilingQuotaChecking
    private let profilingConditions: ProfilingConditions
    private let profilingInterval: TimeInterval
    private let minProfileDuration: TimeInterval
    private var timer: DispatchSourceTimer?

    let featureScope: FeatureScope
    let telemetryController: ProfilingTelemetryController
    let encoder: JSONEncoder
    let dateProvider: DateProvider

    @ReadWriteLock
    private(set) var attributes: [String: AttributeValue] = [:]
    @ReadWriteLock
    private var hasReceivedAppLaunchVital = false
    // Interval between device and server time.
    private(set) var currentServerTimeOffset: TimeInterval = .zero
    // Ongoing RUM Operations to attach to profiles.
    private var currentRUMVitals: [String: Vital] = [:]
    // App hangs to attach to profiles.
    private var hangs: [DurationEvent] = []
    // Long tasks to attach to profiles.
    private var longTasks: [DurationEvent] = []
    private var previousCustomProfilingStartDate: Date
    private var hasConditionsToProfile = true
    private var previousAppState: AppState?
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

    init?(
        core: DatadogCoreProtocol,
        profilingSamplerProvider: ProfilingSamplerProvider,
        quotaChecker: ProfilingQuotaChecking,
        queue: DispatchQueue = DatadogProfiler.defaultQueue,
        telemetryController: ProfilingTelemetryController = .init(),
        profilingConditions: ProfilingConditions = .init(),
        profilingInterval: TimeInterval = Constants.maxProfileDuration,
        minProfileDuration: TimeInterval = Constants.minProfileDuration,
        encoder: JSONEncoder = JSONEncoder(),
        dateProvider: DateProvider = SystemDateProvider()
    ) {
        do {
            Self.lock.lock()
            defer { Self.lock.unlock() }
            guard Self.hasActiveInstance == false else {
                return nil
            }
            Self.hasActiveInstance = true
        }

        self.featureScope = core.scope(for: ProfilerFeature.self)
        self.queue = queue
        self.profilingSamplerProvider = profilingSamplerProvider
        self.quotaChecker = quotaChecker
        self.telemetryController = telemetryController
        self.profilingConditions = profilingConditions
        self.profilingInterval = profilingInterval
        self.minProfileDuration = minProfileDuration
        self.encoder = encoder
        self.dateProvider = dateProvider
        self.previousCustomProfilingStartDate = dateProvider.now
        self.operation = profilingSamplerProvider.isContinuousProfilingConfigured ? .continuousProfiling : .customProfiling
        self.isContinuousProfilingGraceAvailable = profilingSamplerProvider.isContinuousProfilingConfigured
            && profilingSamplerProvider.continuousProfilingSampled == nil

        if profilingSamplerProvider.isContinuousProfilingConfigured {
            startTimer()
        }

        quotaChecker.onQuotaResultUpdate = { [weak self] result in
            self?.queue.async { [weak self] in
                guard let self else {
                    return
                }

                if result?.decision == .quotaKO {
                    // Quota is evaluated per RUM session. Once rejected, disable profiling for
                    // continuous, custom and app-launch profiles in that session.
                    cleanUpState()
                    isStoppedByQuota = true
                    updateProfilerState(canProfile: shouldKeepProfilerRunning())
                    discardCurrentProfile()
                } else if isStoppedByQuota {
                    // A new session clears the previous quota result before the next check completes.
                    // Restart immediately when profiling is otherwise allowed, matching quota fail-open.
                    let canProfile = shouldKeepProfilerRunning()
                    isStoppedByQuota = false
                    updateProfilerState(canProfile: canProfile)
                    if canProfile && timer == nil {
                        startTimer()
                    }
                }
            }
        }
    }

    deinit {
        stopTimer()
        Self.lock.lock()
        Self.hasActiveInstance = false
        Self.lock.unlock()
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
                return false
            case let message as OperationMessage:
                handleOperation(message: message)
                // Every OperationMessage is consumed by ContinuousProfiler after app launch vital
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
        dd_profiler_set_server_time_offset_ns(context.serverTimeOffset.dd.toInt64Nanoseconds)

        queue.async { [weak self] in
            guard let self else {
                return
            }

            currentServerTimeOffset = context.serverTimeOffset
            let previousConditions = hasConditionsToProfile
            hasConditionsToProfile = profilingConditions.canProfileApplication(with: context)
            let currentAppState = context.applicationStateHistory.currentState
            defer { previousAppState = currentAppState }

            switch profilingSamplerProvider.continuousProfilingSampled {
            case true?:
                operation = .continuousProfiling
            case false?:
                operation = .customProfiling

                if isContinuousProfilingGraceAvailable {
                    // The profiler was running optimistically while waiting for the RUM
                    // sampling decision. If that decision samples out continuous profiling,
                    // stop the optimistic profiler unless app-launch profiling still needs
                    // the shared native profiler to harvest TTID.
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

                sendProfile()
                updateProfilerState(canProfile: shouldKeepProfilerRunning())
            }
            // If the conditions are the same, ignore the update profiler state
            else if currentAppState != previousAppState || hasConditionsToProfile != previousConditions {
                switch ProfilingContext.Status.current {
                case .running, .stopped, .unknown:
                    updateProfilerState(canProfile: shouldKeepProfilerRunning())
                default:
                    break
                }
            }
        }
    }

    func handleAppLaunch(message: TTIDMessage) {
        hasReceivedAppLaunchVital = true
        queue.async { [weak self] in
            guard let self else {
                return
            }
            attributes = message.attributes

            // Remove events that were handled by `AppLaunchProfiler`.
            cleanUpState()
            updateProfilerState(canProfile: shouldKeepProfilerRunning())
        }
    }

    func handleOperation(message: OperationMessage) {
        queue.async { [weak self] in
            guard let self, !quotaChecker.isRejectedByQuota else {
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

                    // If profiling is effectively running in custom mode, trigger timer when the last operation completes.
                    if currentRUMVitals.didCompleteOperations() && isCustomProfiling {
                        let customProfilingDuration = dateProvider.now.timeIntervalSince(previousCustomProfilingStartDate)
                        let fireInterval = customProfilingDuration < minProfileDuration ? minProfileDuration - customProfilingDuration : 0
                        fireTimer(after: fireInterval)
                    }
                }
            }
        }
    }

    func handleAppHang(message: AppHangMessage) {
        queue.async { [weak self] in
            guard let self, !self.quotaChecker.isRejectedByQuota else {
                return
            }
            attributes = message.attributes
            hangs.append(message.hang)
        }
    }

    func handleLongTask(message: LongTaskMessage) {
        queue.async { [weak self] in
            guard let self, !self.quotaChecker.isRejectedByQuota else {
                return
            }
            attributes = message.attributes
            longTasks.append(message.longTask)
        }
    }

    func updateProfilerAndSendProfile() {
        isContinuousProfilingGraceAvailable = false
        updateProfilerState(canProfile: shouldKeepProfilerRunning())
        sendProfile()
    }

    func updateProfilerState(canProfile: Bool) {
        switch ProfilingContext.Status.current {
        case .stopped, .unknown: // When `.unknown` status, mostly profiler NOT_CREATED, it will try to start the profiler
            if canProfile && !isCustomProfiling {
                dd_profiler_start()
                previousCustomProfilingStartDate = dateProvider.now
                updateProfilingContext()
                startTimer()
            } else if isCustomProfiling {
                currentRUMVitals.removeAll()
            }
        case .running:
            if canProfile {
                if timer == nil {
                    startTimer()
                }
            } else {
                stopTimer()
                dd_profiler_stop()
                updateProfilingContext(quotaReason: quotaChecker.isRejectedByQuota ? quotaChecker.quotaResult?.reason : nil)
            }
        default: break
        }
    }

    func sendProfile() {
        previousCustomProfilingStartDate = dateProvider.now
        guard let profile = dd_profiler_flush_and_get_profile() else {
            if shouldReportProfileAbsence {
                telemetryController.sendNoProfile(for: operation)
            }
            cleanUpState()
            return
        }

        defer { dd_pprof_destroy(profile) }
        if canWriteProfile {
            write(
                profile: profile,
                rumVitals: Array(self.currentRUMVitals.values),
                hangs: hangs,
                longTasks: longTasks
            )
        } else if quotaChecker.isRejectedByQuota || shouldReportProfileAbsence {
            telemetryController.sendProfileDropped(for: operation, reason: profileDropReason)
        }

        cleanUpState()
    }

    func discardCurrentProfile() {
        guard let profile = dd_profiler_flush_and_get_profile() else {
            return
        }
        dd_pprof_destroy(profile)
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
        let hasCustomProfilingData = currentRUMVitals.count > 0
        let hasContinuousProfilingData = profilingSamplerProvider.continuousProfilingSampled == true
            && (hangs.count > 0 || longTasks.count > 0)

        // Keep quota fail-open while the check is pending. Only explicit rejection prevents writing.
        return (hasCustomProfilingData || hasContinuousProfilingData) && !quotaChecker.isRejectedByQuota
    }

    func shouldKeepProfilerRunning() -> Bool {
        guard !quotaChecker.isRejectedByQuota else {
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
        // If continuous profiling samples out before TTID, keep the shared native profiler
        // briefly so AppLaunchProfiler can harvest the launch profile.
        hasReceivedAppLaunchVital == false
            && dateProvider.now.timeIntervalSince(previousCustomProfilingStartDate) < Constants.cutOffTime
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

    func cleanUpState() {
        // Preserve ongoing custom operations across normal flushes; quota rejection discards all RUM references.
        if canExtendCustomProfiling() {
            currentRUMVitals = currentRUMVitals.ongoingOperations()
        } else {
            currentRUMVitals.removeAll()
        }
        hangs.removeAll()
        longTasks.removeAll()
    }
}

// MARK: - Testing funcs

extension DatadogProfiler {
    /// Whether a `ContinuousProfiler` instance is currently active.
    static var isInstantiated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasActiveInstance
    }

    /// Resets the singleton guard (for testing only).
    static func resetActiveInstance() {
        lock.lock()
        defer { lock.unlock() }
        hasActiveInstance = false
    }
}
#endif
