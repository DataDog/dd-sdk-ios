/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

public enum ProfilingOption {
    case disabled
    /// It must be a number between 0.0 and 100.0, where 0 means no profiles will be collected.
    ///
    case enabled(sampleRate: SampleRate)
}

extension ProfilingOption {
    /// Convenience for 100% sampling
    public static var enabled: ProfilingOption {
        return .enabled(sampleRate: 100.0)
    }

    public var sampleRate: SampleRate {
        switch self {
        case .disabled: 0.0
        case let .enabled(sampleRate): sampleRate
        }
    }
}
