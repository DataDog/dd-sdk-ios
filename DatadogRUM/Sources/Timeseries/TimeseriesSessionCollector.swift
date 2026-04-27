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
    func stop()
}

/// Collects memory and CPU samples at 1s intervals during a RUM session and flushes them
/// as `RUMTimeseriesMemoryEvent` / `RUMTimeseriesCpuEvent` batches via the RUM feature scope.
///
/// Each flush sends two events per metric: one with `schema: .object` (full array) and one with
/// the delta-compressed schema (`schema: .deltaObject` for memory, `schema: .deltaScalar` for CPU).
internal class TimeseriesSessionCollector: TimeseriesCollecting {
    private let memoryReader: SamplingBasedVitalReader
    private let cpuUsageProvider: () -> Double?
    private let batchSize: Int
    private let samplingInterval: TimeInterval
    private let featureScope: FeatureScope
    private let totalRAM: Double

    private var memoryBuffer: [RUMTimeseriesMemoryEvent.Timeseries.Data] = []
    private var cpuBuffer: [RUMTimeseriesCpuEvent.Timeseries.Data] = []
    private var sessionID: String = ""
    private var applicationID: String = ""
    private var sessionType: RUMSessionType = .user
    private var timer: DispatchSourceTimer?

    /// All buffer mutations and timer events run on this queue.
    private let queue = DispatchQueue(label: "com.datadoghq.timeseries-collector", qos: .utility)

    init(
        memoryReader: SamplingBasedVitalReader,
        featureScope: FeatureScope,
        batchSize: Int = 30,
        samplingInterval: TimeInterval = 1,
        cpuUsageProvider: (() -> Double?)? = nil
    ) {
        self.memoryReader = memoryReader
        self.batchSize = batchSize
        self.samplingInterval = samplingInterval
        self.featureScope = featureScope
        self.totalRAM = Double(ProcessInfo.processInfo.physicalMemory)
        self.cpuUsageProvider = cpuUsageProvider ?? { TimeseriesSessionCollector.processCPU() }
    }

    /// Per-process CPU as a percentage (0–100+), summed across all app threads.
    /// Separated into a static so it can be called from the init closure without capturing self.
    private static func processCPU() -> Double? {
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
    }

    /// Resets state and starts a 1s sampling timer for the new session.
    func start(sessionID: String, applicationID: String, sessionType: RUMSessionType) {
        queue.async { [weak self] in
            guard let self = self else {
                return
            }
            self.sessionID = sessionID
            self.applicationID = applicationID
            self.sessionType = sessionType
            self.memoryBuffer = []
            self.cpuBuffer = []

            self.timer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + samplingInterval, repeating: samplingInterval)
            timer.setEventHandler { [weak self] in self?.sample() }
            timer.resume()
            self.timer = timer
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
            self.flushMemory()
            self.flushCPU()
        }
    }

    // MARK: - Private

    private func sample() {
        let now = Int64(Date().timeIntervalSince1970 * 1_000_000_000)

        if let bytes = memoryReader.readVitalData() {
            let memoryPercent = totalRAM > 0 ? bytes / totalRAM * 100 : 0
            let dataPoint = RUMTimeseriesMemoryEvent.Timeseries.Data(
                dataPoint: .init(memoryMax: bytes, memoryPercent: memoryPercent),
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

        featureScope.eventWriteContext { context, writer in
            // object schema — full array of data points
            let objectEvent = RUMTimeseriesMemoryEvent(
                dd: .init(),
                application: .init(id: applicationID),
                date: start / 1_000_000,
                service: context.service,
                session: .init(id: sessionID, type: sessionType),
                source: .ios,
                timeseries: .init(
                    data: batch,
                    end: end,
                    id: eventID,
                    name: "memory",
                    schema: .object,
                    start: start
                ),
                version: context.version
            )
            writer.write(value: objectEvent)

            // delta-object schema — columnar delta-compressed payload
            if let deltaData = DeltaEncoder.encodeMemory(batch),
               let eventData = try? JSONEncoder().encode(objectEvent),
               var dict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
               var ts = dict["timeseries"] as? [String: Any] {
                ts["schema"] = "delta-object"
                ts["data"] = deltaData
                dict["timeseries"] = ts
                writer.write(value: AnyEncodable(dict))
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

        featureScope.eventWriteContext { context, writer in
            // object schema — full array of data points
            let objectEvent = RUMTimeseriesCpuEvent(
                dd: .init(),
                application: .init(id: applicationID),
                date: start / 1_000_000,
                service: context.service,
                session: .init(id: sessionID, type: sessionType),
                source: .ios,
                timeseries: .init(
                    data: batch,
                    end: end,
                    id: eventID,
                    name: "cpu",
                    schema: .object,
                    start: start
                ),
                version: context.version
            )
            writer.write(value: objectEvent)

            // delta-scalar schema — columnar delta-compressed payload
            if let deltaData = DeltaEncoder.encodeCPU(batch),
               let eventData = try? JSONEncoder().encode(objectEvent),
               var dict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
               var ts = dict["timeseries"] as? [String: Any] {
                ts["schema"] = "delta-scalar"
                ts["data"] = deltaData
                dict["timeseries"] = ts
                writer.write(value: AnyEncodable(dict))
            }
        }
    }
}
