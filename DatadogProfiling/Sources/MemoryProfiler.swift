/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@preconcurrency import DatadogInternal

#if !os(watchOS)

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
        case waiting
        case running
        /// Emission is suspended; allocation and free observation remain active.
        case emissionSuspended
        case failed
        case shutDown
    }

    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let profilingSamplerProvider: ProfilingSamplerProvider
    private let profilingConditions = ProfilingConditions()
    private let dateProvider: DateProvider
    private let notificationCenter: NotificationCenter
    private var terminationObserver: NSObjectProtocol?
    private var context: DatadogContext?
    private var sessionID: String?
    private var isSessionSampled: Bool?
    private var isAwaitingInitialSession = true
    private var hasCapturedAppLaunch = false
    private var pendingAppLaunch: dd_memory_capture_t?
    private var hasForegroundTime = false
    private(set) var state: State = .stopped

    private var isEnabled: Bool { profilingSamplerProvider.isMemoryProfilingConfigured }

    init(
        profilingSamplerProvider: ProfilingSamplerProvider,
        queue: DispatchQueue = MemoryProfiler.defaultQueue,
        dateProvider: DateProvider = SystemDateProvider(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.profilingSamplerProvider = profilingSamplerProvider
        self.queue = queue
        self.dateProvider = dateProvider
        self.notificationCenter = notificationCenter
        queue.setSpecific(key: queueKey, value: ())
        runOnQueueSync(queue, key: queueKey) {
            if isEnabled {
                // Start is idempotent: a constructor-started sampler retains its original window.
                state = dd_memory_profiler_start() ? .waiting : .failed
            } else {
                dd_memory_profiler_stop()
            }
        }
        if isEnabled {
            terminationObserver = notificationCenter.addObserver(
                forName: ApplicationNotifications.willTerminate,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.flushAndStop()
            }
        }
    }

    deinit {
        if let terminationObserver {
            notificationCenter.removeObserver(terminationObserver)
        }
        dd_memory_profiler_stop()
    }
}

// MARK: - FeatureMessageReceiver

extension MemoryProfiler: FeatureMessageReceiver {
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
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

extension MemoryProfiler {
    func receive(context: DatadogContext) {
        // The context receiver resolves sampling before delivering this message.
        // Snapshot it before enqueueing: a later session may update the provider meanwhile.
        let isSampled = context.additionalContext(ofType: RUMCoreContext.self) != nil
            ? profilingSamplerProvider.memoryProfilingSampled : nil
        queue.async { [weak self] in
            self?.update(context: context, isSampled: isSampled)
        }
    }

    func captureAppLaunch() {
        queue.async { [weak self] in
            guard let self, state != .shutDown, !hasCapturedAppLaunch else {
                return
            }
            hasCapturedAppLaunch = true
            let isWaitingForSession = isSessionSampled == nil
                && (state == .waiting || state == .emissionSuspended)
            guard state == .running || isWaitingForSession else {
                return
            }
            if isWaitingForSession {
                // Close exactly at TTID while the first session decision is pending.
                // No subsequent native capture may overwrite this borrowed view before resolution.
                var capture = dd_memory_capture_t()
                switch dd_memory_profiler_capture(&capture) {
                case DD_MEMORY_CAPTURE_READY:
                    pendingAppLaunch = capture
                case DD_MEMORY_CAPTURE_IDLE:
                    break
                default:
                    stopNative()
                    state = .failed
                }
            } else if canEmit {
                capture()
            }
        }
    }

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

    /// Discards pending work during SDK teardown.
    func stop() {
        runOnQueueSync(queue, key: queueKey) {
            shutDown()
        }
    }
}

// MARK: - Lifecycle

private extension MemoryProfiler {
    func update(context newContext: DatadogContext, isSampled: Bool?) {
        guard isEnabled, state != .shutDown else {
            return
        }
        // Revocation discards the whole window; it never flushes previously permitted work.
        guard newContext.trackingConsent != .notGranted else {
            context = newContext
            stopNative()
            return
        }

        let rumContext = newContext.additionalContext(ofType: RUMCoreContext.self)
        let newSessionID = rumContext?.sessionID
        let didChangeSession = newSessionID != sessionID
        if didChangeSession, sessionID != nil {
            if state == .running || state == .emissionSuspended, isSessionSampled == true {
                // Recording continues while emission is suspended. Drain the prior
                // session's delta even when its final window cannot be emitted.
                capture(shouldWrite: state == .running && canEmit)
            }
            // The new window must establish its own foreground history. An
            // active prior session cannot authorize a second closing emission.
            hasForegroundTime = false
        }
        context = newContext
        if let rumContext {
            sessionID = rumContext.sessionID
            isSessionSampled = isSampled
            isAwaitingInitialSession = false
        } else if sessionID != nil {
            sessionID = nil
            isSessionSampled = nil
            isAwaitingInitialSession = false
        }

        let currentAppState = newContext.applicationStateHistory.currentState
        if currentAppState == .active {
            hasForegroundTime = true
        } else if !hasForegroundTime {
            // TTID has already advanced the native window. Include the pending
            // launch window when looking for its historical foreground time.
            let origin = pendingAppLaunch?.time_nanos ?? dd_memory_profiler_window_start_time_nanos()
            let start = Date(timeIntervalSince1970: Double(origin) / 1_000_000_000)
            if origin > 0, start <= dateProvider.now {
                hasForegroundTime = newContext.applicationStateHistory.containsState(
                    during: start...dateProvider.now,
                    where: { $0 == .active }
                )
            }
        }
        if let pendingAppLaunch, isSessionSampled != nil {
            self.pendingAppLaunch = nil
            if canEmit {
                write(capture: pendingAppLaunch)
            }
        }
        updateState()
    }

    var canEmit: Bool {
        isEnabled
            && context?.trackingConsent != .notGranted
            && isSessionSampled == true
            && hasForegroundTime
    }

    var canCollect: Bool {
        isEnabled
            && context?.trackingConsent != .notGranted
            && (isSessionSampled == true || (isSessionSampled == nil && isAwaitingInitialSession))
    }

    func updateState() {
        guard state != .failed else {
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
            state = isSessionSampled == nil ? .waiting : .running
        }
        if context?.applicationStateHistory.currentState == .active {
            hasForegroundTime = true
        }
        let canEmitInCurrentConditions = context.map { profilingConditions.canProfileApplication(with: $0) } ?? true
        let isReturningToForeground = context?.applicationStateHistory.currentState == .active
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
        state = isSessionSampled == nil ? .waiting : .running
    }

    func capture(shouldWrite: Bool = true) {
        var capture = dd_memory_capture_t()
        switch dd_memory_profiler_capture(&capture) {
        case DD_MEMORY_CAPTURE_IDLE:
            break
        case DD_MEMORY_CAPTURE_READY:
            if shouldWrite {
                write(capture: capture)
            }
        default:
            stopNative()
            state = .failed
        }
    }

    func write(capture: dd_memory_capture_t) {
        // TODO: RUM-18355 Encode and write the captured memory profile here, before
        // another native lifecycle call invalidates its borrowed aggregation.
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
