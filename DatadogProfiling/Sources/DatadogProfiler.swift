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
        /// Default cut off duration for custom profiling.
        static let customProfilingCutOffTime: TimeInterval = 60 // 1 minute cutoff
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
    private let isContinuousProfiling: Bool
    private let profilingConditions: ProfilingConditions
    private let profilingInterval: TimeInterval
    private var timer: DispatchSourceTimer?

    let operation: ProfilingOperation
    let featureScope: FeatureScope
    let telemetryController: ProfilingTelemetryController
    let encoder: JSONEncoder
    let dateProvider: DateProvider

    @ReadWriteLock
    private(set) var attributes: [String: AttributeValue] = [:]
    @ReadWriteLock
    private var hasReceivedAppLaunchVital = false
    // Ongoing RUM Operations to attach to profiles.
    private var currentRUMVitals: [String: Vital] = [:]
    // App hangs to attach to profiles.
    private var hangs: [DurationEvent] = []
    // Long tasks to attach to profiles.
    private var longTasks: [DurationEvent] = []
    private var previousCustomProfilingStartDate: Date
    private var hasConditionsToProfile = true

    init?(
        core: DatadogCoreProtocol,
        queue: DispatchQueue = DatadogProfiler.defaultQueue,
        isContinuousProfiling: Bool = true,
        operation: ProfilingOperation = .continuousProfiling,
        telemetryController: ProfilingTelemetryController = .init(),
        profilingConditions: ProfilingConditions = .init(),
        profilingInterval: TimeInterval = Constants.maxProfileDuration,
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
        self.isContinuousProfiling = isContinuousProfiling
        self.operation = operation
        self.telemetryController = telemetryController
        self.profilingConditions = profilingConditions
        self.profilingInterval = profilingInterval
        self.encoder = encoder
        self.dateProvider = dateProvider
        self.previousCustomProfilingStartDate = dateProvider.now

        if isContinuousProfiling {
            startTimer()
        }
    }

    deinit {
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
        queue.async { [weak self] in
            guard let self else {
                return
            }
            // Check, based on the context, if the profiler has conditions to profile
            hasConditionsToProfile = profilingConditions.canProfileApplication(with: context)

            if context.applicationStateHistory.currentState == .background {
                // Updates the profiler state if the app was or is about to have foreground time
                guard context.applicationStateHistory
                    .containsState(during: context.launchInfo.processLaunchDate...dateProvider.now, where: { $0 == .active }) else {
                    return
                }

                updateProfilerState(canProfile: hasConditionsToProfile && (isContinuousProfiling || canExtendCustomProfiling()))
                sendProfile()
            } else {
                switch ProfilingContext.Status.current {
                case .running, .stopped:
                    updateProfilerState(canProfile: hasConditionsToProfile && (isContinuousProfiling || canExtendCustomProfiling()))
                default:
                    break
                }
            }
        }
    }

    func handleAppLaunch(message: TTIDMessage) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            attributes = message.attributes

            // Remove events that were handled by `AppLaunchProfiler`
            currentRUMVitals = currentRUMVitals.ongoingOperations()
            hangs.removeAll()
            longTasks.removeAll()
            updateProfilerState(canProfile: hasConditionsToProfile && (isContinuousProfiling || canExtendCustomProfiling()))
        }
    }

    func handleOperation(message: OperationMessage) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            attributes = message.attributes

            switch message.operation.stepType {
            case .start:
                // Start profiler if it is a custom profiler and the operations have started
                if currentRUMVitals.isEmpty && isContinuousProfiling == false {
                    startTimer()
                    updateProfilerState(canProfile: hasConditionsToProfile)
                }

                currentRUMVitals[message.operation.key] = message.operation
            case .end:
                if var startVital = currentRUMVitals[message.operation.key] {
                    // Add duration to vital to help Profiling backend label correctly the samples of this vital
                    let duration = message.operation.date.timeIntervalSince(startVital.date)
                    startVital.duration = duration.dd.toInt64Nanoseconds
                    currentRUMVitals[message.operation.key] = startVital

                    // Stop profiler if it is a custom profiler and the operations have completed
                    if currentRUMVitals.didCompleteOperations() && isContinuousProfiling == false {
                        let customProfilingDuration = dateProvider.now.timeIntervalSince(previousCustomProfilingStartDate)
                        let fireInterval = customProfilingDuration < Constants.minProfileDuration ? Constants.minProfileDuration - customProfilingDuration : 0
                        fireTimer(after: fireInterval)
                    }
                }
            default: break
            }
        }
    }

    func handleAppHang(message: AppHangMessage) {
        queue.async { [weak self] in
            self?.hangs.append(message.hang)
        }
    }

    func handleLongTask(message: LongTaskMessage) {
        queue.async { [weak self] in
            self?.longTasks.append(message.longTask)
        }
    }

    func updateProfilerAndSendProfile() {
        updateProfilerState(canProfile: hasConditionsToProfile && (isContinuousProfiling || canExtendCustomProfiling()))
        sendProfile()
    }

    func updateProfilerState(canProfile: Bool) {
        let profilingContext = updateProfilingContext()

        switch profilingContext.status {
        case .stopped:
            if canProfile {
                dd_profiler_start()
                previousCustomProfilingStartDate = dateProvider.now
                updateProfilingContext()
                startTimer()
            }
        case .running:
            if canProfile == false {
                dd_profiler_stop()
                updateProfilingContext()
                stopTimer()
            }
        default: break
        }
    }

    func sendProfile() {
        previousCustomProfilingStartDate = dateProvider.now
        guard let profile = dd_profiler_flush_and_get_profile() else {
            telemetryController.send(metric: AppLaunchMetric.noProfile)
            return
        }

        defer { dd_pprof_destroy(profile) }
        if canWriteProfile() {
            write(
                profile: profile,
                rumVitals: Array(self.currentRUMVitals.values),
                hangs: hangs,
                longTasks: longTasks
            )
            cleanUpState()
        }
    }

    func canWriteProfile() -> Bool {
        currentRUMVitals.count > 0
        || hangs.isEmpty == false
        || longTasks.isEmpty == false
    }

    func canExtendCustomProfiling() -> Bool {
        currentRUMVitals.contains {
            dateProvider.now.timeIntervalSince($1.date) < Constants.customProfilingCutOffTime
        }
    }

    func cleanUpState() {
        // if it is custom profiling and reached the cutoff time
        if canExtendCustomProfiling() == false {
            currentRUMVitals.removeAll()
        } else {
            currentRUMVitals = currentRUMVitals.ongoingOperations()
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
