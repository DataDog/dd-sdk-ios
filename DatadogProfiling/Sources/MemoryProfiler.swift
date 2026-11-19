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
        /// Recording is active while awaiting RUM context for emission.
        case waiting
        case running
        /// Emission is suspended; allocation and free observation keep the continuous live set current.
        /// An admitted launch remains open until its final capture at TTID.
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
    // Retain the last ID through missing RUM context so returning sessions start a fresh delta.
    private var lastSessionID: String?
    /// Whether the native launch window is still open for TTID capture.
    private var isRecordingAppLaunch = false
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
        // Native startup preserves launch coverage independently of emission sampling.
        if isEnabled, dd_memory_profiler_is_running() {
            isRecordingAppLaunch = dd_memory_profiler_was_started_at_launch()
            state = .waiting
        } else {
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
                lastSessionID = nil
                stopNative()
                return
            }

            let rumContext = context.additionalContext(ofType: RUMCoreContext.self)
            if let rumContext,
               lastSessionID == rumContext.sessionID,
               sessionSampler == rumContext.sessionSampler {
                // Keep processing until this window has established foreground eligibility.
                if state == .running, hasForegroundTime,
                   profilingConditions.canProfileApplication(with: context) {
                    return
                }
            }
            let newSessionID = rumContext?.sessionID
            let didChangeSession = newSessionID != lastSessionID || rumContext?.sessionSampler != sessionSampler
            if didChangeSession,
               lastSessionID != nil || !dd_memory_profiler_was_started_at_launch(),
               rumContext != nil || sessionSampler != nil {
                // A launch cannot span RUM sessions. Continue tracking its surviving objects.
                isRecordingAppLaunch = false
                pendingAppLaunch = nil
                if state == .running || state == .waiting || state == .emissionSuspended {
                    // Drain every prior delta, including sampled-out and uncorrelated periods,
                    // so only the live set carries across emission boundaries.
                    capture(shouldWrite: state == .running && canEmit)
                }
                // The new window must establish its own foreground history. An
                // active prior session cannot authorize a second closing emission.
                hasForegroundTime = false
            }
            sessionSampler = rumContext?.sessionSampler
            if let rumContext {
                lastSessionID = rumContext.sessionID
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
                if canEmit {
                    write(snapshot: pendingAppLaunch)
                }
            }
            updateState(context: context)
        }
    }

    func captureAppLaunch() {
        queue.async { [weak self] in
            guard let self, state != .shutDown, isRecordingAppLaunch else {
                return
            }
            isRecordingAppLaunch = false
            guard state == .running || state == .waiting || state == .emissionSuspended else {
                return
            }
            // Environmental blockers suspend continuous emission, but the admitted launch
            // still closes once at TTID so its final capture includes the whole launch window.
            if sessionSampler == nil {
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
            } else {
                capture(shouldWrite: canEmit)
            }
        }
    }
}

extension MemoryProfiler {
    /// Closes an eligible foreground window on the profiler queue.
    func captureWindow() {
        queue.async { [weak self] in
            guard let self, state == .running, !isRecordingAppLaunch, canEmit else {
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

    func updateState(context: DatadogContext) {
        guard state != .failed, state != .shutDown else {
            return
        }
        // Configuration and consent control recording. Sampling and environmental
        // conditions control emission while the recorder keeps the live set current.
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
                // Preserve the launch boundary until TTID rather than closing it early.
                if !isRecordingAppLaunch, canEmit {
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
        isRecordingAppLaunch = false
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
