/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)
@_implementationOnly import DatadogMachProfiler

/// Numeric memory diagnostics captured before the next window or teardown can replace them.
internal struct MemoryDiagnostics: Encodable {
    /// Result of a memory profiling capture attempt.
    enum CaptureResult: String, Encodable {
        case encoded
        case idle
        case discarded
        case stopped
        case startFailed = "start_failed"
        case captureFailed = "capture_failed"
        case serializationFailed = "serialization_failed"
        case invalidTime = "invalid_time"
    }

    var captureResult: CaptureResult
    let payloadBytes: Int
    let averageProbeLength: Double
    let sampledAllocations: UInt64
    let reentrantSkips: UInt64
    let recordedAllocations: UInt64
    let droppedAllocRecords: UInt64
    let liveOccupancy: UInt64
    let peakLiveOccupancy: UInt64
    let droppedSamples: UInt64
    let tombstones: UInt64
    let maxProbeLength: UInt64
    let recorderStorageBytes: UInt64
    let encoderStorageBytes: UInt64
    let swiftInstallResult: Int32
    let objcInstallResult: Int32

    enum CodingKeys: String, CodingKey {
        case captureResult = "capture_result"
        case tombstones
        case payloadBytes = "payload_bytes"
        case averageProbeLength = "average_probe_length"
        case sampledAllocations = "sampled_allocations"
        case reentrantSkips = "reentrant_skips"
        case recordedAllocations = "recorded_allocations"
        case droppedAllocRecords = "dropped_alloc_records"
        case liveOccupancy = "live_occupancy"
        case peakLiveOccupancy = "peak_live_occupancy"
        case droppedSamples = "dropped_samples"
        case maxProbeLength = "max_probe_length"
        case recorderStorageBytes = "recorder_storage_bytes"
        case encoderStorageBytes = "encoder_storage_bytes"
        case swiftInstallResult = "swift_install_result"
        case objcInstallResult = "objc_install_result"
    }

    init(
        result: CaptureResult,
        diagnostics: dd_memory_profiler_diagnostics_t,
        payloadBytes: Int = 0
    ) {
        self.captureResult = result
        self.payloadBytes = payloadBytes
        let live = diagnostics.window.live_set
        self.averageProbeLength = live.probe_count == 0 ? 0 : Double(live.total_probe_length) / Double(live.probe_count)
        self.sampledAllocations = diagnostics.sampled_allocations
        self.reentrantSkips = diagnostics.reentrant_skips
        self.recordedAllocations = diagnostics.window.recorded_allocations
        self.droppedAllocRecords = diagnostics.window.dropped_alloc_records
        self.liveOccupancy = live.occupancy
        self.peakLiveOccupancy = live.peak_occupancy
        self.droppedSamples = live.dropped_samples
        self.tombstones = live.tombstones
        self.maxProbeLength = live.max_probe_length
        self.recorderStorageBytes = diagnostics.recorder_storage_bytes
        self.encoderStorageBytes = diagnostics.encoder_storage_bytes
        self.swiftInstallResult = diagnostics.swift_install_result
        self.objcInstallResult = diagnostics.objc_install_result
    }

    static func consume(result: CaptureResult, payloadBytes: Int = 0) -> MemoryDiagnostics {
        MemoryDiagnostics(
            result: result,
            diagnostics: dd_memory_profiler_consume_diagnostics(),
            payloadBytes: payloadBytes
        )
    }
}
#endif
