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

    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let profilingSamplerProvider: ProfilingSamplerProvider
    private let profilingConditions = ProfilingConditions()
    private let writer: ProfileWriter
    private let dateProvider: DateProvider
    private var hasCapturedAppLaunch = false
    private var pendingAppLaunch: (
        snapshot: ProfileSnapshot,
        timeNanos: Int64
    )?
    private var durationEvents: [DurationEvent] = []
    private var eventAttributes: [AttributeKey: AttributeValue] = [:]
    private var currentContext: DatadogContext?
    private var hasForegroundTime = false
    private(set) var state: State = .stopped

    private var isEnabled: Bool { profilingSamplerProvider.memory.isConfigured }

    private var rumContext: RUMCoreContext? {
        guard currentContext?.trackingConsent != .notGranted else {
            return nil
        }
        return currentContext?.additionalContext(ofType: RUMCoreContext.self)
    }

    init(
        profilingSamplerProvider: ProfilingSamplerProvider,
        writer: ProfileWriter,
        queue: DispatchQueue = MemoryProfiler.defaultQueue,
        dateProvider: DateProvider = SystemDateProvider(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.profilingSamplerProvider = profilingSamplerProvider
        self.queue = queue
        self.writer = writer
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
        case .payload(let payload):
            switch payload {
            case let message as TTIDMessage:
                captureAppLaunch(message: message)
            case let message as AppHangMessage:
                append(message.hang, attributes: message.attributes)
            case let message as LongTaskMessage:
                append(message.longTask, attributes: message.attributes)
            default:
                break
            }
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
                currentContext = context
                stopNative()
                return
            }

            let previousRUMContext = rumContext
            let nextRUMContext = context.additionalContext(ofType: RUMCoreContext.self)
            if let nextRUMContext,
               previousRUMContext?.sessionID == nextRUMContext.sessionID,
               previousRUMContext?.sessionSampler == nextRUMContext.sessionSampler {
                // Unchanged session sampling cannot restore eligibility for a stopped recording.
                if state == .stopped {
                    currentContext = context
                    return
                }
                // Keep processing until this window has established foreground eligibility.
                if state == .running, hasForegroundTime,
                   profilingConditions.canProfileApplication(with: context) {
                    currentContext = context
                    return
                }
            }
            let didChangeSession = nextRUMContext?.sessionID != previousRUMContext?.sessionID
            if didChangeSession, previousRUMContext != nil {
                if state == .running || state == .emissionSuspended,
                   profilingSamplerProvider.memory.sampled(for: previousRUMContext?.sessionSampler) == true {
                    // Recording continues while emission is suspended. Drain the prior
                    // session's delta even when its final window cannot be emitted.
                    capture(shouldWrite: state == .running && canEmit)
                }
                // The new window must establish its own foreground history. An
                // active prior session cannot authorize a second closing emission.
                hasForegroundTime = false
                clearDurationEvents()
            }
            currentContext = context
            if nextRUMContext == nil, previousRUMContext != nil {
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
            if let pendingAppLaunch, rumContext != nil {
                self.pendingAppLaunch = nil
                if canEmitAppLaunch {
                    var snapshot = pendingAppLaunch.snapshot
                    snapshot.rumContext = rumContext
                    writer.write([snapshot], operation: .appLaunch)
                }
            }
            updateState(context: context)
        }
    }

    func captureAppLaunch(message: TTIDMessage) {
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
            let isWaitingForSession = rumContext == nil
                && (state == .waiting || state == .emissionSuspended)
            guard state == .running || isWaitingForSession else {
                return
            }
            if isWaitingForSession {
                // Close exactly at TTID while the first session decision is pending.
                // Serialize now so the pending snapshot owns its bytes until resolution.
                var capture = dd_memory_capture_t()
                let status = dd_memory_profiler_capture(&capture)
                defer { clearDurationEvents() }
                switch status {
                case DD_MEMORY_CAPTURE_READY:
                    if let snapshot = makeSnapshot(from: capture, message: message) {
                        pendingAppLaunch = (snapshot, capture.time_nanos)
                    }
                case DD_MEMORY_CAPTURE_IDLE:
                    break
                default:
                    stopNative()
                    state = .failed
                }
            } else if canEmitAppLaunch {
                capture(operation: .appLaunch, message: message)
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
    func append(_ event: DurationEvent, attributes: [AttributeKey: AttributeValue]) {
        queue.async { [weak self] in
            guard let self, state != .stopped, state != .failed, state != .shutDown else {
                return
            }
            durationEvents.append(event)
            eventAttributes = attributes
        }
    }

    func clearDurationEvents() {
        durationEvents.removeAll()
        eventAttributes.removeAll()
    }

    var canEmit: Bool {
        isEnabled
            && profilingSamplerProvider.memory.sampled(for: rumContext?.sessionSampler) == true
            && hasForegroundTime
    }

    var canCollect: Bool {
        isEnabled
            && (
                profilingSamplerProvider.memory.sampled(for: rumContext?.sessionSampler) == true
                    || (state != .stopped && rumContext == nil)
                    || (
                        state != .stopped && !hasCapturedAppLaunch
                            && profilingSamplerProvider.memory.appLaunchSampled(for: rumContext?.sessionSampler) == true
                    )
            )
    }

    var canEmitAppLaunch: Bool {
        isEnabled
            && profilingSamplerProvider.memory.appLaunchSampled(for: rumContext?.sessionSampler) == true
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
            state = rumContext == nil ? .waiting : .running
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
        state = rumContext == nil ? .waiting : .running
    }

    func capture(shouldWrite: Bool = true, operation: ProfilingOperation = .continuousProfiling, message: TTIDMessage? = nil) {
        if let snapshot = closeWindow(shouldEncode: shouldWrite, message: message) {
            writer.write([snapshot], operation: operation)
        }
    }

    func closeWindow(shouldEncode: Bool = true, message: TTIDMessage? = nil) -> ProfileSnapshot? {
        defer { clearDurationEvents() }
        var capture = dd_memory_capture_t()
        let status = dd_memory_profiler_capture(&capture)
        switch status {
        case DD_MEMORY_CAPTURE_IDLE:
            return nil
        case DD_MEMORY_CAPTURE_READY:
            return shouldEncode ? makeSnapshot(from: capture, message: message) : nil
        default:
            stopNative()
            state = .failed
            return nil
        }
    }

    func makeSnapshot(from capture: dd_memory_capture_t, message: TTIDMessage? = nil) -> ProfileSnapshot? {
        let offset = (message?.ttid.serverTimeOffset ?? currentContext?.serverTimeOffset ?? 0).dd.toInt64Nanoseconds
        let (start, startOverflow) = capture.time_nanos.addingReportingOverflow(offset)
        let (end, endOverflow) = start.addingReportingOverflow(capture.duration_nanos)
        guard !startOverflow, !endOverflow, start >= 0, capture.duration_nanos >= 0 else {
            return nil
        }
        var capture = capture
        capture.time_nanos = start
        let view = dd_memory_profiler_serialize(&capture)
        guard let bytes = view.data, view.size > 0 else {
            return nil
        }
        let attributes = eventAttributes.merging(message?.attributes ?? [:]) { _, launchValue in launchValue }
        let rumEvents = durationEvents
            .filter { event in
                let (eventEnd, overflow) = event.start.addingReportingOverflow(event.duration)
                let overlapsStart = overflow ? event.duration > 0 : eventEnd >= start
                return event.start <= end && overlapsStart
            }
            .map { event -> RUMEvent in
                switch event.type {
                case .error: return .hang(event)
                case .longTask: return .longTask(event)
                }
            }
        return ProfileSnapshot(
            start: Date(timeIntervalSince1970: Double(start) / 1_000_000_000),
            end: Date(timeIntervalSince1970: Double(end) / 1_000_000_000),
            attachment: PprofAttachment(
                filename: ProfileAttachments.Constants.heapPprofFilename,
                // The native encoder owns this view until the next serialization or stop.
                data: Data(bytes: bytes, count: view.size)
            ),
            rumEvents: rumEvents + (message.map { [.vital($0.ttid)] } ?? []),
            attributes: attributes,
            rumContext: rumContext
        )
    }

    func stopNative() {
        let didFail = state == .failed
        dd_memory_profiler_stop()
        state = didFail ? .failed : .stopped
        hasForegroundTime = false
        hasCapturedAppLaunch = true
        pendingAppLaunch = nil
        clearDurationEvents()
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
