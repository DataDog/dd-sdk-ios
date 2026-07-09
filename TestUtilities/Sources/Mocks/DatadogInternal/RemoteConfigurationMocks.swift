/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension RemoteConfiguration: AnyMockable, RandomMockable {
    public static func mockAny() -> RemoteConfiguration {
        mockWith()
    }

    public static func mockRandom() -> RemoteConfiguration {
        .init(
            profiling: .mockRandom(),
            rum: nil,
            sessionReplay: nil,
            trace: nil
        )
    }

    public static func mockWith(
        profiling: RemoteConfiguration.Profiling? = nil,
        rum: RemoteConfiguration.RUM? = nil,
        sessionReplay: RemoteConfiguration.SessionReplay? = nil,
        trace: RemoteConfiguration.Trace? = nil
    ) -> RemoteConfiguration {
        .init(
            profiling: profiling,
            rum: rum,
            sessionReplay: sessionReplay,
            trace: trace
        )
    }
}

extension RemoteConfiguration.Profiling: AnyMockable, RandomMockable {
    public static func mockAny() -> RemoteConfiguration.Profiling {
        mockWith()
    }

    /// Builds a `profiling` namespace with **every** field populated with a random, non-`nil` value.
    ///
    /// Keeping all fields populated is what lets the exhaustiveness guard in
    /// `ProfilingConfiguration_RemoteConfigurationTests` detect any newly generated schema field.
    public static func mockRandom() -> RemoteConfiguration.Profiling {
        .init(
            applicationLaunchSampleRate: .mockRandom(min: 0, max: 100),
            continuousSampleRate: .mockRandom(min: 0, max: 100)
        )
    }

    public static func mockWith(
        applicationLaunchSampleRate: Double? = nil,
        continuousSampleRate: Double? = nil
    ) -> RemoteConfiguration.Profiling {
        .init(
            applicationLaunchSampleRate: applicationLaunchSampleRate,
            continuousSampleRate: continuousSampleRate
        )
    }
}
