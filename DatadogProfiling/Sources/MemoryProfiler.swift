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
    enum Constants {
        /// Delay for collecting nearby RUM events into one heap capture.
        static let eventCaptureDelay: TimeInterval = 1
    }

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
    private let telemetryController: ProfilingTelemetryController
    private let scheduler: ProfilingScheduler
    private var periodicStart: DispatchTime?
    private let dateProvider: DateProvider
    private let monotonicClock: MonotonicClock
    private let appLaunchDeadline: TimeInterval
    private var eventCaptureWorkItem: DispatchWorkItem?
    private var sessionSampler: DeterministicSampler?
    // Retain the last ID through missing RUM context so returning sessions start a fresh delta.
    private var lastSessionID: String?
    /// Whether the native launch window is still awaiting TTID or a fallback capture.
    private var isRecordingAppLaunch = false
    private var pendingAppLaunch: (
        snapshot: ProfileSnapshot,
        timeNanos: Int64
    )?
    private var rumEvents: [RUMEvent] = []
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
        telemetryController: ProfilingTelemetryController = .init(),
        queue: DispatchQueue = MemoryProfiler.defaultQueue,
        dateProvider: DateProvider = SystemDateProvider(),
        monotonicClock: MonotonicClock = SystemMonotonicClock(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.profilingSamplerProvider = profilingSamplerProvider
        self.queue = queue
        self.writer = writer
        self.scheduler = scheduler
        self.telemetryController = telemetryController
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
            stopNative()
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
                append(.error(message.hang), attributes: message.attributes)
            case let message as MemoryWarningMessage:
                append(.error(message.warning), attributes: message.attributes)
            case let message as OperationMessage where message.operation.stepType == nil
                && message.operation.name == "time_to_full_display":
                append(.vital(message.operation), attributes: message.attributes)
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
                discardPendingAppLaunch()
                if state == .running || state == .waiting || state == .emissionSuspended {
                    // Drain every prior delta, including sampled-out and uncorrelated periods,
                    // so only the live set carries across emission boundaries.
                    capture(shouldWrite: state == .running && canEmit)
                }
                // The new window must establish its own foreground history. An
                // active prior session cannot authorize a second closing emission.
                hasForegroundTime = false
                clearEvents()
            }
            sessionSampler = rumContext?.sessionSampler
            if let rumContext {
                lastSessionID = rumContext.sessionID
            }
            currentContext = context
            if profilingSamplerProvider.memory.sampled(for: sessionSampler) == false {
                clearEvents()
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
                } else if var diagnostics = pendingAppLaunch.snapshot.memoryDiagnostics {
                    diagnostics.captureResult = .discarded
                    telemetryController.sendMemoryDiagnostics(diagnostics, for: .appLaunch)
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
                let origin = dd_memory_profiler_window_start_time_nanos()
                if let snapshot = closeWindow(operation: .appLaunch, message: message) {
                    pendingAppLaunch = (snapshot, origin)
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
            // Event-triggered heaps retain their own correlations instead of inheriting
            // the CPU timeline selected by a combined periodic write.
            let operation: ProfilingOperation = rumEvents.isEmpty ? .continuousProfiling : .trigger
            let snapshot = closeWindow(operation: operation)
            if operation == .trigger {
                if let snapshot {
                    writer.write([snapshot], operation: operation)
                }
                completion(nil)
            } else {
                completion(snapshot)
            }
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
    func append(_ event: RUMEvent, attributes: [AttributeKey: AttributeValue]) {
        queue.async { [weak self] in
            guard let self, state != .stopped, state != .failed, state != .shutDown,
                  state != .emissionSuspended || isRecordingAppLaunch,
                  profilingSamplerProvider.memory.sampled(for: sessionSampler) != false else {
                return
            }
            rumEvents.append(event)
            mergeEventAttributes(attributes)
            scheduleEventCapture()
        }
    }

    func mergeEventAttributes(_ attributes: [AttributeKey: AttributeValue]) {
        var merged = attributes
        for key in [RUMCoreContext.IDs.viewID, RUMCoreContext.IDs.viewName] {
            var views = eventAttributes[key] as? [String] ?? []
            for view in attributes[key] as? [String] ?? [] where !views.contains(view) {
                views.append(view)
            }
            if !views.isEmpty {
                merged[key] = views
            }
        }
        eventAttributes = merged
    }

    func clearEvents() {
        eventCaptureWorkItem?.cancel()
        eventCaptureWorkItem = nil
        rumEvents.removeAll()
        eventAttributes.removeAll()
    }

    func scheduleEventCapture() {
        guard eventCaptureWorkItem == nil, !rumEvents.isEmpty,
              state == .running, canEmit else {
            return
        }
        expireAppLaunchIfNeeded()
        guard !isRecordingAppLaunch else {
            return
        }
        // A fixed delay coalesces bursts without postponing capture on each new event.
        let work = DispatchWorkItem { [weak self] in
            guard let self, state == .running, canEmit, !rumEvents.isEmpty else {
                return
            }
            capture(operation: .trigger)
        }
        eventCaptureWorkItem = work
        queue.asyncAfter(deadline: .now() + Constants.eventCaptureDelay, execute: work)
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
                telemetryController.sendMemoryDiagnostics(.consume(result: .startFailed), for: .continuousProfiling)
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
                        clearEvents()
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
            scheduleEventCapture()
        } else {
            stopPeriodicCapture()
        }
    }

    func capture(shouldWrite: Bool = true, operation: ProfilingOperation = .continuousProfiling, message: TTIDMessage? = nil) {
        let operation = operation == .continuousProfiling && !rumEvents.isEmpty ? .trigger : operation
        if let snapshot = closeWindow(shouldEncode: shouldWrite, operation: operation, message: message) {
            writer.write([snapshot], operation: operation)
        }
    }

    func closeWindow(
        shouldEncode: Bool = true,
        operation: ProfilingOperation = .continuousProfiling,
        message: TTIDMessage? = nil
    ) -> ProfileSnapshot? {
        defer { clearEvents() }
        var capture = dd_memory_capture_t()
        let status = dd_memory_profiler_capture(&capture)
        // Queued ticks from the preceding window must not close the new one.
        if periodicStart != nil {
            periodicStart = .now()
        }
        var result: MemoryDiagnostics.CaptureResult = .discarded
        var snapshot: ProfileSnapshot?
        switch status {
        case DD_MEMORY_CAPTURE_IDLE:
            result = .idle
            // An unchanged live set is still useful at an event boundary.
            if shouldEncode, !rumEvents.isEmpty, capture.aggregation.count > 0 {
                snapshot = makeSnapshot(from: capture, result: &result, message: message)
            }
        case DD_MEMORY_CAPTURE_READY:
            if shouldEncode {
                snapshot = makeSnapshot(from: capture, result: &result, message: message)
            }
        default:
            result = .captureFailed
            stopNative(reportDiscardedWindow: false)
            state = .failed
        }
        let diagnostics = MemoryDiagnostics.consume(
            result: result,
            payloadBytes: snapshot?.attachment.data.count ?? 0
        )
        if var snapshot {
            snapshot.memoryDiagnostics = diagnostics
            return snapshot
        }
        telemetryController.sendMemoryDiagnostics(diagnostics, for: operation)
        return nil
    }

    func makeSnapshot(
        from capture: dd_memory_capture_t,
        result: inout MemoryDiagnostics.CaptureResult,
        message: TTIDMessage? = nil
    ) -> ProfileSnapshot? {
        let offset = (message?.ttid.serverTimeOffset ?? currentContext?.serverTimeOffset ?? 0).dd.toInt64Nanoseconds
        let (start, startOverflow) = capture.time_nanos.addingReportingOverflow(offset)
        let (end, endOverflow) = start.addingReportingOverflow(capture.duration_nanos)
        guard !startOverflow, !endOverflow, start >= 0, capture.duration_nanos >= 0 else {
            result = .invalidTime
            return nil
        }
        var capture = capture
        capture.time_nanos = start
        let view = dd_memory_profiler_serialize(&capture)
        guard let bytes = view.data, view.size > 0 else {
            result = .serializationFailed
            return nil
        }
        result = .encoded
        if let message {
            mergeEventAttributes(eventAttributes.merging(message.attributes) { _, launchValue in launchValue })
        }
        // A trigger may arrive after its event ended or a periodic window closed.
        // Its correlation describes why we captured, not a slice of the heap.
        return ProfileSnapshot(
            start: Date(timeIntervalSince1970: Double(start) / 1_000_000_000),
            end: Date(timeIntervalSince1970: Double(end) / 1_000_000_000),
            attachment: PprofAttachment(
                filename: ProfileAttachments.Constants.heapPprofFilename,
                // The native encoder owns this view until the next serialization or stop.
                data: Data(bytes: bytes, count: view.size)
            ),
            rumEvents: rumEvents + (message.map { [.vital($0.ttid)] } ?? []),
            attributes: eventAttributes,
            rumContext: rumContext
        )
    }

    func discardPendingAppLaunch() {
        if var diagnostics = pendingAppLaunch?.snapshot.memoryDiagnostics {
            diagnostics.captureResult = .discarded
            telemetryController.sendMemoryDiagnostics(diagnostics, for: .appLaunch)
        }
        pendingAppLaunch = nil
    }

    func stopPeriodicCapture() {
        periodicStart = nil
        scheduler.stopPeriodic(for: self)
    }

    func stopNative(reportDiscardedWindow: Bool = true) {
        let didFail = state == .failed
        stopPeriodicCapture()
        let wasRunning = dd_memory_profiler_is_running()
        dd_memory_profiler_stop()
        if wasRunning, reportDiscardedWindow {
            let diagnostics = MemoryDiagnostics.consume(result: .stopped)
            if diagnostics.sampledAllocations > 0
                || diagnostics.reentrantSkips > 0
                || diagnostics.recordedAllocations > 0
                || diagnostics.droppedAllocRecords > 0 {
                telemetryController.sendMemoryDiagnostics(diagnostics, for: .continuousProfiling)
            }
        }
        state = didFail ? .failed : .stopped
        hasForegroundTime = false
        isRecordingAppLaunch = false
        discardPendingAppLaunch()
        clearEvents()
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
