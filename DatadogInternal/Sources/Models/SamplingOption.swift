/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// Whether a feature is off or on with a sample rate.
public enum SamplingOption {
    /// Feature is disabled.
    case disabled
    /// Feature is enabled with the given sample rate.
    ///
    /// - Parameter sampleRate: The sampling rate of the feature. Must be a value between `0.0` and `100.0`.
    ///                         `0` means the feature is disabled and `100` means it is enabled.
    case enabled(sampleRate: SampleRate)
}

extension SamplingOption {
    /// Enabled with a 100% sample rate.
    public static var enabled: SamplingOption {
        .enabled(sampleRate: 100.0)
    }

    /// The sample rate for this feature.
    public var sampleRate: SampleRate {
        switch self {
        case .disabled: 0.0
        case let .enabled(sampleRate): sampleRate
        }
    }
}
