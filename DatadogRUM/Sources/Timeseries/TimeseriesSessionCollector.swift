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
///
/// At session start a coin is flipped: 50% of sessions send full-array `object` schema events,
/// 50% send delta-compressed events (`delta-object` for memory, `delta-scalar` for CPU).
internal class TimeseriesSessionCollector: TimeseriesCollecting {
    private let memoryReader: SamplingBasedVitalReader
    private let cpuUsageProvider: () -> Double?
    private let compressionSampler: () -> Bool
    private let batchSize: Int
    private let samplingInterval: TimeInterval
    private let collectInBackground: Bool
    private let featureScope: FeatureScope
    private let totalRAM: Double

    private var memoryBuffer: [RUMTimeseriesMemoryEvent.Timeseries.Data] = []
    private var cpuBuffer: [RUMTimeseriesCpuEvent.Timeseries.Data] = []
    private var sessionID: String = ""
    private var applicationID: String = ""
    private var sessionType: RUMSessionType = .user
    private var useDeltaCompression: Bool = false
    private var timer: DispatchSourceTimer?
    private var isPaused: Bool = false

    /// All buffer mutations and timer events run on this queue.
    private let queue = DispatchQueue(label: "com.datadoghq.timeseries-collector", qos: .utility)

    init(
        memoryReader: SamplingBasedVitalReader,
        featureScope: FeatureScope,
        batchSize: Int = 30,
        samplingInterval: TimeInterval = 1,
        collectInBackground: Bool = false,
        cpuUsageProvider: (() -> Double?)? = nil,
        compressionSampler: @escaping () -> Bool = { Bool.random() },
        totalRAM: Double = Double(ProcessInfo.processInfo.physicalMemory)
    ) {
        self.memoryReader = memoryReader
        self.batchSize = batchSize
        self.samplingInterval = samplingInterval
        self.collectInBackground = collectInBackground
        self.featureScope = featureScope
        self.totalRAM = totalRAM
        self.cpuUsageProvider = cpuUsageProvider ?? { TimeseriesSessionCollector.processCPU() }
        self.compressionSampler = compressionSampler
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
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(threadsList[Int(i)], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            guard kr == KERN_SUCCESS, info.flags != TH_FLAGS_IDLE else {
                continue
            }
            total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
        }
        return total
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
            self.useDeltaCompression = self.compressionSampler()
            self.memoryBuffer = []
            self.cpuBuffer = []
            self.isPaused = false

            self.timer?.cancel()
            self.timer = self.makeTimer()
        }
    }

    /// Suspends sampling and flushes buffered data. Session state is preserved for `resume()`. Idempotent.
    /// No-op when `collectInBackground` is `true`.
    func pause() {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }
            if self.collectInBackground || self.isPaused || self.timer == nil {
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

        if let bytes = memoryReader.readVitalData() {
            let memoryPercent = totalRAM > 0 ? bytes / totalRAM * 100 : 0
            let dataPoint = RUMTimeseriesMemoryEvent.Timeseries.Data(
                dataPoint: .init(memoryFootprint: bytes, memoryPercent: memoryPercent),
                timestamp: now
            )
            memoryBuffer.append(dataPoint)
            if memoryBuffer.count >= batchSize {
                flushMemory()
            }
        }

        if let cpuUsage = cpuUsageProvider() {
            let dataPoint = RUMTimeseriesCpuEvent.Timeseries.Data(
                dataPoint: .init(cpuUsage: cpuUsage),
                timestamp: now
            )
            cpuBuffer.append(dataPoint)
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
        let start = batch[0].timestamp
        let end = batch[batch.count - 1].timestamp
        let eventID = UUID().uuidString.lowercased()
        let useDelta = self.useDeltaCompression

        featureScope.eventWriteContext { context, writer in
            let offsetNs = context.serverTimeOffset.dd.toInt64Nanoseconds
            let adjustedBatch = batch.map { sample in
                RUMTimeseriesMemoryEvent.Timeseries.Data(
                    dataPoint: sample.dataPoint,
                    timestamp: sample.timestamp + offsetNs
                )
            }
            let adjustedStart = start + offsetNs
            let adjustedEnd = end + offsetNs
            let objectEvent = RUMTimeseriesMemoryEvent(
                dd: .init(),
                application: .init(id: applicationID),
                date: (Double(start) / 1_000_000_000 + context.serverTimeOffset).dd.toInt64Milliseconds,
                service: context.service,
                session: .init(id: sessionID, type: sessionType),
                source: .init(rawValue: context.source) ?? .ios,
                timeseries: .init(
                    data: adjustedBatch,
                    end: adjustedEnd,
                    id: eventID,
                    name: "memory",
                    schema: .object,
                    start: adjustedStart
                ),
                version: context.version
            )

            if useDelta {
                if let deltaData = DeltaEncoder.encodeMemory(adjustedBatch),
                   let eventData = try? JSONEncoder().encode(objectEvent),
                   var dict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                   var ts = dict["timeseries"] as? [String: Any] {
                    ts["schema"] = "delta-object"
                    ts["data"] = deltaData
                    dict["timeseries"] = ts
                    writer.write(value: AnyEncodable(dict))
                }
            } else {
                writer.write(value: objectEvent)
            }
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
        let start = batch[0].timestamp
        let end = batch[batch.count - 1].timestamp
        let eventID = UUID().uuidString.lowercased()
        let useDelta = self.useDeltaCompression

        featureScope.eventWriteContext { context, writer in
            let offsetNs = context.serverTimeOffset.dd.toInt64Nanoseconds
            let adjustedBatch = batch.map { sample in
                RUMTimeseriesCpuEvent.Timeseries.Data(
                    dataPoint: sample.dataPoint,
                    timestamp: sample.timestamp + offsetNs
                )
            }
            let adjustedStart = start + offsetNs
            let adjustedEnd = end + offsetNs
            let objectEvent = RUMTimeseriesCpuEvent(
                dd: .init(),
                application: .init(id: applicationID),
                date: (Double(start) / 1_000_000_000 + context.serverTimeOffset).dd.toInt64Milliseconds,
                service: context.service,
                session: .init(id: sessionID, type: sessionType),
                source: .init(rawValue: context.source) ?? .ios,
                timeseries: .init(
                    data: adjustedBatch,
                    end: adjustedEnd,
                    id: eventID,
                    name: "cpu",
                    schema: .object,
                    start: adjustedStart
                ),
                version: context.version
            )

            if useDelta {
                if let deltaData = DeltaEncoder.encodeCPU(adjustedBatch),
                   let eventData = try? JSONEncoder().encode(objectEvent),
                   var dict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                   var ts = dict["timeseries"] as? [String: Any] {
                    ts["schema"] = "delta-scalar"
                    ts["data"] = deltaData
                    dict["timeseries"] = ts
                    writer.write(value: AnyEncodable(dict))
                }
            } else {
                writer.write(value: objectEvent)
            }
        }
    }
}
