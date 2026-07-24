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
            sessionReplay: .mockRandom(),
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
            appHang: .mockRandom(),
            applicationId: .mockRandom(),
            longTask: .mockRandom(),
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
        appHang: RemoteConfiguration.RUM.AppHang? = nil,
        applicationId: String = .mockAny(),
        longTask: RemoteConfiguration.RUM.LongTask? = nil,
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
            appHang: appHang,
            applicationId: applicationId,
            longTask: longTask,
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

extension RemoteConfiguration.RUM.AppHang: AnyMockable, RandomMockable {
    public static func mockAny() -> RemoteConfiguration.RUM.AppHang {
        mockWith()
    }

    /// `enabled` is fixed to `true` so callers exercising every field (e.g. exhaustiveness checks) can
    /// rely on `threshold` always taking effect; use `mockWith(enabled:)` to test `enabled == false`.
    public static func mockRandom() -> RemoteConfiguration.RUM.AppHang {
        .init(enabled: true, threshold: .mockRandom(min: 100, max: 5_000))
    }

    public static func mockWith(
        enabled: Bool? = nil,
        threshold: Double? = nil
    ) -> RemoteConfiguration.RUM.AppHang {
        .init(enabled: enabled, threshold: threshold)
    }
}

extension RemoteConfiguration.RUM.LongTask: AnyMockable, RandomMockable {
    public static func mockAny() -> RemoteConfiguration.RUM.LongTask {
        mockWith()
    }

    /// `enabled` is fixed to `true` so callers exercising every field (e.g. exhaustiveness checks) can
    /// rely on `threshold` always taking effect; use `mockWith(enabled:)` to test `enabled == false`.
    public static func mockRandom() -> RemoteConfiguration.RUM.LongTask {
        .init(enabled: true, threshold: .mockRandom(min: 100, max: 5_000))
    }

    public static func mockWith(
        enabled: Bool? = nil,
        threshold: Double? = nil
    ) -> RemoteConfiguration.RUM.LongTask {
        .init(enabled: enabled, threshold: threshold)
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
            tracedHosts: [.mockRandom(), .mockRandom()]
        )
    }

    public static func mockWith(
        sampleRate: Double? = nil,
        traceContextInjection: RemoteConfiguration.Trace.TraceContextInjection? = nil,
        tracedHosts: [RemoteConfiguration.Trace.TracedHosts]? = nil
    ) -> RemoteConfiguration.Trace {
        .init(
            sampleRate: sampleRate,
            traceContextInjection: traceContextInjection,
            tracedHosts: tracedHosts
        )
    }
}

extension RemoteConfiguration.Trace.TraceContextInjection: RandomMockable {
    public static func mockRandom() -> RemoteConfiguration.Trace.TraceContextInjection {
        [.all, .sampled].randomElement()!
    }
}

extension RemoteConfiguration.Trace.TracedHosts: AnyMockable, RandomMockable {
    public static func mockAny() -> RemoteConfiguration.Trace.TracedHosts {
        .init(host: .mockAny(), propagatorTypes: [.mockRandom()])
    }

    public static func mockRandom() -> RemoteConfiguration.Trace.TracedHosts {
        .init(host: .mockRandom(), propagatorTypes: [.mockRandom()])
    }
}

extension RemoteConfiguration.Trace.TracedHosts.PropagatorTypes: RandomMockable {
    public static func mockRandom() -> RemoteConfiguration.Trace.TracedHosts.PropagatorTypes {
        [.datadog, .b3, .b3multi, .tracecontext].randomElement()!
    }
}

extension RemoteConfiguration.SessionReplay: AnyMockable, RandomMockable {
    public static func mockAny() -> RemoteConfiguration.SessionReplay {
        mockWith()
    }

    /// Builds a `sessionReplay` namespace with **every** field populated with a random, non-`nil` value.
    ///
    /// Keeping all fields populated is what lets the exhaustiveness guard in
    /// `SessionReplayConfiguration_RemoteConfigurationTests` detect any newly generated schema field.
    public static func mockRandom() -> RemoteConfiguration.SessionReplay {
        .init(
            imagePrivacy: .mockRandom(),
            sampleRate: .mockRandom(min: 0, max: 100),
            textAndInputPrivacy: .mockRandom(),
            touchPrivacy: .mockRandom()
        )
    }

    public static func mockWith(
        imagePrivacy: RemoteConfiguration.SessionReplay.ImagePrivacy? = nil,
        sampleRate: Double? = nil,
        textAndInputPrivacy: RemoteConfiguration.SessionReplay.TextAndInputPrivacy? = nil,
        touchPrivacy: RemoteConfiguration.SessionReplay.TouchPrivacy? = nil
    ) -> RemoteConfiguration.SessionReplay {
        .init(
            imagePrivacy: imagePrivacy,
            sampleRate: sampleRate,
            textAndInputPrivacy: textAndInputPrivacy,
            touchPrivacy: touchPrivacy
        )
    }
}

extension RemoteConfiguration.SessionReplay.ImagePrivacy: RandomMockable {
    public static func mockRandom() -> RemoteConfiguration.SessionReplay.ImagePrivacy {
        [.maskNone, .maskNonBundledOnly, .maskAll].randomElement()!
    }
}

extension RemoteConfiguration.SessionReplay.TextAndInputPrivacy: RandomMockable {
    public static func mockRandom() -> RemoteConfiguration.SessionReplay.TextAndInputPrivacy {
        [.maskSensitiveInputs, .maskAllInputs, .maskAll].randomElement()!
    }
}

extension RemoteConfiguration.SessionReplay.TouchPrivacy: RandomMockable {
    public static func mockRandom() -> RemoteConfiguration.SessionReplay.TouchPrivacy {
        [.show, .hide].randomElement()!
    }
}
