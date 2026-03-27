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
    }

    private let profilingConditions: ProfilingConditions
    private let profilingInterval: TimeInterval
    private var timer: Timer?

    let operation: ProfilingOperation = .continuousProfiling
    let featureScope: FeatureScope
    let telemetryController: ProfilingTelemetryController
    let encoder: JSONEncoder

    @ReadWriteLock
    private(set) var context: [String: AttributeValue] = [:]
    // Ongoing RUM Operations to attach to profiles.
    @ReadWriteLock
    private var currentRUMVitals: [String: Operation] = [:]
    // App hangs to attach to profiles.
    @ReadWriteLock
    private var hangs: [DurationEvent<RUMErrorEvent>] = []
    // Long tasks to attach to profiles.
    @ReadWriteLock
    private var longTasks: [DurationEvent<RUMLongTaskEvent>] = []

    /// The notification center where this profiler observes `UIApplication` lifecycle notifications.
    private weak var notificationCenter: NotificationCenter?

    init(
        core: DatadogCoreProtocol,
        telemetryController: ProfilingTelemetryController = .init(),
        profilingConditions: ProfilingConditions = .init(),
        profilingInterval: TimeInterval = Constants.maxProfileDuration,
        encoder: JSONEncoder = JSONEncoder(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.featureScope = core.scope(for: ProfilerFeature.self)
        self.telemetryController = telemetryController
        self.profilingConditions = profilingConditions
        self.profilingInterval = profilingInterval
        self.encoder = encoder
        self.notificationCenter = notificationCenter

        startTimer()
        observeNotificationCenter()
    }

    deinit {
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
        guard case let .payload(message as RUMMessage) = message else {
            return false
        }

        context = message.context

        switch message.event {
        case let vital as Vital:
            switch vital.type {
            case let .rumOperation(stepType):
                if stepType == .start {
                    currentRUMVitals[vital.key] = (start: vital, nil)
                } else if let startVital = currentRUMVitals[vital.key]?.start {
                    currentRUMVitals[vital.key] = (start: startVital, end: vital)
                }
                return false
            case .applicationLaunch:
                // Remove events that were handled by `AppLaunchProfiler`
                self.currentRUMVitals = self.currentRUMVitals.ongoingOperations()
                self.hangs.removeAll()
                self.longTasks.removeAll()
                resetTimer()
                return false
            default:
                return false
            }
        case let longTask as DurationEvent<RUMLongTaskEvent>:
            longTasks.append(longTask)
            return true
        case let hang as DurationEvent<RUMErrorEvent>:
            hangs.append(hang)
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
        self.updateProfilerState(canProfile: false) { [weak self] in
            self?.sendProfile()
        }
    }

    @objc
    func applicationWillEnterForeground() {
        resetTimer()
        updateProfilerState()
    }

    func updateProfilerState(canProfile: Bool = true, onRunning: @escaping () -> Void = {}) {
        featureScope.context { [weak self] context in
            guard let self else {
                return
            }

            let profilingContext = self.updateProfilingContext()
            let canProfile = canProfile && profilingConditions.canProfileApplication(with: context)

            switch profilingContext.status {
            case .stopped:
                if canProfile {
                    dd_profiler_start()
                    updateProfilingContext()
                }
            case .running:
                if canProfile == false {
                    dd_profiler_stop()
                    updateProfilingContext()
                }

                onRunning()
            default: break
            }
        }
    }

    func sendProfile() {
        guard let profile = dd_profiler_flush_and_get_profile() else {
            self.telemetryController.send(metric: AppLaunchMetric.noProfile)
            return
        }

        defer { dd_pprof_destroy(profile) }
        if canWriteProfile() {
            self.write(
                profile: profile,
                rumVitals: self.currentRUMVitals.allVitals(),
                hangs: hangs,
                longTasks: longTasks
            )
            self.currentRUMVitals = self.currentRUMVitals.ongoingOperations()
            self.hangs.removeAll()
            self.longTasks.removeAll()
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
        // Schedule reoccurring samples
        let timer = Timer(timeInterval: profilingInterval, repeats: true) { [weak self] _ in
            self?.updateProfilerState { [weak self] in
                self?.sendProfile()
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func resetTimer() {
        timer?.fireDate = Date().addingTimeInterval(profilingInterval)
    }

    func canWriteProfile() -> Bool {
        self.currentRUMVitals.count > 0
        || self.hangs.isEmpty == false
        || self.longTasks.isEmpty == false
    }
}
