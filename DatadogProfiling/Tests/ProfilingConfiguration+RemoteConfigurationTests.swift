/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogProfiling

class ProfilingConfiguration_RemoteConfigurationTests: XCTestCase {
    /// When there is no remote configuration (`nil`) or its `profiling` namespace is absent, Profiling
    /// must behave exactly as configured in-code.
    func testWhenNoRemoteValuesAreProvided_itLeavesConfigurationUnchanged() {
        let baseline = Profiling.Configuration(
            customEndpoint: .mockRandom(),
            applicationLaunchSampleRate: 42
        )

        var withNilRemote = baseline
        withNilRemote.apply(remoteConfiguration: nil)
        DDAssertReflectionEqual(withNilRemote, baseline)

        var withEmptyRemote = baseline
        withEmptyRemote.apply(remoteConfiguration: .mockWith()) // every namespace absent
        DDAssertReflectionEqual(withEmptyRemote, baseline)

        var withEmptyNamespace = baseline
        withEmptyNamespace.apply(remoteConfiguration: .mockWith(profiling: .mockWith())) // all fields absent
        DDAssertReflectionEqual(withEmptyNamespace, baseline)
    }

    /// A remote `applicationLaunchSampleRate` overrides the in-code value, regardless of the baseline.
    func testItOverridesApplicationLaunchSampleRateFromRemoteValue() throws {
        for _ in 0..<100 {
            // Given
            let profiling: RemoteConfiguration.Profiling = .mockRandom()
            var configuration = Profiling.Configuration(
                applicationLaunchSampleRate: .mockRandom(min: 0, max: 100)
            )

            // When
            configuration.apply(remoteConfiguration: .mockWith(profiling: profiling))

            // Then
            XCTAssertEqual(
                configuration.applicationLaunchSampleRate,
                SampleRate(try XCTUnwrap(profiling.applicationLaunchSampleRate))
            )
        }
    }

    /// `continuousSampleRate` has no in-code equivalent, so providing it must not change the
    /// configuration.
    func testWhenRemoteProvidesOnlyContinuousSampleRate_itLeavesConfigurationUnchanged() {
        let baseline = Profiling.Configuration(applicationLaunchSampleRate: 42)

        var configuration = baseline
        configuration.apply(remoteConfiguration: .mockWith(profiling: .mockWith(continuousSampleRate: 99)))

        DDAssertReflectionEqual(configuration, baseline)
    }
}

#endif
