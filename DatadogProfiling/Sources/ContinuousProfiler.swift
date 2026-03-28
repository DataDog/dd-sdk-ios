/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// swiftlint:disable duplicate_imports
#if swift(>=6.0)
internal import DatadogMachProfiler
#else
@_implementationOnly import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

internal final class ContinuousProfiler: ProfilingHandler {
    enum Constants {
        /// Default profile duration during continuous profiling.
        static let maxProfileDuration: TimeInterval = 60 // 1 minute profiles
        /// Minimum profile duration during continuous profiling.
        static let minProfileDuration: TimeInterval = 5 // 5 seconds profiles
        /// Default cut off duration for custom profiling.
        static let customProfilingCutOffTime: TimeInterval = 60 // 1 minute cutoff
    }

    /// Ensures only one `ContinuousProfiler` is active at a time.
    private static var hasActiveInstance = false
    private static let lock = NSLock()

    private let isContinuousProfiling: Bool
    private let profilingConditions: ProfilingConditions
    private let profilingInterval: TimeInterval
    private var timer: Timer?

    let operation: ProfilingOperation
    let featureScope: FeatureScope
    let telemetryController: ProfilingTelemetryController
    let encoder: JSONEncoder
    let dateProvider: DateProvider

    @ReadWriteLock
    private(set) var attributes: [String: AttributeValue] = [:]
    // Ongoing RUM Operations to attach to profiles.
    @ReadWriteLock
    private var currentRUMVitals: [String: Operation] = [:]
    // App hangs to attach to profiles.
    @ReadWriteLock
    private var hangs: [DurationEvent] = []
    // Long tasks to attach to profiles.
    @ReadWriteLock
    private var longTasks: [DurationEvent] = []
    @ReadWriteLock
    private var hasReceivedAppLaunchVital = false
    @ReadWriteLock
    private var previousCustomProfilingStartDate: Date

    /// The notification center where this profiler observes `UIApplication` lifecycle notifications.
    private weak var notificationCenter: NotificationCenter?

    init?(
        core: DatadogCoreProtocol,
        isContinuousProfiling: Bool,
        operation: ProfilingOperation = .continuousProfiling,
        telemetryController: ProfilingTelemetryController = .init(),
        profilingConditions: ProfilingConditions = .init(),
        profilingInterval: TimeInterval = Constants.maxProfileDuration,
        encoder: JSONEncoder = JSONEncoder(),
        notificationCenter: NotificationCenter = .default,
        dateProvider: DateProvider = SystemDateProvider()
    ) {
        Self.lock.lock()
        guard Self.hasActiveInstance == false else {
            Self.lock.unlock()
            return nil
        }
        Self.hasActiveInstance = true
        Self.lock.unlock()

        self.featureScope = core.scope(for: ProfilerFeature.self)
        self.isContinuousProfiling = isContinuousProfiling
        self.operation = operation
        self.telemetryController = telemetryController
        self.profilingConditions = profilingConditions
        self.profilingInterval = profilingInterval
        self.encoder = encoder
        self.notificationCenter = notificationCenter
        self.dateProvider = dateProvider
        self.previousCustomProfilingStartDate = dateProvider.now

        if isContinuousProfiling {
            startTimer()
        }
        observeNotificationCenter()
    }

    deinit {
        Self.lock.lock()
        Self.hasActiveInstance = false
        Self.lock.unlock()

        notificationCenter?.removeObserver(
            self,
            name: ApplicationNotifications.didEnterBackground,
            object: nil
        )
        notificationCenter?.removeObserver(
            self,
            name: ApplicationNotifications.willEnterForeground,
            object: nil
        )
    }
}

// MARK: - FeatureMessageReceiver

extension ContinuousProfiler: FeatureMessageReceiver {
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .payload(message) = message else {
            return false
        }

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
    }
}

// MARK: - Private

private extension ContinuousProfiler {
    @objc
    func applicationDidEnterBackground() {
        updateProfilerAndSendProfile()
    }

    @objc
    func applicationWillEnterForeground() {
        updateProfilerAndSendProfile()
    }

    func handleAppLaunch(message: TTIDMessage) {
        featureScope.context { [weak self] context in
            guard let self else {
                return
            }

            attributes = message.attributes

            // Remove events that were handled by `AppLaunchProfiler`
            _currentRUMVitals.mutate { $0 = $0.ongoingOperations() }
            _hangs.mutate { $0.removeAll() }
            _longTasks.mutate { $0.removeAll() }
            updateProfilerState(context: context, canProfile: isContinuousProfiling || canExtendCustomProfiling())
        }
    }

    func handleOperation(message: OperationMessage) {
        featureScope.context { [weak self] context in
            guard let self else {
                return
            }

            attributes = message.attributes

            switch message.operation.stepType {
            case .start:
                // Start profiler if it is a custom profiler and the operations have started
                if currentRUMVitals.isEmpty && isContinuousProfiling == false {
                    startTimer()
                    updateProfilerState(context: context)
                }

                _currentRUMVitals.mutate { $0[message.operation.key] = (start: message.operation, nil) }
            case .end:
                if let startVital = currentRUMVitals[message.operation.key]?.start {
                    _currentRUMVitals.mutate { $0[message.operation.key] = (start: startVital, message.operation) }

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
        featureScope.context { [weak self] context in
            self?._hangs.mutate { $0.append(message.hang) }
        }
    }

    func handleLongTask(message: LongTaskMessage) {
        featureScope.context { [weak self] context in
            self?._longTasks.mutate { $0.append(message.longTask) }
        }
    }

    func updateProfilerAndSendProfile() {
        featureScope.context { [weak self] context in
            guard let self else {
                return
            }

            // Updates the profiler state if the app was or is about to have foreground time
            guard context.applicationStateHistory
                .containsState(during: context.launchInfo.processLaunchDate...dateProvider.now, where: { $0 == .active }) else {
                return
            }

            updateProfilerState(
                context: context,
                canProfile: isContinuousProfiling || canExtendCustomProfiling()
            )
            sendProfile()
        }
    }

    func updateProfilerState(context: DatadogContext, canProfile: Bool = true) {
        let profilingContext = self.updateProfilingContext()
        let canProfile = canProfile && profilingConditions.canProfileApplication(with: context)

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
            self.telemetryController.send(metric: AppLaunchMetric.noProfile)
            return
        }

        defer { dd_pprof_destroy(profile) }
        if canWriteProfile() {
            write(
                profile: profile,
                rumVitals: self.currentRUMVitals.allVitals(),
                hangs: hangs,
                longTasks: longTasks
            )
            cleanUpState()
        }
    }

    func observeNotificationCenter() {
        notificationCenter?.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: ApplicationNotifications.didEnterBackground,
            object: nil
        )
        notificationCenter?.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: ApplicationNotifications.willEnterForeground,
            object: nil
        )
    }

    func startTimer() {
        guard self.timer == nil else {
            // reset timer
            fireTimer(after: profilingInterval)
            return
        }

        // Schedule reoccurring samples
        let timer = Timer(timeInterval: profilingInterval, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            updateProfilerAndSendProfile()
        }

        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopTimer() {
        self.timer?.invalidate()
        self.timer = nil
    }

    func fireTimer(after interval: TimeInterval) {
        timer?.fireDate = dateProvider.now.addingTimeInterval(interval)
    }

    func canWriteProfile() -> Bool {
        self.currentRUMVitals.count > 0
        || self.hangs.isEmpty == false
        || self.longTasks.isEmpty == false
    }

    func canExtendCustomProfiling() -> Bool {
        self.currentRUMVitals.contains {
            dateProvider.now.timeIntervalSince($1.start.date) < Constants.customProfilingCutOffTime
        }
    }

    func cleanUpState() {
        // if it is custom profiling and reached the cutoff time
        if canExtendCustomProfiling() == false {
            _currentRUMVitals.mutate { $0.removeAll() }
        } else {
            _currentRUMVitals.mutate { $0 = $0.ongoingOperations() }
        }
        _hangs.mutate { $0.removeAll() }
        _longTasks.mutate { $0.removeAll() }
    }
}

// MARK: - Testing funcs

extension ContinuousProfiler {
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
