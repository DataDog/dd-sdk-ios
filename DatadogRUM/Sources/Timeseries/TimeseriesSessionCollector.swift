/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Defines the interface for collecting timeseries data during a RUM session.
internal protocol TimeseriesCollecting: AnyObject {
    func start(sessionID: String, applicationID: String, sessionType: RUMSessionType)
    func pause()
    func resume()
    func stop()
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
        sessionSampleRate: Double = 100
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

            self.timer?.cancel()
            self.timer = self.makeTimer()
        }
    }

    /// Suspends sampling and flushes buffered data. Session state is preserved for `resume()`. Idempotent.
    func pause() {
        queue.async { [weak self] in
            guard let self = self else {
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
    func resume() {
        queue.async { [weak self] in
            guard let self = self, self.isPaused else {
                return
            }
            self.isPaused = false
            self.timer = self.makeTimer()
        }
    }

    /// Stops sampling and flushes any remaining buffered data points.
    func stop() {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }
            self.timer?.cancel()
            self.timer = nil
            self.isPaused = false
            self.flushMemory()
            self.flushCPU()
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
        let now = Int64.ddWithNoOverflow(Date().timeIntervalSince1970 * 1_000_000_000)
        let activeView = activeContextReader?.activeView
        let viewID = activeView?.id
        let viewPath = activeView?.path
        let viewName = activeView?.name

        if let bytes = memoryReader.readVitalData() {
            let footprintKB = bytes / 1_024
            let memoryPercent = totalRAM > 0 ? bytes / totalRAM * 100 : 0
            memoryBuffer.append(
                MemorySample(
                    timestamp: now,
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
            cpuBuffer.append(CPUSample(timestamp: now, usage: cpuUsage, viewID: viewID, viewPath: viewPath, viewName: viewName))
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
        // genuinely collected while it was active. Only dropped if no sample in the batch had a view.
        guard let view = Self.lastKnownView(
            in: batch.map { (viewID: $0.viewID, viewPath: $0.viewPath, viewName: $0.viewName) }
        ) else {
            return
        }

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
                view: .init(id: view.id, name: view.name, url: view.path)
            )
            writer.write(value: event)
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
        // genuinely collected while it was active. Only dropped if no sample in the batch had a view.
        guard let view = Self.lastKnownView(
            in: batch.map { (viewID: $0.viewID, viewPath: $0.viewPath, viewName: $0.viewName) }
        ) else {
            return
        }

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
                view: .init(id: view.id, name: view.name, url: view.path)
            )
            writer.write(value: event)
        }
    }
}
