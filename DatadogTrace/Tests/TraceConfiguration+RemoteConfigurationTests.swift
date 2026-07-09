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

    /// The `trace` namespace must enable network instrumentation (even when none was configured
    /// in-code) and set up distributed tracing for the given hosts. When header formats are provided,
    /// they apply to every traced host, and the remote `sampleRate` drives the tracing sample rate.
    func testWhenRemoteTraceProvidesHostsAndHeaderTypes_itConfiguresDistributedTracing() {
        // Given no in-code network instrumentation
        var configuration = Trace.Configuration(urlSessionTracking: nil)

        // When
        configuration.apply(remoteConfiguration: .mockWith(
            trace: .init(
                sampleRate: 55,
                traceContextInjection: .all,
                tracedHosts: ["api.example.com", "example.com"],
                tracingHeaderTypes: [.datadog, .b3]
            )
        ))

        // Then
        guard case let .traceWithHeaders(hostsWithHeaders, sampleRate, injection) =
            configuration.urlSessionTracking?.firstPartyHostsTracing else {
            return XCTFail("Expected `.traceWithHeaders` first-party hosts tracing to be configured")
        }
        XCTAssertEqual(hostsWithHeaders, [
            "api.example.com": [.datadog, .b3],
            "example.com": [.datadog, .b3]
        ])
        XCTAssertEqual(sampleRate, 55)
        XCTAssertEqual(injection, .all)
    }

    /// When the `trace` namespace provides hosts but no header formats, Trace falls back to the default
    /// trace headers and the default sample rate / injection strategy.
    func testWhenRemoteTraceProvidesHostsWithoutHeaderTypes_itUsesDefaultTraceHeaders() {
        var configuration = Trace.Configuration(urlSessionTracking: nil)

        configuration.apply(remoteConfiguration: .mockWith(trace: .init(tracedHosts: ["example.com"])))

        guard case let .trace(hosts, sampleRate, injection) =
            configuration.urlSessionTracking?.firstPartyHostsTracing else {
            return XCTFail("Expected `.trace` first-party hosts tracing to be configured")
        }
        XCTAssertEqual(hosts, ["example.com"])
        XCTAssertEqual(sampleRate, .maxSampleRate) // default when the remote omits `sampleRate`
        XCTAssertEqual(injection, .sampled) // default when the remote omits `traceContextInjection`
    }

    /// A `trace` namespace without hosts has nothing to instrument and must leave the configuration's
    /// network instrumentation untouched (only the span sample rate is affected).
    func testWhenRemoteTraceHasNoHosts_itLeavesNetworkInstrumentationUnchanged() {
        var configuration = Trace.Configuration(sampleRate: 10, urlSessionTracking: nil)

        configuration.apply(remoteConfiguration: .mockWith(trace: .mockWith(sampleRate: 42, tracedHosts: nil)))

        XCTAssertEqual(configuration.sampleRate, 42, "The span sample rate is still overridden")
        XCTAssertNil(configuration.urlSessionTracking, "No hosts means nothing to instrument")
    }

    /// An explicit empty host list means "stop propagating traces": it must clear the in-code
    /// first-party hosts tracing (no host stays first-party) while keeping the rest of the network
    /// instrumentation (e.g. redacted status codes).
    func testWhenRemoteTraceHasEmptyHosts_itClearsInCodeTracing() {
        var configuration = Trace.Configuration(
            urlSessionTracking: .init(
                firstPartyHostsTracing: .trace(hosts: ["in-code.example.com"]),
                redactedStatusCodes: [401, 403]
            )
        )

        configuration.apply(remoteConfiguration: .mockWith(trace: .init(tracedHosts: [])))

        guard case let .trace(hosts, _, _) = configuration.urlSessionTracking?.firstPartyHostsTracing else {
            return XCTFail("Expected `.trace` first-party hosts tracing to be configured")
        }
        XCTAssertEqual(hosts, [])
        XCTAssertEqual(configuration.urlSessionTracking?.redactedStatusCodes, [401, 403])
    }

    /// An explicit empty host list has nothing to clear when no network instrumentation was configured
    /// in-code, so the configuration must stay untouched (no default instrumentation is installed).
    func testWhenRemoteTraceHasEmptyHostsAndNoInCodeInstrumentation_itLeavesConfigurationUnchanged() {
        var configuration = Trace.Configuration(urlSessionTracking: nil)

        configuration.apply(remoteConfiguration: .mockWith(trace: .init(tracedHosts: [])))

        XCTAssertNil(configuration.urlSessionTracking)
    }

    /// When the developer already configured `urlSessionTracking`, applying remote hosts must replace
    /// only its first-party hosts tracing while preserving its other settings (e.g. redacted status
    /// codes).
    func testWhenRemoteTraceProvidesHosts_itPreservesOtherURLSessionTrackingSettings() {
        var configuration = Trace.Configuration(
            urlSessionTracking: .init(
                firstPartyHostsTracing: .trace(hosts: ["in-code.example.com"]),
                redactedStatusCodes: [401, 403]
            )
        )

        configuration.apply(remoteConfiguration: .mockWith(trace: .init(tracedHosts: ["remote.example.com"])))

        guard case let .trace(hosts, _, _) = configuration.urlSessionTracking?.firstPartyHostsTracing else {
            return XCTFail("Expected `.trace` first-party hosts tracing to be configured")
        }
        XCTAssertEqual(hosts, ["remote.example.com"], "First-party hosts tracing is replaced by the remote hosts")
        XCTAssertEqual(configuration.urlSessionTracking?.redactedStatusCodes, [401, 403], "Other settings are preserved")
    }
}
