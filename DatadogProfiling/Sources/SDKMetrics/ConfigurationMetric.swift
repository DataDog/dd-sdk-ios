/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if !os(watchOS)

// swiftlint:disable duplicate_imports
#if swift(>=6.0)
internal import DatadogMachProfiler
#else
@_implementationOnly import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

/// Tracks the profiling configuration to be added to telemetry metrics.
internal final class ConfigurationMetric {
    internal enum Constants {
        /// Namespace for bundling the profiling configuration.
        static let configurationKey = "profiling_config"
        static let defaultBufferSize = Int(SAMPLING_CONFIG_DEFAULT_BUFFER_SIZE)
        static let defaultStackDepth = Int(SAMPLING_CONFIG_DEFAULT_STACK_DEPTH)
        static let defaultThreadCount = Int(SAMPLING_CONFIG_DEFAULT_THREAD_COUNT)
        static let defaultSamplingFrequency = Int(SAMPLING_CONFIG_DEFAULT_INTERVAL_HZ)
    }

    /// Max number of samples of the profile.
    let bufferSize: Int
    /// Max number of frames per trace.
    let stackDepth: Int
    /// Number of threads covered in the process.
    let threadCoverage: Int
    /// Sampling rate in Hz.
    let samplingFrequency: Int

    init(
        bufferSize: Int = Constants.defaultBufferSize,
        stackDepth: Int = Constants.defaultStackDepth,
        threadCoverage: Int = Constants.defaultThreadCount,
        samplingFrequency: Int = Constants.defaultSamplingFrequency
    ) {
        self.bufferSize = bufferSize
        self.stackDepth = stackDepth
        self.threadCoverage = threadCoverage
        self.samplingFrequency = samplingFrequency
    }

    func asMetricAttributes() -> [String: Encodable]? {
        [Constants.configurationKey: self]
    }
}

extension ConfigurationMetric: Encodable {
    enum CodingKeys: String, CodingKey {
        case bufferSize = "buffer_size"
        case stackDepth = "stack_depth"
        case threadCoverage = "thread_coverage"
        case samplingFrequency = "sampling_frequency"
    }
}

#endif
