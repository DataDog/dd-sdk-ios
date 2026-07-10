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
            rum: .mockRandom(),
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

extension RemoteConfiguration.RUM: AnyMockable, RandomMockable {
    public static func mockAny() -> RemoteConfiguration.RUM {
        mockWith()
    }

    /// Builds a `rum` namespace with **every** field populated with a random, non-`nil` value.
    ///
    /// Keeping all fields populated is what lets the exhaustiveness guard in
    /// `RUMConfiguration_RemoteConfigurationTests` detect any newly generated schema field.
    public static func mockRandom() -> RemoteConfiguration.RUM {
        .init(
            appHangThresholdMs: .mockRandom(min: 100, max: 5_000),
            applicationId: .mockRandom(),
            env: .mockRandom(),
            longTaskThresholdMs: .mockRandom(min: 100, max: 5_000),
            service: .mockRandom(),
            telemetrySampleRate: .mockRandom(min: 0, max: 100),
            trackAnonymousUser: .mockRandom(),
            trackBackgroundEvents: .mockRandom(),
            trackFrustrations: .mockRandom(),
            trackMemoryWarnings: .mockRandom(),
            trackResources: .mockRandom(),
            trackSlowFrames: .mockRandom(),
            trackUserInteractions: .mockRandom(),
            trackWatchdogTerminations: .mockRandom(),
            vitalsUpdateFrequency: .mockRandom()
        )
    }

    public static func mockWith(
        appHangThresholdMs: Double? = nil,
        applicationId: String = .mockAny(),
        env: String? = nil,
        longTaskThresholdMs: Double? = nil,
        service: String? = nil,
        telemetrySampleRate: Double? = nil,
        trackAnonymousUser: Bool? = nil,
        trackBackgroundEvents: Bool? = nil,
        trackFrustrations: Bool? = nil,
        trackMemoryWarnings: Bool? = nil,
        trackResources: Bool? = nil,
        trackSlowFrames: Bool? = nil,
        trackUserInteractions: Bool? = nil,
        trackWatchdogTerminations: Bool? = nil,
        vitalsUpdateFrequency: RemoteConfiguration.RUM.VitalsUpdateFrequency? = nil
    ) -> RemoteConfiguration.RUM {
        .init(
            appHangThresholdMs: appHangThresholdMs,
            applicationId: applicationId,
            env: env,
            longTaskThresholdMs: longTaskThresholdMs,
            service: service,
            telemetrySampleRate: telemetrySampleRate,
            trackAnonymousUser: trackAnonymousUser,
            trackBackgroundEvents: trackBackgroundEvents,
            trackFrustrations: trackFrustrations,
            trackMemoryWarnings: trackMemoryWarnings,
            trackResources: trackResources,
            trackSlowFrames: trackSlowFrames,
            trackUserInteractions: trackUserInteractions,
            trackWatchdogTerminations: trackWatchdogTerminations,
            vitalsUpdateFrequency: vitalsUpdateFrequency
        )
    }
}

extension RemoteConfiguration.RUM.VitalsUpdateFrequency: RandomMockable {
    public static func mockRandom() -> RemoteConfiguration.RUM.VitalsUpdateFrequency {
        [.frequent, .average, .rare, .never].randomElement()!
    }
}

extension RemoteConfiguration.Trace: AnyMockable, RandomMockable {
    public static func mockAny() -> RemoteConfiguration.Trace {
        mockWith()
    }

    /// Builds a `trace` namespace with **every** field populated with a random, non-`nil` value.
    ///
    /// Keeping all fields populated is what lets the exhaustiveness guard in
    /// `TraceConfiguration_RemoteConfigurationTests` detect any newly generated schema field.
    public static func mockRandom() -> RemoteConfiguration.Trace {
        .init(
            sampleRate: .mockRandom(min: 0, max: 100),
            traceContextInjection: .mockRandom(),
            tracedHosts: ["api.example.com", "example.com"],
            tracingHeaderTypes: [.mockRandom()]
        )
    }

    public static func mockWith(
        sampleRate: Double? = nil,
        traceContextInjection: RemoteConfiguration.Trace.TraceContextInjection? = nil,
        tracedHosts: [String]? = nil,
        tracingHeaderTypes: [RemoteConfiguration.Trace.TracingHeaderTypes]? = nil
    ) -> RemoteConfiguration.Trace {
        .init(
            sampleRate: sampleRate,
            traceContextInjection: traceContextInjection,
            tracedHosts: tracedHosts,
            tracingHeaderTypes: tracingHeaderTypes
        )
    }
}

extension RemoteConfiguration.Trace.TraceContextInjection: RandomMockable {
    public static func mockRandom() -> RemoteConfiguration.Trace.TraceContextInjection {
        [.all, .sampled].randomElement()!
    }
}

extension RemoteConfiguration.Trace.TracingHeaderTypes: RandomMockable {
    public static func mockRandom() -> RemoteConfiguration.Trace.TracingHeaderTypes {
        [.datadog, .b3, .b3multi, .tracecontext].randomElement()!
    }
}
