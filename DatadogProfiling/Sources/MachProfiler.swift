/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// swiftlint:disable duplicate_imports
#if swift(>=6.0)
internal import DatadogMachProfiler
#else
@_implementationOnly import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

internal final class MachProfiler: Profiler {
    internal let samplingIntervalNs: UInt64

    private var profiler: OpaquePointer?
    private var profile: OpaquePointer?

    init(samplingFrequencyHz: Double = 101) {
        self.samplingIntervalNs = UInt64(1_000_000_000 / samplingFrequencyHz) // Convert Hz to nanoseconds
    }

    deinit {
        profiler_stop(profiler)
        profiler_destroy(profiler)
        dd_pprof_destroy(profile)
    }

    func start(currentThreadOnly: Bool) {
        guard profile == nil else {
            return
        }
        profile = dd_pprof_create(samplingIntervalNs)

        var config = sampling_config_t(
            sampling_interval_nanos: samplingIntervalNs,
            profile_current_thread_only: currentThreadOnly ? 1 : 0,
            max_buffer_size: 1_000,
            max_stack_depth: 128,
            max_thread_count: 100,
            qos_class: QOS_CLASS_USER_INTERACTIVE
        )

        profiler = profiler_create(&config, dd_pprof_callback, UnsafeMutableRawPointer(profile))

        profiler_start(profiler)
    }

    func stop() throws -> Profile? {
        guard profile != nil else {
            return nil
        }

        profiler_stop(profiler)
        let start = dd_pprof_get_start_timestamp_s(profile)
        let end = dd_pprof_get_end_timestamp_s(profile)
        profiler_destroy(profiler)
        profiler = nil

        var data: UnsafeMutablePointer<UInt8>?
        let size = dd_pprof_serialize(profile, &data)
        dd_pprof_destroy(profile)
        profile = nil

        guard let data = data else {
            throw ProgrammerError(description: "Failed to serialise pprof data")
        }

        let pprof = Data(bytes: data, count: size)
        dd_pprof_free_serialized_data(data)

        return Profile(
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            pprof: pprof
        )
    }
}
