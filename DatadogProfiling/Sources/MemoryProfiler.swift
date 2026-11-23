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
internal final class MemoryProfiler: ProfileSnapshotProvider, @unchecked Sendable {
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
        /// An admitted launch remains open until TTID or the launch fallback.
        case emissionSuspended
        case failed
        case shutDown
    }

    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let profilingSamplerProvider: ProfilingSamplerProvider
    private let profilingConditions = ProfilingConditions()
    private let writer: ProfileWriter
    private let scheduler: ProfilingScheduler
    private var periodicStart: DispatchTime?
    private let dateProvider: DateProvider
    private let monotonicClock: MonotonicClock
    private let appLaunchDeadline: TimeInterval
    private var sessionSampler: DeterministicSampler?
    // Retain the last ID through missing RUM context so returning sessions start a fresh delta.
    private var lastSessionID: String?
    /// Whether the native launch window is still awaiting TTID or a fallback capture.
    private var isRecordingAppLaunch = false
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
        scheduler: ProfilingScheduler,
        queue: DispatchQueue = MemoryProfiler.defaultQueue,
        dateProvider: DateProvider = SystemDateProvider(),
        monotonicClock: MonotonicClock = SystemMonotonicClock(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.profilingSamplerProvider = profilingSamplerProvider
        self.queue = queue
        self.writer = writer
        self.scheduler = scheduler
        self.dateProvider = dateProvider
        self.monotonicClock = monotonicClock
        let now = monotonicClock.elapsedTime
        let age = Double(dd_memory_profiler_window_age_nanos()) / 1_000_000_000
        self.appLaunchDeadline = now + max(0, ProfilingScheduler.Constants.profilingInterval - age)
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
        scheduler.stopPeriodic(for: self)
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
                sessionSampler = nil
                lastSessionID = nil
                currentContext = context
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
                    currentContext = context
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
                clearDurationEvents()
            }
            sessionSampler = rumContext?.sessionSampler
            if let rumContext {
                lastSessionID = rumContext.sessionID
            }
            currentContext = context
            if profilingSamplerProvider.memory.sampled(for: sessionSampler) == false {
                clearDurationEvents()
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
                if canEmit {
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
                let status = dd_memory_profiler_capture(&capture)
                if periodicStart != nil {
                    periodicStart = .now()
                }
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
            } else {
                capture(shouldWrite: canEmit, operation: .appLaunch, message: message)
            }
        }
    }
}

extension MemoryProfiler {
    func captureSnapshot(scheduledFor time: DispatchTime, completion: @escaping @Sendable (ProfileSnapshot?) -> Void) {
        queue.async { [weak self] in
            guard let self, state == .running, canEmit,
                  let periodicStart, time >= periodicStart else {
                completion(nil)
                return
            }
            expireAppLaunchIfNeeded()
            guard !isRecordingAppLaunch else {
                completion(nil)
                return
            }
            completion(closeWindow())
        }
    }

    /// Closes an eligible foreground window on the profiler queue.
    func captureWindow() {
        queue.async { [weak self] in
            guard let self, state == .running, canEmit else {
                return
            }
            expireAppLaunchIfNeeded()
            guard !isRecordingAppLaunch else {
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
            guard let self, state != .stopped, state != .failed, state != .shutDown,
                  state != .emissionSuspended || isRecordingAppLaunch,
                  profilingSamplerProvider.memory.sampled(for: sessionSampler) != false else {
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
            && profilingSamplerProvider.memory.sampled(for: sessionSampler) == true
            && hasForegroundTime
    }

    /// Releases an expired TTID wait without stopping allocation and free tracking.
    func expireAppLaunchIfNeeded() {
        if isRecordingAppLaunch, monotonicClock.elapsedTime >= appLaunchDeadline {
            isRecordingAppLaunch = false
        }
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
            state = rumContext == nil ? .waiting : .running
        }
        let canEmitInCurrentConditions = profilingConditions.canProfileApplication(with: context)
        let isReturningToForeground = context.applicationStateHistory.currentState == .active
        guard canEmitInCurrentConditions, state != .emissionSuspended || isReturningToForeground else {
            if state == .running || state == .waiting {
                // Preserve the launch boundary until TTID rather than closing it early.
                if !isRecordingAppLaunch {
                    if canEmit {
                        capture()
                    } else {
                        clearDurationEvents()
                    }
                }
                if state != .failed {
                    state = .emissionSuspended
                }
            }
            stopPeriodicCapture()
            return
        }
        state = rumContext == nil ? .waiting : .running
        if profilingSamplerProvider.memory.sampled(for: rumContext?.sessionSampler) == true {
            if periodicStart == nil {
                periodicStart = .now()
            }
            scheduler.startPeriodic(for: self)
        } else {
            stopPeriodicCapture()
        }
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
        // Queued ticks from the preceding window must not close the new one.
        if periodicStart != nil {
            periodicStart = .now()
        }
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
        // These events provide RUM context when CPU supplies none; they do not select a heap slice.
        let rumEvents = durationEvents
            .filter { $0.couldBeSampled(byProfileStartingAt: start, endingAt: end) }
            .compactMap { event -> RUMEvent? in
                switch event.type {
                case .error: return .hang(event)
                case .longTask: return .longTask(event)
                @unknown default: return nil
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

    func stopPeriodicCapture() {
        periodicStart = nil
        scheduler.stopPeriodic(for: self)
    }

    func stopNative() {
        let didFail = state == .failed
        stopPeriodicCapture()
        dd_memory_profiler_stop()
        state = didFail ? .failed : .stopped
        hasForegroundTime = false
        isRecordingAppLaunch = false
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
