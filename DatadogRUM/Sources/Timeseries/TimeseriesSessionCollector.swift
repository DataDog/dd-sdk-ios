/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Defines the interface for collecting timeseries data during a RUM session.
internal protocol TimeseriesCollecting: AnyObject {
    /// Provides global custom attributes, the active view, and the active session's expiry state at sample
    /// time, so the collector can self-enforce `RUMSessionScope`'s own expiry rules without maintaining a
    /// shadow copy of that state. Set by `RUMFeature` once `Monitor` is constructed, since the collector is
    /// created before it.
    var activeContextReader: RUMActiveContextReader? { get set }
    func start(sessionID: String, applicationID: String, sessionType: RUMSessionType)
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
    }

    /// A single CPU sample: usage as a percentage (0.0 to 100.0).
    private struct CPUSample {
        let timestamp: Int64
        let usage: Double
    }

    private let memoryReader: SamplingBasedVitalReader
    private let cpuUsageProvider: () -> Double?
    private let batchSize: Int
    private let collectTypes: Set<RUM.Configuration.TimeseriesType>
    private let samplingInterval: TimeInterval
    private let featureScope: FeatureScope
    private let totalRAM: Double
    private let ciTest: RUMCITest?
    private let syntheticsTest: RUMSyntheticsTest?
    private let sessionSampleRate: Double
    private let sanitizer = RUMEventSanitizer()

    /// `Monitor`'s conformance is safe to read from any thread.
    weak var activeContextReader: RUMActiveContextReader?

    private var memoryBuffer: [MemorySample] = []
    private var cpuBuffer: [CPUSample] = []
    private var sessionID: String = ""
    private var applicationID: String = ""
    private var sessionType: RUMSessionType = .user
    private var timer: DispatchSourceTimer?
    private var isPaused: Bool = false
    /// The start time of the current session, used to self-enforce `RUMSessionScope.Constants.sessionMaxDuration`
    /// even if the RUM command pipeline never notifies this collector of the session's expiry.
    private var sessionStartTime: Date = .distantPast
    /// The time of the last RUM interaction reported via `noteActivity(sessionID:at:)`, used to self-enforce
    /// `RUMSessionScope.Constants.sessionTimeoutDuration` even when the app goes idle with no RUM commands.
    private var lastActivityTime: Date = .distantPast
    private let now: () -> Date
    private let mediaTimeProvider: CACurrentMediaTimeProvider
    /// The wall-clock date and monotonic media time captured together at the start of the current session,
    /// used to derive sample timestamps that are immune to wall-clock adjustments (see `sample()`).
    private var anchorDate: Date = .distantPast
    private var anchorMediaTime: CFTimeInterval = 0
    /// The date of the most recently emitted sample, used as a floor when re-anchoring in `resume()` so a
    /// backward wall-clock jump while paused/backgrounded can't make the new anchor precede samples already
    /// flushed before the pause (see `resume(sessionID:)`).
    private var lastSampleDate: Date?
    /// Whether replay was reported active by `activeContextReader` at any point during the current session,
    /// OR-accumulated in `sample()` (mirrors `RUMViewScope`'s per-view `hasReplay` accumulation) so a batch
    /// still reports `hasReplay: true` even if replay stopped before the batch was flushed. Stays `nil` until
    /// a value has actually been observed, so sessions with no Session Replay context still omit the field
    /// instead of reporting a false `false`.
    private var hasReplay: Bool? = nil

    /// All buffer mutations and timer events run on this queue.
    private let queue = DispatchQueue(label: "com.datadoghq.timeseries-collector", qos: .utility)

    init(
        memoryReader: SamplingBasedVitalReader,
        featureScope: FeatureScope,
        batchSize: Int = 120,
        collectTypes: Set<RUM.Configuration.TimeseriesType> = Set(RUM.Configuration.TimeseriesType.allCases),
        samplingInterval: TimeInterval = 1,
        cpuUsageProvider: (() -> Double?)? = nil,
        totalRAM: Double = Double(ProcessInfo.processInfo.physicalMemory),
        ciTest: RUMCITest? = nil,
        syntheticsTest: RUMSyntheticsTest? = nil,
        sessionSampleRate: Double = 100,
        now: @escaping () -> Date = Date.init,
        mediaTimeProvider: CACurrentMediaTimeProvider = MediaTimeProvider()
    ) {
        self.memoryReader = memoryReader
        self.batchSize = max(2, batchSize)
        self.collectTypes = collectTypes
        self.samplingInterval = samplingInterval
        self.featureScope = featureScope
        self.totalRAM = totalRAM
        self.ciTest = ciTest
        self.syntheticsTest = syntheticsTest
        self.sessionSampleRate = sessionSampleRate
        self.cpuUsageProvider = cpuUsageProvider ?? { TimeseriesSessionCollector.processCPU() }
        self.now = now
        self.mediaTimeProvider = mediaTimeProvider
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
    func start(sessionID: String, applicationID: String, sessionType: RUMSessionType) {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }
            self.flushMemory()
            self.flushCPU()
            self.sessionID = sessionID
            self.applicationID = applicationID
            self.sessionType = sessionType
            self.memoryBuffer = []
            self.cpuBuffer = []
            self.isPaused = false
            self.hasReplay = nil
            self.anchorDate = self.now()
            self.anchorMediaTime = self.mediaTimeProvider.current
            self.lastSampleDate = nil

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
            if self.isPaused {
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
            // Re-anchor to the current wall/media time pair so a pause spanning real device sleep (during
            // which the monotonic media clock doesn't advance) doesn't offset post-resume sample timestamps
            // backward by the sleep duration. Clamped to `lastSampleDate` so a wall-clock jump *backward*
            // while paused can't make the new anchor precede samples already flushed before the pause —
            // preserving monotonicity across the pause/resume boundary in both directions.
            let resumeDate = self.now()
            self.anchorDate = max(resumeDate, self.lastSampleDate ?? resumeDate)
            self.anchorMediaTime = self.mediaTimeProvider.current
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

    private func makeTimer() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + samplingInterval, repeating: samplingInterval)
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
        return timer
    }

    // MARK: - Private

    private func sample() {
        // Derived from the monotonic media clock anchored at session start, rather than raw `now()`, so a
        // backward wall-clock adjustment mid-session (NTP sync, manual clock change) can't produce
        // out-of-order or inverted (`end < start`) batch timestamps.
        let currentDate = anchorDate.addingTimeInterval(mediaTimeProvider.current - anchorMediaTime)
        lastSampleDate = currentDate

        if let hasContextReplay = activeContextReader?.hasReplay {
            hasReplay = (hasReplay ?? false) || hasContextReplay
        }

        // Self-enforce the same session lifetime rules `RUMSessionScope` uses, in case this session
        // has expired without any RUM command arriving to call `stop(sessionID:)` (e.g. the app went
        // idle with no user interaction). This is a safety net only — it does not affect RUM's own
        // session state, it just stops this collector from uploading data past session expiry.
        //
        // Pulled fresh from `activeContextReader` on every tick, rather than from a locally pushed
        // copy, so there's a single live source of truth and no race with how/when that state is updated.
        //
        // Compared against `now()`, not the anchored `currentDate`, because `sessionStartTime`/
        // `lastInteractionTime` on the `Monitor` side are wall-clock `Date`s — comparing them against the
        // sleep/adjustment-immune anchored date would reintroduce spurious expiry on the very same backward
        // clock jumps this anchoring is meant to guard against.
        if activeContextReader?.isSessionExpired(sessionID: sessionID, at: now()) == true {
            timer?.cancel()
            timer = nil
            flushMemory()
            flushCPU()
            return
        }

        let timestamp = Int64.ddWithNoOverflow(currentDate.timeIntervalSince1970 * 1_000_000_000)

        if collectTypes.contains(.memory), let bytes = memoryReader.readVitalData() {
            let footprintKB = bytes / 1_024
            let memoryPercent = totalRAM > 0 ? bytes / totalRAM * 100 : 0
            memoryBuffer.append(MemorySample(timestamp: timestamp, footprintKB: footprintKB, percent: memoryPercent))
            if memoryBuffer.count >= batchSize {
                flushMemory()
            }
        }

        if collectTypes.contains(.cpu), let cpuUsage = cpuUsageProvider() {
            cpuBuffer.append(CPUSample(timestamp: timestamp, usage: cpuUsage))
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
        let sessionSampleRate = self.sessionSampleRate
        let hasReplay = self.hasReplay
        let start = batch[0].timestamp
        let end = batch[batch.count - 1].timestamp
        let eventID = UUID().uuidString.lowercased()

        featureScope.eventWriteContext { context, writer in
            let offsetNs = context.serverTimeOffset.dd.toInt64Nanoseconds
            let timestamps = batch.map { $0.timestamp + offsetNs }
            let adjustedStart = start + offsetNs
            let adjustedEnd = end + offsetNs
            let event = RUMTimeseriesMemoryEvent(
                dd: .init(configuration: .init(sessionSampleRate: sessionSampleRate)),
                application: .init(id: applicationID),
                buildId: context.buildId,
                buildVersion: context.buildNumber,
                ciTest: ciTest,
                date: (Double(start) / 1_000_000_000 + context.serverTimeOffset).dd.toInt64Milliseconds,
                ddtags: context.ddTags,
                device: context.normalizedDevice(),
                os: context.os,
                service: context.service,
                session: .init(hasReplay: hasReplay, id: sessionID, type: sessionType),
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
                version: context.version
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
        let sessionSampleRate = self.sessionSampleRate
        let hasReplay = self.hasReplay
        let start = batch[0].timestamp
        let end = batch[batch.count - 1].timestamp
        let eventID = UUID().uuidString.lowercased()

        featureScope.eventWriteContext { context, writer in
            let offsetNs = context.serverTimeOffset.dd.toInt64Nanoseconds
            let timestamps = batch.map { $0.timestamp + offsetNs }
            let adjustedStart = start + offsetNs
            let adjustedEnd = end + offsetNs
            let event = RUMTimeseriesCpuEvent(
                dd: .init(configuration: .init(sessionSampleRate: sessionSampleRate)),
                application: .init(id: applicationID),
                buildId: context.buildId,
                buildVersion: context.buildNumber,
                ciTest: ciTest,
                date: (Double(start) / 1_000_000_000 + context.serverTimeOffset).dd.toInt64Milliseconds,
                ddtags: context.ddTags,
                device: context.normalizedDevice(),
                os: context.os,
                service: context.service,
                session: .init(hasReplay: hasReplay, id: sessionID, type: sessionType),
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
                version: context.version
            )
            writer.write(value: self.sanitizer.sanitize(event: event))
        }
    }
}
