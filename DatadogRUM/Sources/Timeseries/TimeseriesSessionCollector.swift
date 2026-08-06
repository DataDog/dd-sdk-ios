/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Defines the interface for collecting timeseries data during a RUM session.
internal protocol TimeseriesCollecting: AnyObject {
    func start(sessionID: String, applicationID: String, sessionType: RUMSessionType, startTime: Date)
    func pause(sessionID: String)
    func resume(sessionID: String)
    func stop(sessionID: String)
    /// Reports that a RUM interaction was just processed, so the collector can self-enforce
    /// the session inactivity timeout even if no further commands ever arrive to call `stop(sessionID:)`.
    func noteActivity(sessionID: String, at time: Date)
    /// Synchronously flushes any buffered samples. **Blocks the caller thread.**
    func flush()
}

/// Collects memory and CPU samples at configurable intervals (default: 1 s) during a RUM session and flushes them
/// as `RUMTimeseriesMemoryEvent` / `RUMTimeseriesCpuEvent` batches via the RUM feature scope.
internal class TimeseriesSessionCollector: TimeseriesCollecting {
    /// A single memory sample: physical memory footprint in kilobytes and its percentage of total device RAM.
    private struct MemorySample {
        let timestamp: Int64
        let footprintKB: Double
        let percent: Double
        /// The view active when this sample was collected, if any.
        let viewID: String?
        let viewPath: String?
        let viewName: String?
    }

    /// A single CPU sample: usage as a percentage (0.0 to 100.0).
    private struct CPUSample {
        let timestamp: Int64
        let usage: Double
        /// The view active when this sample was collected, if any.
        let viewID: String?
        let viewPath: String?
        let viewName: String?
    }

    private let memoryReader: SamplingBasedVitalReader
    private let cpuUsageProvider: () -> Double?
    private let batchSize: Int
    private let samplingInterval: TimeInterval
    private let featureScope: FeatureScope
    private let totalRAM: Double
    private let ciTest: RUMCITest?
    private let syntheticsTest: RUMSyntheticsTest?
    private let sessionSampleRate: Double
    private let sanitizer = RUMEventSanitizer()

    /// Provides global custom attributes and the active view at sample time. Set by `RUMFeature` once `Monitor`
    /// is constructed, since the collector is created before it. `Monitor`'s conformance is safe to read from
    /// any thread.
    weak var activeContextReader: RUMActiveContextReader?

    private var memoryBuffer: [MemorySample] = []
    private var cpuBuffer: [CPUSample] = []
    private var sessionID: String = ""
    private var applicationID: String = ""
    private var sessionType: RUMSessionType = .user
    private var timer: DispatchSourceTimer?
    private var isPaused: Bool = false
    /// The view ID of the samples currently buffered, so a view change can trigger a flush before
    /// mixing samples from two different views into the same batch. `nil` means either no view was
    /// active yet, or no sample has been buffered since the last flush.
    private var currentBatchViewID: String?
    /// The start time of the current session, used to self-enforce `RUMSessionScope.Constants.sessionMaxDuration`
    /// even if the RUM command pipeline never notifies this collector of the session's expiry.
    private var sessionStartTime: Date = .distantPast
    /// The time of the last RUM interaction reported via `noteActivity(sessionID:at:)`, used to self-enforce
    /// `RUMSessionScope.Constants.sessionTimeoutDuration` even when the app goes idle with no RUM commands.
    private var lastActivityTime: Date = .distantPast
    private let now: () -> Date

    /// All buffer mutations and timer events run on this queue.
    private let queue = DispatchQueue(label: "com.datadoghq.timeseries-collector", qos: .utility)

    init(
        memoryReader: SamplingBasedVitalReader,
        featureScope: FeatureScope,
        batchSize: Int = 120,
        samplingInterval: TimeInterval = 1,
        cpuUsageProvider: (() -> Double?)? = nil,
        totalRAM: Double = Double(ProcessInfo.processInfo.physicalMemory),
        ciTest: RUMCITest? = nil,
        syntheticsTest: RUMSyntheticsTest? = nil,
        sessionSampleRate: Double = 100,
        now: @escaping () -> Date = Date.init
    ) {
        self.memoryReader = memoryReader
        self.batchSize = max(2, batchSize)
        self.samplingInterval = samplingInterval
        self.featureScope = featureScope
        self.totalRAM = totalRAM
        self.ciTest = ciTest
        self.syntheticsTest = syntheticsTest
        self.sessionSampleRate = sessionSampleRate
        self.cpuUsageProvider = cpuUsageProvider ?? { TimeseriesSessionCollector.processCPU() }
        self.now = now
    }

    deinit {
        timer?.cancel()
    }

    /// Per-process CPU as a percentage (0–100+), summed across all app threads.
    /// Separated into a static so it can be called from the init closure without capturing self.
    private static func processCPU() -> Double? {
        #if os(watchOS)
        return nil
        #else
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t()
        let kr = withUnsafeMutablePointer(to: &threadsList) {
            $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadsCount)
            }
        }
        guard kr == KERN_SUCCESS, let threadsList = threadsList else {
            return nil
        }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: threadsList),
                vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride)
            )
        }
        var total = 0.0
        for i in 0..<threadsCount {
            defer {
                mach_port_deallocate(mach_task_self_, threadsList[Int(i)])
            }
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threadsList[Int(i)], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            guard kr == KERN_SUCCESS, info.flags != TH_FLAGS_IDLE else {
                continue
            }
            total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
        }
        return min(total, 100.0)
        #endif
    }

    /// Resets state, flips the compression coin, and starts the sampling timer for the new session.
    func start(sessionID: String, applicationID: String, sessionType: RUMSessionType, startTime: Date = Date()) {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }
            self.flushMemory()
            self.flushCPU()
            self.sessionID = sessionID
            self.applicationID = applicationID
            self.sessionType = sessionType
            self.sessionStartTime = startTime
            self.lastActivityTime = startTime
            self.memoryBuffer = []
            self.cpuBuffer = []
            self.isPaused = false
            self.currentBatchViewID = nil

            self.timer?.cancel()
            self.timer = self.makeTimer()
        }
    }

    /// Suspends sampling and flushes buffered data. Session state is preserved for `resume()`. Idempotent.
    /// No-ops if `sessionID` no longer matches the currently active session (e.g. a call left over from a
    /// session that has since ended and been replaced — see `RUMSessionScope.Constants` for expiry rules).
    func pause(sessionID: String) {
        queue.async { [weak self] in
            guard let self = self, self.sessionID == sessionID else {
                return
            }
            if self.isPaused || self.timer == nil {
                return
            }
            self.timer?.cancel()
            self.timer = nil
            self.isPaused = true
            self.flushMemory()
            self.flushCPU()
        }
    }

    /// Resumes sampling after `pause()`. Idempotent — only takes effect if currently paused.
    /// No-ops if `sessionID` no longer matches the currently active session.
    func resume(sessionID: String) {
        queue.async { [weak self] in
            guard let self = self, self.sessionID == sessionID, self.isPaused else {
                return
            }
            self.isPaused = false
            self.timer = self.makeTimer()
        }
    }

    /// Stops sampling and flushes any remaining buffered data points.
    /// No-ops if `sessionID` no longer matches the currently active session.
    func stop(sessionID: String) {
        queue.async { [weak self] in
            guard let self = self, self.sessionID == sessionID else {
                return
            }
            self.timer?.cancel()
            self.timer = nil
            self.isPaused = false
            self.flushMemory()
            self.flushCPU()
        }
    }

    /// Synchronously flushes any buffered samples without stopping or pausing sampling. **Blocks the caller thread.**
    func flush() {
        queue.sync {
            flushMemory()
            flushCPU()
        }
    }

    /// Records that a RUM interaction happened, resetting the inactivity clock this collector uses to
    /// self-enforce `RUMSessionScope.Constants.sessionTimeoutDuration` (see `sample()`).
    /// No-ops if `sessionID` no longer matches the currently active session.
    func noteActivity(sessionID: String, at time: Date) {
        queue.async { [weak self] in
            guard let self = self, self.sessionID == sessionID else {
                return
            }
            self.lastActivityTime = time
        }
    }

    /// Returns the most recently active view among the given samples, searching from the end of the batch
    /// backwards, or `nil` if no sample in the batch had a view.
    private static func lastKnownView(
        in samples: [(viewID: String?, viewPath: String?, viewName: String?)]
    ) -> (id: String, path: String, name: String?)? {
        for sample in samples.reversed() {
            if let id = sample.viewID {
                return (id: id, path: sample.viewPath ?? "", name: sample.viewName)
            }
        }
        return nil
    }

    private func makeTimer() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + samplingInterval, repeating: samplingInterval)
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
        return timer
    }

    // MARK: - Private

    private func sample() {
        let currentDate = now()

        // Self-enforce the same session lifetime rules `RUMSessionScope` uses, in case this session
        // has expired without any RUM command arriving to call `stop(sessionID:)` (e.g. the app went
        // idle with no user interaction). This is a safety net only — it does not affect RUM's own
        // session state, it just stops this collector from uploading data past session expiry.
        let sessionExceededMaxDuration = currentDate.timeIntervalSince(sessionStartTime) >= RUMSessionScope.Constants.sessionMaxDuration
        let sessionExceededInactivityTimeout = currentDate.timeIntervalSince(lastActivityTime) >= RUMSessionScope.Constants.sessionTimeoutDuration
        if sessionExceededMaxDuration || sessionExceededInactivityTimeout {
            timer?.cancel()
            timer = nil
            flushMemory()
            flushCPU()
            return
        }

        let timestamp = Int64.ddWithNoOverflow(currentDate.timeIntervalSince1970 * 1_000_000_000)
        let activeView = activeContextReader?.activeView
        let viewID = activeView?.id
        let viewPath = activeView?.path
        let viewName = activeView?.name

        // Flush before mixing samples from two different views into the same batch, so each batch
        // (and the RUM view it's attributed to) reflects a single view rather than whichever view
        // happened to be active at the last sample or at flush time.
        if viewID != currentBatchViewID {
            flushMemory()
            flushCPU()
        }
        currentBatchViewID = viewID

        if let bytes = memoryReader.readVitalData() {
            let footprintKB = bytes / 1_024
            let memoryPercent = totalRAM > 0 ? bytes / totalRAM * 100 : 0
            memoryBuffer.append(
                MemorySample(
                    timestamp: timestamp,
                    footprintKB: footprintKB,
                    percent: memoryPercent,
                    viewID: viewID,
                    viewPath: viewPath,
                    viewName: viewName
                )
            )
            if memoryBuffer.count >= batchSize {
                flushMemory()
            }
        }

        if let cpuUsage = cpuUsageProvider() {
            cpuBuffer.append(CPUSample(timestamp: timestamp, usage: cpuUsage, viewID: viewID, viewPath: viewPath, viewName: viewName))
            if cpuBuffer.count >= batchSize {
                flushCPU()
            }
        }
    }

    private func flushMemory() {
        guard !memoryBuffer.isEmpty else {
            return
        }
        let batch = memoryBuffer
        memoryBuffer = []
        let sessionID = self.sessionID
        let applicationID = self.applicationID
        let sessionType = self.sessionType
        let ciTest = self.ciTest
        let syntheticsTest = self.syntheticsTest
        let globalAttributes = self.activeContextReader?.globalAttributes ?? [:]
        let sessionSampleRate = self.sessionSampleRate
        let start = batch[0].timestamp
        let end = batch[batch.count - 1].timestamp
        let eventID = UUID().uuidString.lowercased()

        // The batch is attributed to the most recently active view among its samples, not the view active
        // at flush time — a view ending right before a scheduled flush shouldn't drop data that was
        // genuinely collected while it was active. `view` is left `nil` if no sample in the batch had one
        // (e.g. samples collected before the first view starts), rather than dropping the batch.
        let view = Self.lastKnownView(
            in: batch.map { (viewID: $0.viewID, viewPath: $0.viewPath, viewName: $0.viewName) }
        )

        featureScope.eventWriteContext { context, writer in
            let offsetNs = context.serverTimeOffset.dd.toInt64Nanoseconds
            let timestamps = batch.map { $0.timestamp + offsetNs }
            let adjustedStart = start + offsetNs
            let adjustedEnd = end + offsetNs
            let event = RUMTimeseriesMemoryEvent(
                dd: .init(configuration: .init(sessionSampleRate: sessionSampleRate)),
                account: .init(context: context),
                application: .init(id: applicationID),
                buildId: context.buildId,
                buildVersion: context.buildNumber,
                ciTest: ciTest,
                connectivity: .init(context: context),
                context: .init(contextInfo: globalAttributes),
                date: (Double(start) / 1_000_000_000 + context.serverTimeOffset).dd.toInt64Milliseconds,
                ddtags: context.ddTags,
                device: context.normalizedDevice(),
                os: context.os,
                service: context.service,
                session: .init(hasReplay: context.hasReplay, id: sessionID, type: sessionType),
                source: .init(rawValue: context.source) ?? .ios,
                synthetics: syntheticsTest,
                timeseries: .init(
                    data: .init(
                        timestamps: timestamps,
                        values: .init(
                            memoryFootprint: batch.map { $0.footprintKB },
                            memoryPercent: batch.map { $0.percent }
                        )
                    ),
                    end: adjustedEnd,
                    id: eventID,
                    start: adjustedStart
                ),
                usr: .init(context: context),
                version: context.version,
                view: view.map { .init(id: $0.id, name: $0.name, url: $0.path) }
            )
            writer.write(value: self.sanitizer.sanitize(event: event))
        }
    }

    private func flushCPU() {
        guard !cpuBuffer.isEmpty else {
            return
        }
        let batch = cpuBuffer
        cpuBuffer = []
        let sessionID = self.sessionID
        let applicationID = self.applicationID
        let sessionType = self.sessionType
        let ciTest = self.ciTest
        let syntheticsTest = self.syntheticsTest
        let globalAttributes = self.activeContextReader?.globalAttributes ?? [:]
        let sessionSampleRate = self.sessionSampleRate
        let start = batch[0].timestamp
        let end = batch[batch.count - 1].timestamp
        let eventID = UUID().uuidString.lowercased()

        // The batch is attributed to the most recently active view among its samples, not the view active
        // at flush time — a view ending right before a scheduled flush shouldn't drop data that was
        // genuinely collected while it was active. `view` is left `nil` if no sample in the batch had one
        // (e.g. samples collected before the first view starts), rather than dropping the batch.
        let view = Self.lastKnownView(
            in: batch.map { (viewID: $0.viewID, viewPath: $0.viewPath, viewName: $0.viewName) }
        )

        featureScope.eventWriteContext { context, writer in
            let offsetNs = context.serverTimeOffset.dd.toInt64Nanoseconds
            let timestamps = batch.map { $0.timestamp + offsetNs }
            let adjustedStart = start + offsetNs
            let adjustedEnd = end + offsetNs
            let event = RUMTimeseriesCpuEvent(
                dd: .init(configuration: .init(sessionSampleRate: sessionSampleRate)),
                account: .init(context: context),
                application: .init(id: applicationID),
                buildId: context.buildId,
                buildVersion: context.buildNumber,
                ciTest: ciTest,
                connectivity: .init(context: context),
                context: .init(contextInfo: globalAttributes),
                date: (Double(start) / 1_000_000_000 + context.serverTimeOffset).dd.toInt64Milliseconds,
                ddtags: context.ddTags,
                device: context.normalizedDevice(),
                os: context.os,
                service: context.service,
                session: .init(hasReplay: context.hasReplay, id: sessionID, type: sessionType),
                source: .init(rawValue: context.source) ?? .ios,
                synthetics: syntheticsTest,
                timeseries: .init(
                    data: .init(
                        timestamps: timestamps,
                        values: .init(cpuUsage: batch.map { $0.usage })
                    ),
                    end: adjustedEnd,
                    id: eventID,
                    start: adjustedStart
                ),
                usr: .init(context: context),
                version: context.version,
                view: view.map { .init(id: $0.id, name: $0.name, url: $0.path) }
            )
            writer.write(value: self.sanitizer.sanitize(event: event))
        }
    }
}
