/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@preconcurrency import DatadogInternal

#if !os(watchOS) && !os(macOS)

// Keep native types out of the distributed Swift module interface.
@_implementationOnly import DatadogMachProfiler

/// Owns memory profiling windows independently of CPU profiling decisions.
internal final class MemoryProfiler: @unchecked Sendable {
    static let defaultQueue = DispatchQueue(
        label: "com.datadoghq.datadog-memory-profiler",
        qos: .utility
    )

    enum State: Equatable {
        case stopped
        /// Native launch recording is active while awaiting the first RUM sampling decision.
        case waiting
        case running
        /// Emission is suspended; allocation and free observation remain active.
        case emissionSuspended
        case failed
        case shutDown
    }

    private struct Snapshot {
        let pprof: Data
        let timeNanos: Int64
    }

    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let profilingSamplerProvider: ProfilingSamplerProvider
    private let profilingConditions = ProfilingConditions()
    private let dateProvider: DateProvider
    private var sessionSampler: DeterministicSampler?
    private var sessionID: String?
    private var hasCapturedAppLaunch = false
    private var pendingAppLaunch: Snapshot?
    private var hasForegroundTime = false
    private(set) var state: State = .stopped

    private var isEnabled: Bool { profilingSamplerProvider.memory.isConfigured }

    init(
        profilingSamplerProvider: ProfilingSamplerProvider,
        queue: DispatchQueue = MemoryProfiler.defaultQueue,
        dateProvider: DateProvider = SystemDateProvider(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.profilingSamplerProvider = profilingSamplerProvider
        self.queue = queue
        self.dateProvider = dateProvider
        queue.setSpecific(key: queueKey, value: ())
        // Only an admitted launch may record before the first RUM decision.
        if isEnabled,
           dd_memory_profiler_was_started_at_launch(),
           dd_memory_profiler_is_running() {
            state = .waiting
        } else {
            hasCapturedAppLaunch = true
            if !isEnabled {
                runOnQueueSync(queue, key: queueKey) {
                    dd_memory_profiler_stop()
                }
            }
        }
        if isEnabled {
            notificationCenter.addObserver(
                self,
                selector: #selector(applicationWillTerminate(_:)),
                name: ApplicationNotifications.willTerminate,
                object: nil
            )
        }
    }

    deinit {
        // RUM-18564 will coordinate SDK shutdown independently of receiver lifetime.
        if state != .shutDown {
            dd_memory_profiler_stop()
        }
    }
}

// MARK: - FeatureMessageReceiver

extension MemoryProfiler: FeatureMessageReceiver {
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard isEnabled else {
            return false
        }
        switch message {
        case .context(let context):
            receive(context: context)
        case .payload(let payload) where payload is TTIDMessage:
            captureAppLaunch()
        default:
            break
        }
        // Memory observation must not consume messages needed by the CPU profiler.
        return false
    }
}

// MARK: - Context and capture

private extension MemoryProfiler {
    @objc
    func applicationWillTerminate(_ notification: Notification) {
        flushAndStop()
    }

    func receive(context: DatadogContext) {
        queue.async { [weak self] in
            guard let self, state != .failed, state != .shutDown else {
                return
            }
            // Revocation discards the whole window; it never flushes previously permitted work.
            guard context.trackingConsent != .notGranted else {
                sessionSampler = nil
                stopNative()
                return
            }

            let rumContext = context.additionalContext(ofType: RUMCoreContext.self)
            if let rumContext,
               sessionID == rumContext.sessionID,
               sessionSampler == rumContext.sessionSampler {
                // Unchanged session sampling cannot restore eligibility for a stopped recording.
                if state == .stopped {
                    return
                }
                // Keep processing until this window has established foreground eligibility.
                if state == .running, hasForegroundTime,
                   profilingConditions.canProfileApplication(with: context) {
                    return
                }
            }
            let newSessionID = rumContext?.sessionID
            let didChangeSession = newSessionID != sessionID
            if didChangeSession, sessionID != nil {
                if state == .running || state == .emissionSuspended,
                   profilingSamplerProvider.memory.sampled(for: sessionSampler) == true {
                    // Recording continues while emission is suspended. Drain the prior
                    // session's delta even when its final window cannot be emitted.
                    capture(shouldWrite: state == .running && canEmit)
                }
                // The new window must establish its own foreground history. An
                // active prior session cannot authorize a second closing emission.
                hasForegroundTime = false
            }
            sessionSampler = rumContext?.sessionSampler
            if let rumContext {
                sessionID = rumContext.sessionID
            } else if sessionID != nil {
                sessionID = nil
                stopNative()
                return
            }

            let currentAppState = context.applicationStateHistory.currentState
            if currentAppState == .active {
                hasForegroundTime = true
            } else if !hasForegroundTime {
                // TTID has already advanced the native window. Include the pending
                // launch window when looking for its historical foreground time.
                let origin = pendingAppLaunch?.timeNanos ?? dd_memory_profiler_window_start_time_nanos()
                let start = Date(timeIntervalSince1970: Double(origin) / 1_000_000_000)
                if origin > 0, start <= dateProvider.now {
                    hasForegroundTime = context.applicationStateHistory.containsState(
                        during: start...dateProvider.now,
                        where: { $0 == .active }
                    )
                }
            }
            if let pendingAppLaunch, sessionSampler != nil {
                self.pendingAppLaunch = nil
                if canEmitAppLaunch {
                    write(snapshot: pendingAppLaunch)
                }
            }
            updateState(context: context)
        }
    }

    func captureAppLaunch() {
        queue.async { [weak self] in
            guard let self, state != .shutDown, !hasCapturedAppLaunch else {
                return
            }
            hasCapturedAppLaunch = true
            defer {
                if state != .failed, !canCollect {
                    stopNative()
                }
            }
            let isWaitingForSession = sessionSampler == nil
                && (state == .waiting || state == .emissionSuspended)
            guard state == .running || isWaitingForSession else {
                return
            }
            if isWaitingForSession {
                // Close exactly at TTID while the first session decision is pending.
                // Serialize now so the pending snapshot owns its bytes until resolution.
                var capture = dd_memory_capture_t()
                switch dd_memory_profiler_capture(&capture) {
                case DD_MEMORY_CAPTURE_READY:
                    pendingAppLaunch = serialize(capture: capture)
                case DD_MEMORY_CAPTURE_IDLE:
                    break
                default:
                    stopNative()
                    state = .failed
                }
            } else if canEmitAppLaunch {
                capture()
            }
        }
    }
}

extension MemoryProfiler {
    /// Closes an eligible foreground window on the profiler queue.
    func captureWindow() {
        queue.async { [weak self] in
            guard let self, state == .running, canEmit else {
                return
            }
            capture()
        }
    }

    /// Flushes eligible foreground work on an orderly termination, then releases native hooks.
    func flushAndStop() {
        runOnQueueSync(queue, key: queueKey) {
            guard state != .shutDown else {
                return
            }
            if state == .running, canEmit {
                dd_memory_profiler_pause()
                capture()
            }
            shutDown()
        }
    }
}

// MARK: - Helpers

private extension MemoryProfiler {
    var canEmit: Bool {
        isEnabled
            && profilingSamplerProvider.memory.sampled(for: sessionSampler) == true
            && hasForegroundTime
    }

    var canCollect: Bool {
        isEnabled
            && (
                profilingSamplerProvider.memory.sampled(for: sessionSampler) == true
                    || (state != .stopped && sessionSampler == nil)
                    || (
                        state != .stopped && !hasCapturedAppLaunch
                            && profilingSamplerProvider.memory.appLaunchSampled(for: sessionSampler) == true
                    )
            )
    }

    var canEmitAppLaunch: Bool {
        isEnabled
            && profilingSamplerProvider.memory.appLaunchSampled(for: sessionSampler) == true
            && hasForegroundTime
    }

    func updateState(context: DatadogContext) {
        guard state != .failed, state != .shutDown else {
            return
        }
        guard canCollect else {
            stopNative()
            return
        }
        // Eligibility controls recording even while environmental conditions
        // suppress emission, including consent recovery in background.
        if state == .stopped {
            guard dd_memory_profiler_start() else {
                state = .failed
                return
            }
            state = sessionSampler == nil ? .waiting : .running
        }
        let canEmitInCurrentConditions = profilingConditions.canProfileApplication(with: context)
        let isReturningToForeground = context.applicationStateHistory.currentState == .active
        guard canEmitInCurrentConditions, state != .emissionSuspended || isReturningToForeground else {
            if state == .running || state == .waiting {
                if canEmit {
                    capture()
                }
                if state != .failed {
                    state = .emissionSuspended
                }
            }
            return
        }
        state = sessionSampler == nil ? .waiting : .running
    }

    func capture(shouldWrite: Bool = true) {
        var capture = dd_memory_capture_t()
        switch dd_memory_profiler_capture(&capture) {
        case DD_MEMORY_CAPTURE_IDLE:
            break
        case DD_MEMORY_CAPTURE_READY:
            if shouldWrite, let snapshot = serialize(capture: capture) {
                write(snapshot: snapshot)
            }
        default:
            stopNative()
            state = .failed
        }
    }

    private func serialize(capture: dd_memory_capture_t) -> Snapshot? {
        var capture = capture
        let encoded = dd_memory_profiler_serialize(&capture)
        guard let data = encoded.data, encoded.size > 0 else {
            return nil
        }
        return Snapshot(
            pprof: Data(bytes: data, count: encoded.size),
            timeNanos: capture.time_nanos
        )
    }

    private func write(snapshot: Snapshot) {
        // TODO: RUM-18355 Write the serialized memory profile with its event and RUM metadata.
    }

    func stopNative() {
        let didFail = state == .failed
        dd_memory_profiler_stop()
        state = didFail ? .failed : .stopped
        hasForegroundTime = false
        hasCapturedAppLaunch = true
        pendingAppLaunch = nil
    }

    func shutDown() {
        guard state != .shutDown else {
            return
        }
        stopNative()
        state = .shutDown
    }
}

#endif
