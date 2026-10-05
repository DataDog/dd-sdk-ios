/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogTrace

class TraceConfiguration_RemoteConfigurationTests: XCTestCase {
    /// When there is no remote configuration (`nil`) or its `trace` namespace is absent, Trace must
    /// behave exactly as configured in-code.
    func testWhenNoRemoteValuesAreProvided_itLeavesConfigurationUnchanged() {
        let baseline = Trace.Configuration(
            sampleRate: 42,
            urlSessionTracking: .init(firstPartyHostsTracing: .trace(hosts: ["in-code.example.com"]))
        )

        var withNilRemote = baseline
        withNilRemote.apply(remoteConfiguration: nil)
        DDAssertReflectionEqual(withNilRemote, baseline)

        var withEmptyRemote = baseline
        withEmptyRemote.apply(remoteConfiguration: .mockWith()) // every namespace absent
        DDAssertReflectionEqual(withEmptyRemote, baseline)

        var withEmptyNamespace = baseline
        withEmptyNamespace.apply(remoteConfiguration: .mockWith(trace: .mockWith())) // all fields absent
        DDAssertReflectionEqual(withEmptyNamespace, baseline)
    }

    /// A remote `sampleRate` overrides the span sample rate.
    func testWhenRemoteProvidesSampleRate_itOverridesSpanSampleRate() {
        var configuration = Trace.Configuration(sampleRate: 10)

        configuration.apply(remoteConfiguration: .mockWith(trace: .mockWith(sampleRate: 90)))

        XCTAssertEqual(configuration.sampleRate, 90)
    }

    /// The `trace` namespace no longer drives URLSession instrumentation — that is owned by RUM's remote
    /// configuration instead, to avoid registering overlapping URLSession handlers when both modules are
    /// enabled.
    func testWhenRemoteTraceProvidesHosts_itLeavesNetworkInstrumentationUnchanged() {
        var configuration = Trace.Configuration(urlSessionTracking: nil)

        configuration.apply(remoteConfiguration: .mockWith(
            trace: .init(
                sampleRate: 55,
                traceContextInjection: .all,
                tracedHosts: [
                    .init(host: "api.example.com", propagatorTypes: [.datadog, .b3]),
                    .init(host: "example.com", propagatorTypes: [.datadog, .b3])
                ]
            )
        ))

        XCTAssertEqual(configuration.sampleRate, 55, "The span sample rate is still overridden")
        XCTAssertNil(configuration.urlSessionTracking, "Hosts are ignored: distributed tracing is enabled through RUM's remote configuration")
    }
}
